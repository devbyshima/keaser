import Foundation

/// The remote half of sync: writing what iCloud sent into the database.
///
/// Rules, per record:
/// - Unchanged here since iCloud last had it: iCloud's version is taken.
/// - Changed on both sides: the later edit wins (`SyncRecord.wins(over:)`;
///   equal times are decided by the payloads, the same way on every
///   device). The settings, the list orders and the split rules are the
///   exception on a device that has never synced them: iCloud's copy wins
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
/// deleted too. An expense, income or transfer keeps working when its
/// category, income category or wallet is deleted elsewhere: an ID that
/// matches no label reads as none. Two labels of the same name in one
/// account (made independently on two devices) become one, and on a
/// device's first sync an account it made that has the name of an account
/// already in iCloud merges into it, so a second device adds to the
/// person's data instead of duplicating it. Either way everything that
/// pointed at a label that went (expenses, income, transfers, balance
/// adjustments, the split rule's savings wallet) points at the one that
/// stays (`LabelRedirects`).
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
        let display = db.preferences.currencyCode
        for index in db.accounts.indices {
            mergeSameNamedLabels(in: &db.accounts[index], list: \.categories, type: .category, state: st, now: now) { $0.merge($1, into: $2) }
            mergeSameNamedLabels(in: &db.accounts[index], list: \.paymentMethods, type: .paymentMethod, state: st, now: now) {
                $0.merge($1, into: $2, display: display)
            }
            mergeSameNamedLabels(in: &db.accounts[index], list: \.incomeCategories, type: .incomeCategory, state: st, now: now) { $0.merge($1, into: $2) }
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
    /// categories, payment methods and income categories join the
    /// account's (a label of the same name becomes the existing one), and
    /// its expenses, income, transfers and balance adjustments move over.
    /// The split rule is the account's own: this device's goes.
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
        let display = db.preferences.currencyCode
        var redirects = LabelRedirects()

        func join<Label: AccountItem & Named>(
            _ list: WritableKeyPath<Account, [Label]>,
            orderedAt: WritableKeyPath<Account, Date>,
            redirect: (inout LabelRedirects, _ label: Label, _ same: Label) -> Void
        ) {
            for label in source[keyPath: list] {
                if let same = target[keyPath: list].first(where: { labelKey($0.name) == labelKey(label.name) }) {
                    redirect(&redirects, label, same)
                } else {
                    target[keyPath: list].append(label)
                    target[keyPath: orderedAt] = now
                }
            }
        }
        func move<Item: AccountItem>(_ list: WritableKeyPath<Account, [Item]>, _ type: SyncRecordType, redirect: (inout Item) -> Bool) {
            for var item in source[keyPath: list] {
                _ = redirect(&item)
                // One already in iCloud under the old account must win there.
                if isKnown(type, item.id, st) { item.updatedAt = max(item.updatedAt, now) }
                target[keyPath: list].append(item)
            }
        }

        join(\.categories, orderedAt: \.categoriesOrderedAt) { $0.merge($1, into: $2) }
        join(\.paymentMethods, orderedAt: \.paymentMethodsOrderedAt) { $0.merge($1, into: $2, display: display) }
        join(\.incomeCategories, orderedAt: \.incomeCategoriesOrderedAt) { $0.merge($1, into: $2) }
        move(\.expenses, .expense) { redirects.redirect(&$0) }
        move(\.incomes, .income) { redirects.redirect(&$0) }
        move(\.transfers, .transfer) { redirects.redirect(&$0) }
        move(\.balanceAdjustments, .balanceAdjustment) { redirects.redirect(&$0) }
        db.accounts[t] = target
        db.accounts.remove(at: s)
    }

    /// On a first sync that brought accounts from iCloud: an account this
    /// device made within the hour, with nothing in it but the built-in
    /// labels (no expenses, income, transfers or balances), is the
    /// placeholder of a new device's setup and goes.
    private static func dropPlaceholderAccounts(_ db: inout Database, state st: SyncState, now: Date, redirects: inout [UUID: UUID]) {
        guard let first = db.accounts.first(where: { isKnown(.account, $0.id, st) }) else { return }
        let defaultCategories = Set(ExpenseCategory.defaults().map { labelKey($0.name) })
        let defaultMethods = Set(PaymentMethod.defaults().map { labelKey($0.name) })
        let defaultIncomeCategories = Set(IncomeCategory.defaults(for: first.id).map { labelKey($0.name) })
        db.accounts.removeAll { account in
            let isPlaceholder = !isKnown(.account, account.id, st)
                && account.expenses.isEmpty
                && account.incomes.isEmpty
                && account.transfers.isEmpty
                && account.balanceAdjustments.isEmpty
                && now.timeIntervalSince(account.createdAt) < placeholderAccountAge
                && account.categories.allSatisfy { defaultCategories.contains(labelKey($0.name)) }
                && account.paymentMethods.allSatisfy { defaultMethods.contains(labelKey($0.name)) && !$0.isTracking }
                && account.incomeCategories.allSatisfy { defaultIncomeCategories.contains(labelKey($0.name)) }
            if isPlaceholder { redirects[account.id] = first.id }
            return isPlaceholder
        }
    }

    /// Labels of one name in one account are one label (the editors never
    /// allow two). The one iCloud has wins, or of two it has, the smaller
    /// ID, so every device picks the same; whatever pointed at the others
    /// points at it (`redirect` says which references a label of this list
    /// has). Only runs when iCloud has one of them: two local labels of one
    /// name are left for the person.
    private static func mergeSameNamedLabels<Label: AccountItem & Named>(
        in account: inout Account,
        list: WritableKeyPath<Account, [Label]>,
        type: SyncRecordType,
        state st: SyncState,
        now: Date,
        redirect: (inout LabelRedirects, _ label: Label, _ winner: Label) -> Void
    ) {
        let labels = account[keyPath: list]
        let groups = Dictionary(grouping: labels, by: { labelKey($0.name) }).values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return }
        var redirects = LabelRedirects()
        var replaced = Set<UUID>()
        for group in groups {
            let inCloud = group.filter { isKnown(type, $0.id, st) }
            guard let winner = inCloud.min(by: { $0.id.uuidString < $1.id.uuidString }) else { continue }
            for label in group where label.id != winner.id {
                redirect(&redirects, label, winner)
                replaced.insert(label.id)
            }
        }
        guard !replaced.isEmpty else { return }
        account[keyPath: list].removeAll { replaced.contains($0.id) }
        redirects.apply(to: &account, now: now)
    }

    private static func isKnown(_ type: SyncRecordType, _ id: UUID, _ st: SyncState) -> Bool {
        st.known[SyncRecordName.make(type, id)] != nil
    }
}

