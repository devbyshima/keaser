import Foundation

/// The remote half of sync: writing what iCloud sent into the database.
///
/// Rules, per record:
/// - Unchanged here since iCloud last had it: iCloud's version is taken.
/// - Changed on both sides: the later edit wins (`SyncRecord.wins(over:)`;
///   equal times are decided by the payloads, the same way on every
///   device). The settings and the list orders are the exception on a
///   device that has never synced them: iCloud's copy wins
///   (`SyncKind.remoteWinsFirstMeeting`). Either way the pass start stays
///   the earliest of the two.
/// - Deleted here, edited in iCloud: the edit wins only when it is later
///   than the deletion (`Tombstone.deletedAt`); otherwise the deletion
///   still goes out.
/// - Deleted in iCloud, edited here since: the edit wins and the record is
///   sent again as a new one. Nothing typed on one device is lost because
///   another device deleted it at the same time.
/// - Deleted in iCloud, unchanged here: it goes. An account goes with
///   everything in it.
///
/// Integrity: an item whose account has not arrived waits (`parked`) and is
/// applied when the account comes; one whose account was deleted here is
/// deleted too. An expense keeps working when its category or payment
/// method is deleted elsewhere: an ID that matches no label reads as none.
/// Two labels of the same name in one account (made independently on two
/// devices) become one, and on a device's first sync an account it made
/// that has the name of an account already in iCloud merges into it, so a
/// second device adds to the person's data instead of duplicating it.
/// The database and sync state after a merge, and the files it let go.
public struct SyncMergeResult: Sendable {
    public var database: Database
    public var state: SyncState
    /// Files of records iCloud deleted that nothing here refers to any
    /// more (receipt photos). The app removes them once the database is
    /// saved.
    public var removedAssets: [SyncAsset]
}

public enum SyncMerge {
    /// How long an empty account made on a device that has never synced is
    /// taken to be a placeholder: set up moments before iCloud's accounts
    /// arrived on a new device.
    public static let placeholderAccountAge: TimeInterval = 3600

    /// Applies the state's inbox, and retries what is parked, returning
    /// the merged database and the state with the inbox emptied. Pure: the
    /// caller saves both, the database first.
    public static func apply(to database: Database, state: SyncState, now: Date) -> SyncMergeResult {
        var db = database
        var st = state
        let initial = !st.hasCompletedInitialSync
        let inbox = st.inbox
        st.inbox = [:]

        applyDeletions(inbox, to: &db, state: &st)
        applySaves(inbox, to: &db, state: &st, now: now)

        var redirects: [UUID: UUID] = [:]
        if initial {
            mergeNewAccounts(&db, state: st, now: now, redirects: &redirects)
            dropPlaceholderAccounts(&db, state: st, now: now, redirects: &redirects)
        }
        for index in db.accounts.indices {
            mergeSameNamedLabels(in: &db.accounts[index], list: \.categories, type: .category, reference: \.categoryID, state: st, now: now)
            mergeSameNamedLabels(in: &db.accounts[index], list: \.paymentMethods, type: .paymentMethod, reference: \.paymentMethodID, state: st, now: now)
        }
        OrderSyncKind.arrangeByKnownOrders(&db, known: st.known)

        if let selected = db.preferences.selectedAccountID, !db.accounts.contains(where: { $0.id == selected }) {
            db.preferences.selectedAccountID = redirects[selected] ?? db.accounts.first?.id
        }
        return SyncMergeResult(database: db, state: st, removedAssets: removedAssets(inbox, in: db))
    }

    /// The files of the records iCloud deleted that the merged database no
    /// longer holds.
    private static func removedAssets(_ inbox: [String: InboxItem], in db: Database) -> [SyncAsset] {
        inbox.sorted { $0.key < $1.key }.flatMap { name, item -> [SyncAsset] in
            guard case .deleted(let type) = item, let kind = SyncKinds.kind(for: type) ?? SyncKinds.kind(forName: name),
                  kind.record(named: name, in: db) == nil
            else { return [] }
            return kind.assets(named: name)
        }
    }

    // MARK: Deletions

    private static func applyDeletions(_ inbox: [String: InboxItem], to db: inout Database, state st: inout SyncState) {
        for (name, item) in inbox.sorted(by: { $0.key < $1.key }) {
            guard case .deleted(let type) = item else { continue }
            let base = st.known.removeValue(forKey: name)
            let wasParked = st.parked.removeValue(forKey: name) != nil
            st.tombstones[name] = nil
            guard let kind = SyncKinds.kind(for: type) ?? SyncKinds.kind(forName: name),
                  let local = kind.record(named: name, in: db)
            else { continue }
            // A copy older than one this build could not read is stale;
            // otherwise a copy changed here since outlives the deletion.
            let changedHere = base.map { kind.isPending(SyncPlan.outgoing(local, extras: $0.extras), known: $0) } ?? true
            guard wasParked || !changedHere else { continue }
            kind.remove(named: name, from: &db)
            if type == .account, let id = SyncRecordName.id(in: name) {
                st.parked = st.parked.filter { $0.value.record?.parent != id }
            }
        }
    }

    // MARK: Saves

    private static func applySaves(_ inbox: [String: InboxItem], to db: inout Database, state st: inout SyncState, now: Date) {
        var incoming: [FetchedRecord] = inbox.values.compactMap { item in
            if case .saved(let record) = item { return record }
            return nil
        }
        // What waited is tried again, unless iCloud has since sent a newer
        // word on it.
        for (name, parked) in st.parked where inbox[name] == nil {
            incoming.append(parked)
        }
        st.parked = [:]
        func rank(_ fetched: FetchedRecord) -> Int {
            SyncKinds.kind(for: fetched.type)?.rank ?? Int.max
        }
        incoming.sort { (rank($0), $0.name) < (rank($1), $1.name) }
        for fetched in incoming {
            applySave(fetched, to: &db, state: &st, now: now)
        }
    }

    private static func applySave(_ fetched: FetchedRecord, to db: inout Database, state st: inout SyncState, now: Date) {
        let name = fetched.name
        let base = st.known[name]
        let systemFields = fetched.systemFields ?? base?.systemFields
        guard let record = fetched.record,
              record.readerVersion <= SyncSchema.readerVersion,
              let kind = SyncKinds.kind(for: record.type),
              let canonical = kind.canonical(record)
        else {
            // A later version's record: kept exactly as it is, never
            // applied, overwritten or deleted by this build.
            st.parked[name] = fetched
            st.known[name] = KnownRecord(
                type: fetched.type, fingerprint: SyncFingerprint.of(fetched.payload),
                modifiedAt: fetched.record?.modifiedAt ?? .distantPast,
                parent: fetched.record?.parent, systemFields: systemFields
            )
            return
        }
        let extras = SyncPlan.extras(of: record, canonical: canonical)
        let remote = SyncPlan.outgoing(canonical, extras: extras)
        var entry = KnownRecord(
            type: record.type, fingerprint: remote.fingerprint, modifiedAt: canonical.modifiedAt,
            parent: canonical.parent, extras: extras, systemFields: systemFields
        )
        if record.type == .order { entry.orderIDs = OrderSyncKind.ids(in: canonical) }
        defer { st.known[name] = entry }

        if let tombstone = st.tombstones[name] {
            // Deleted here: an edit made after the deletion brings it back.
            guard canonical.modifiedAt > tombstone.deletedAt else { return }
            st.tombstones[name] = nil
        } else if let found = kind.record(named: name, in: db) {
            let local = SyncPlan.outgoing(found, extras: extras)
            if local.fingerprint == remote.fingerprint { return }
            let changedHere = base.map { kind.isPending(SyncPlan.outgoing(found, extras: $0.extras), known: $0) } ?? true
            let remoteWins = !changedHere
                || (base == nil && kind.remoteWinsFirstMeeting)
                || remote.wins(over: local)
            guard remoteWins else {
                // This device's edit stands and goes out over iCloud's.
                kind.absorb(canonical, into: &db)
                return
            }
        }

        switch kind.apply(canonical, to: &db) {
        case .applied:
            break
        case .needsAccount(let accountID):
            if st.tombstones[SyncRecordName.make(.account, accountID)] != nil {
                // Its account was deleted here, so it goes too.
                st.tombstones[name] = Tombstone(type: record.type, deletedAt: now)
            } else {
                st.parked[name] = fetched
            }
        case .unreadable:
            st.parked[name] = fetched
        }
    }

    // MARK: Duplicates