/// Where the references to labels that merged into others now point: each
/// label's ID to the ID of the one that stays, by kind of label.
struct LabelRedirects {
    var categories: [UUID: UUID] = [:]
    var wallets: [UUID: UUID] = [:]
    var incomeCategories: [UUID: UUID] = [:]
    /// The currency of a wallet that merged into one in another currency.
    /// What followed it (no currency of its own) is given it, so an amount
    /// or a stated balance keeps the currency it was typed in.
    var walletCurrencies: [UUID: String] = [:]

    mutating func merge(_ category: ExpenseCategory, into other: ExpenseCategory) {
        categories[category.id] = other.id
    }

    mutating func merge(_ category: IncomeCategory, into other: IncomeCategory) {
        incomeCategories[category.id] = other.id
    }

    /// `display`: the display currency, which a wallet without a currency
    /// of its own is in.
    mutating func merge(_ wallet: PaymentMethod, into other: PaymentMethod, display: String) {
        wallets[wallet.id] = other.id
        let currency = wallet.effectiveCurrency(display: display)
        if currency != other.effectiveCurrency(display: display) {
            walletCurrencies[wallet.id] = currency
        }
    }

    // Each points one item at the labels that stay; true when that changed
    // it.

    func redirect(_ expense: inout Expense) -> Bool {
        let before = expense
        expense.categoryID = redirected(expense.categoryID, by: categories)
        redirectWallet(&expense, \.paymentMethodID, currency: \.currencyCode)
        return expense != before
    }

    func redirect(_ income: inout Income) -> Bool {
        let before = income
        income.categoryID = redirected(income.categoryID, by: incomeCategories)
        redirectWallet(&income, \.walletID, currency: \.currencyCode)
        return income != before
    }

    func redirect(_ transfer: inout Transfer) -> Bool {
        let before = transfer
        redirectWallet(&transfer, \.fromWalletID, currency: \.currencyOut)
        redirectWallet(&transfer, \.toWalletID, currency: \.currencyIn)
        return transfer != before
    }

    func redirect(_ adjustment: inout BalanceAdjustment) -> Bool {
        let before = adjustment
        redirectWallet(&adjustment, \.walletID, currency: \.currencyCode)
        return adjustment != before
    }

    func redirect(_ rule: inout SplitRule) -> Bool {
        let before = rule
        rule.savingsWalletID = redirected(rule.savingsWalletID, by: wallets)
        return rule != before
    }

    /// Points everything in `account` at the labels that stay. What changed
    /// is stamped `now` (or keeps a later stamp), so it goes out and wins.
    func apply(to account: inout Account, now: Date) {
        Self.stamp(&account.expenses, now: now) { redirect(&$0) }
        Self.stamp(&account.incomes, now: now) { redirect(&$0) }
        Self.stamp(&account.transfers, now: now) { redirect(&$0) }
        Self.stamp(&account.balanceAdjustments, now: now) { redirect(&$0) }
        if redirect(&account.splitRule) {
            account.splitRule.updatedAt = max(account.splitRule.updatedAt, now)
        }
    }

    private static func stamp<Item: AccountItem>(_ items: inout [Item], now: Date, redirect: (inout Item) -> Bool) {
        for index in items.indices {
            guard redirect(&items[index]) else { continue }
            items[index].updatedAt = max(items[index].updatedAt, now)
        }
    }

    private func redirected(_ id: UUID?, by map: [UUID: UUID]) -> UUID? {
        guard let id else { return nil }
        return map[id] ?? id
    }

    private func redirectWallet<Item>(_ item: inout Item, _ wallet: WritableKeyPath<Item, UUID?>, currency: WritableKeyPath<Item, String?>) {
        guard let id = item[keyPath: wallet], let other = wallets[id] else { return }
        if item[keyPath: currency] == nil {
            item[keyPath: currency] = walletCurrencies[id]
        }
        item[keyPath: wallet] = other
    }
}

/// A label's name, for recognising the same label made on two devices.
protocol Named {
    var name: String { get }
}

extension ExpenseCategory: Named {}
extension PaymentMethod: Named {}
extension IncomeCategory: Named {}