    /// On a first sync: each account this device made that iCloud does not
    /// have yet, named like one iCloud has, merges into that one. Its
    /// categories and payment methods join the account's (a label of the
    /// same name becomes the existing one) and its expenses move over.
    private static func mergeNewAccounts(_ db: inout Database, state st: SyncState, now: Date, redirects: inout [UUID: UUID]) {
        let inCloud = db.accounts.filter { isKnown(.account, $0.id, st) }
        guard !inCloud.isEmpty else { return }
        for local in db.accounts where !isKnown(.account, local.id, st) {
            let key = labelKey(local.name)
            let matches = inCloud.filter { labelKey($0.name) == key }
            guard let target = matches.min(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }) else { continue }
            merge(local.id, into: target.id, &db, state: st, now: now)
            redirects[local.id] = target.id
        }
    }

    private static func merge(_ sourceID: UUID, into targetID: UUID, _ db: inout Database, state st: SyncState, now: Date) {
        guard let s = db.accounts.firstIndex(where: { $0.id == sourceID }),
              let t = db.accounts.firstIndex(where: { $0.id == targetID })
        else { return }
        let source = db.accounts[s]
        var target = db.accounts[t]
        var categories: [UUID: UUID] = [:]
        for category in source.categories {
            if let same = target.categories.first(where: { labelKey($0.name) == labelKey(category.name) }) {
                categories[category.id] = same.id
            } else {
                target.categories.append(category)
                target.categoriesOrderedAt = now
            }
        }
        var methods: [UUID: UUID] = [:]
        for method in source.paymentMethods {
            if let same = target.paymentMethods.first(where: { labelKey($0.name) == labelKey(method.name) }) {
                methods[method.id] = same.id
            } else {
                target.paymentMethods.append(method)
                target.paymentMethodsOrderedAt = now
            }
        }
        for var expense in source.expenses {
            if let id = expense.categoryID, let same = categories[id] { expense.categoryID = same }
            if let id = expense.paymentMethodID, let same = methods[id] { expense.paymentMethodID = same }
            // One already in iCloud under the old account must win there.
            if isKnown(.expense, expense.id, st) { expense.updatedAt = max(expense.updatedAt, now) }
            target.expenses.append(expense)
        }
        db.accounts[t] = target
        db.accounts.remove(at: s)
    }

    /// On a first sync that brought accounts from iCloud: an account this
    /// device made within the hour, with nothing in it but the built-in
    /// labels, is the placeholder of a new device's setup and goes.
    private static func dropPlaceholderAccounts(_ db: inout Database, state st: SyncState, now: Date, redirects: inout [UUID: UUID]) {
        guard let first = db.accounts.first(where: { isKnown(.account, $0.id, st) }) else { return }
        let defaultCategories = Set(ExpenseCategory.defaults().map { labelKey($0.name) })
        let defaultMethods = Set(PaymentMethod.defaults().map { labelKey($0.name) })
        db.accounts.removeAll { account in
            let isPlaceholder = !isKnown(.account, account.id, st)
                && account.expenses.isEmpty
                && now.timeIntervalSince(account.createdAt) < placeholderAccountAge
                && account.categories.allSatisfy { defaultCategories.contains(labelKey($0.name)) }
                && account.paymentMethods.allSatisfy { defaultMethods.contains(labelKey($0.name)) }
            if isPlaceholder { redirects[account.id] = first.id }
            return isPlaceholder
        }
    }

    /// Labels of one name in one account are one label (the editors never
    /// allow two). The one iCloud has wins, or of two it has, the smaller
    /// ID, so every device picks the same; expenses filed under the others
    /// move to it. Only runs when iCloud has one of them: two local labels
    /// of one name are left for the person.
    private static func mergeSameNamedLabels<Label: AccountItem & Named>(
        in account: inout Account,
        list: WritableKeyPath<Account, [Label]>,
        type: SyncRecordType,
        reference: WritableKeyPath<Expense, UUID?>,
        state st: SyncState,
        now: Date
    ) {
        let labels = account[keyPath: list]
        let groups = Dictionary(grouping: labels, by: { labelKey($0.name) }).values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return }
        var replaced: [UUID: UUID] = [:]
        for group in groups {
            let inCloud = group.filter { isKnown(type, $0.id, st) }
            guard let winner = inCloud.min(by: { $0.id.uuidString < $1.id.uuidString }) else { continue }
            for label in group where label.id != winner.id {
                replaced[label.id] = winner.id
            }
        }
        guard !replaced.isEmpty else { return }
        account[keyPath: list].removeAll { replaced[$0.id] != nil }
        for index in account.expenses.indices {
            guard let id = account.expenses[index][keyPath: reference], let winner = replaced[id] else { continue }
            account.expenses[index][keyPath: reference] = winner
            account.expenses[index].updatedAt = max(account.expenses[index].updatedAt, now)
        }
    }

    private static func isKnown(_ type: SyncRecordType, _ id: UUID, _ st: SyncState) -> Bool {
        st.known[SyncRecordName.make(type, id)] != nil
    }
}

/// A label's name, for recognising the same label made on two devices.
protocol Named {
    var name: String { get }
}

extension ExpenseCategory: Named {}
extension PaymentMethod: Named {}
