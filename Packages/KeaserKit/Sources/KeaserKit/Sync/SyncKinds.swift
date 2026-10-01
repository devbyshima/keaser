import Foundation

/// What happened when a record from iCloud was written into the database.
public enum SyncApplyOutcome: Equatable, Sendable {
    case applied
    /// The account the record belongs to is not on this device (yet).
    case needsAccount(UUID)
    /// The body does not read as this kind.
    case unreadable
}

/// One kind of record: which part of the database it stands for, and how
/// it is written as a record and applied back.
///
/// The diff (`SyncPlan`), the merge (`SyncMerge`) and the CloudKit mapping
/// in the app all work from `SyncKinds.all`, so a new kind of data syncs by
/// adding one conforming type there and a `SyncStamps` rule for its edit
/// time; nothing else changes. Builds that predate a kind keep its records
/// aside, untouched, until they are updated.
public protocol SyncKind: Sendable {
    static var type: SyncRecordType { get }
    /// Records apply in rank order, so an account exists before anything
    /// that belongs to it.
    static var rank: Int { get }
    /// True for records every device has from the start under the same
    /// name (the settings, the orders): when a device that has never synced
    /// meets iCloud's copy, iCloud's wins whatever the edit times, so a new
    /// device takes on the person's settings instead of imposing its
    /// defaults.
    static var remoteWinsFirstMeeting: Bool { get }
    /// Every record of this kind that `database` holds.
    static func records(in database: Database) -> [SyncRecord]
    /// The record named `name`, when `database` holds it.
    static func record(named name: String, in database: Database) -> SyncRecord?
    /// The records of these names `database` holds, found in one pass.
    static func records(named names: Set<String>, in database: Database) -> [SyncRecord]
    /// `record` as this build writes it: its body read into the model and
    /// written back. Nil when the body does not read.
    static func canonical(_ record: SyncRecord) -> SyncRecord?
    /// Writes `record` into `database`, inserting or replacing.
    static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome
    /// Takes the record named `name` out of `database` (deleted on another
    /// device).
    static func remove(named name: String, from database: inout Database)
    /// Called when this device's version wins over `record`: keeps what
    /// must survive from the losing side.
    static func absorb(_ record: SyncRecord, into database: inout Database)
    /// Whether the local version has changed since iCloud last had it.
    static func isPending(_ local: SyncRecord, known: KnownRecord) -> Bool
    /// The files a record of this kind named `name` carries (CKAssets):
    /// uploaded with it, stored on arrival, removed when it is deleted.
    static func assets(named name: String) -> [SyncAsset]
}

extension SyncKind {
    public static func records(named names: Set<String>, in database: Database) -> [SyncRecord] {
        names.compactMap { record(named: $0, in: database) }
    }

    public static var remoteWinsFirstMeeting: Bool { false }
    public static func absorb(_ record: SyncRecord, into database: inout Database) {}
    public static func isPending(_ local: SyncRecord, known: KnownRecord) -> Bool {
        local.fingerprint != known.fingerprint
    }
    public static func assets(named name: String) -> [SyncAsset] { [] }
}

public enum SyncKinds {
    /// Every kind this build syncs, in rank order.
    public static let all: [any SyncKind.Type] = [
        SettingsSyncKind.self,
        AccountSyncKind.self,
        CategorySyncKind.self,
        PaymentMethodSyncKind.self,
        IncomeCategorySyncKind.self,
        SplitRuleSyncKind.self,
        ExpenseSyncKind.self,
        IncomeSyncKind.self,
        TransferSyncKind.self,
        BalanceAdjustmentSyncKind.self,
        OrderSyncKind.self,
        ReceiptSyncKind.self,
    ]

    public static func kind(for type: SyncRecordType) -> (any SyncKind.Type)? {
        all.first { $0.type == type }
    }

    /// The kind a record name stands for: names start with the type.
    public static func kind(forName name: String) -> (any SyncKind.Type)? {
        let prefix = name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
        return kind(for: SyncRecordType(prefix))
    }

    /// Every record `database` is made of.
    public static func records(in database: Database) -> [SyncRecord] {
        all.flatMap { $0.records(in: database) }
    }
}

// MARK: - Settings

public enum SettingsSyncKind: SyncKind {
    public static let type = SyncRecordType.settings
    public static let rank = 0
    public static let remoteWinsFirstMeeting = true

    public static func records(in database: Database) -> [SyncRecord] {
        [record(SyncedSettings(database.preferences))]
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        name == SyncRecordName.settings ? record(SyncedSettings(database.preferences)) : nil
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        SyncCoding.value(SyncedSettings.self, from: record.body).map(Self.record)
    }

    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        guard let settings = SyncCoding.value(SyncedSettings.self, from: record.body) else { return .unreadable }
        settings.apply(to: &database.preferences)
        return .applied
    }

    public static func remove(named name: String, from database: inout Database) {
        // Nothing deletes the settings; a stray deletion leaves them be.
    }

    /// One pass per person: the earliest start wins even when the rest of
    /// the other device's settings lose.
    public static func absorb(_ record: SyncRecord, into database: inout Database) {
        guard let settings = SyncCoding.value(SyncedSettings.self, from: record.body) else { return }
        database.preferences.trialStartDate = SyncedSettings.earlier(database.preferences.trialStartDate, settings.trialStartDate)
    }

    static func record(_ settings: SyncedSettings) -> SyncRecord {
        SyncRecord(name: SyncRecordName.settings, type: type, modifiedAt: settings.updatedAt, body: SyncCoding.body(settings))
    }
}

// MARK: - Accounts

public enum AccountSyncKind: SyncKind {
    public static let type = SyncRecordType.account
    public static let rank = 1

    /// An account record holds only the account's own details; what it
    /// holds syncs as records of their own.
    struct Fields: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date

        init(_ account: Account) {
            id = account.id
            name = account.name
            createdAt = account.createdAt
            updatedAt = account.updatedAt
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Account"
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        }
    }

    public static func records(in database: Database) -> [SyncRecord] {
        database.accounts.map { record(Fields($0)) }
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        guard let id = SyncRecordName.id(in: name), let account = database.accounts.first(where: { $0.id == id }) else { return nil }
        return record(Fields(account))
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        SyncCoding.value(Fields.self, from: record.body).map(Self.record)
    }

    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        guard let fields = SyncCoding.value(Fields.self, from: record.body) else { return .unreadable }
        if let index = database.accounts.firstIndex(where: { $0.id == fields.id }) {
            database.accounts[index].name = fields.name
            database.accounts[index].createdAt = fields.createdAt
            database.accounts[index].updatedAt = fields.updatedAt
        } else {
            // Empty: its labels, expenses, income, transfers and balance
            // adjustments arrive as records of their own, and so do their
            // orders and its split rule, which wins over this default.
            var account = Account(
                id: fields.id, name: fields.name, createdAt: fields.createdAt,
                categories: [], paymentMethods: [], expenses: [], updatedAt: fields.updatedAt,
                incomeCategories: [], splitRule: SplitRule()
            )
            account.categoriesOrderedAt = .distantPast
            account.paymentMethodsOrderedAt = .distantPast
            account.incomeCategoriesOrderedAt = .distantPast
            database.accounts.append(account)
        }
        return .applied
    }

    /// Deleted on another device: the account goes with everything in it.
    public static func remove(named name: String, from database: inout Database) {
        guard let id = SyncRecordName.id(in: name) else { return }
        database.accounts.removeAll { $0.id == id }
    }

    static func record(_ fields: Fields) -> SyncRecord {
        SyncRecord(
            name: SyncRecordName.make(type, fields.id), type: type,
            modifiedAt: fields.updatedAt, body: SyncCoding.body(fields)
        )
    }
}

// MARK: - What an account holds

/// A category, payment method, expense, income category, income, transfer
/// or balance adjustment: a value with an ID and an edit time, kept in one
/// of an account's lists. The record's `parent` is the account.
public protocol AccountItem: Identifiable, Codable, Equatable, Sendable where ID == UUID {
    var updatedAt: Date { get set }
}

extension ExpenseCategory: AccountItem {}
extension PaymentMethod: AccountItem {}
extension Expense: AccountItem {}
extension IncomeCategory: AccountItem {}
extension Income: AccountItem {}
extension Transfer: AccountItem {}
extension BalanceAdjustment: AccountItem {}

public protocol AccountItemSyncKind: SyncKind {
    associatedtype Item: AccountItem
    /// The account's list of these.
    static var list: WritableKeyPath<Account, [Item]> { get }
}

extension AccountItemSyncKind {
    public static func records(in database: Database) -> [SyncRecord] {
        database.accounts.flatMap { account in
            account[keyPath: list].map { record($0, in: account.id) }
        }
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        guard let id = SyncRecordName.id(in: name) else { return nil }
        for account in database.accounts {
            if let item = account[keyPath: list].first(where: { $0.id == id }) { return record(item, in: account.id) }
        }
        return nil
    }

    public static func records(named names: Set<String>, in database: Database) -> [SyncRecord] {
        let ids = Set(names.compactMap(SyncRecordName.id(in:)))
        guard !ids.isEmpty else { return [] }
        return database.accounts.flatMap { account in
            account[keyPath: list].filter { ids.contains($0.id) }.map { record($0, in: account.id) }
        }
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        guard let item = SyncCoding.value(Item.self, from: record.body), let parent = record.parent else { return nil }
        return self.record(item, in: parent)
    }

    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        guard let item = SyncCoding.value(Item.self, from: record.body), let parent = record.parent else { return .unreadable }
        guard let target = database.accounts.firstIndex(where: { $0.id == parent }) else { return .needsAccount(parent) }
        // Moved to another account elsewhere: out of the old one first.
        for a in database.accounts.indices where a != target {
            database.accounts[a][keyPath: list].removeAll { $0.id == item.id }
        }
        if let index = database.accounts[target][keyPath: list].firstIndex(where: { $0.id == item.id }) {
            database.accounts[target][keyPath: list][index] = item
        } else {
            database.accounts[target][keyPath: list].append(item)
        }
        return .applied
    }

    /// Deleted on another device. What pointed at a deleted category or
    /// payment method keeps working: an ID that no longer matches a label
    /// reads as none (`Account.category(id:)`), and the deleting device
    /// sends its own copies of those expenses with the label cleared.
    public static func remove(named name: String, from database: inout Database) {
        guard let id = SyncRecordName.id(in: name) else { return }
        for a in database.accounts.indices {
            database.accounts[a][keyPath: list].removeAll { $0.id == id }
        }
    }

    public static func record(_ item: Item, in accountID: UUID) -> SyncRecord {
        SyncRecord(
            name: SyncRecordName.make(type, item.id), type: type,
            modifiedAt: item.updatedAt, parent: accountID, body: SyncCoding.body(item)
        )
    }
}

public enum CategorySyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.category
    public static let rank = 2
    public static var list: WritableKeyPath<Account, [ExpenseCategory]> { \.categories }
}

/// Payment methods, which are also the wallets: the wallet fields (kind,
/// currency, balance, credit limit) travel in the same record.
public enum PaymentMethodSyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.paymentMethod
    public static let rank = 2
    public static var list: WritableKeyPath<Account, [PaymentMethod]> { \.paymentMethods }
}

/// Income categories. The built-in ones have IDs derived from their
/// account's (`IncomeCategory.defaults(for:)`), so two devices that give
/// the same account its defaults make the same records.
public enum IncomeCategorySyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.incomeCategory
    public static let rank = 2
    public static var list: WritableKeyPath<Account, [IncomeCategory]> { \.incomeCategories }
}

/// Expenses. The body is the whole `Expense`, so whatever it holds syncs
/// with it, including the ordered list of its receipt photos' IDs; the
/// photos themselves travel as `ReceiptSyncKind` records.
public enum ExpenseSyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.expense
    public static let rank = 3
    public static var list: WritableKeyPath<Account, [Expense]> { \.expenses }
}

/// Income. Its savings transfer is a `TransferSyncKind` record of its own,
/// linked both ways by ID (`savingsTransferID`, `Transfer.incomeID`).
public enum IncomeSyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.income
    public static let rank = 3
    public static var list: WritableKeyPath<Account, [Income]> { \.incomes }
}

public enum TransferSyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.transfer
    public static let rank = 3
    public static var list: WritableKeyPath<Account, [Transfer]> { \.transfers }
}

public enum BalanceAdjustmentSyncKind: AccountItemSyncKind {
    public static let type = SyncRecordType.balanceAdjustment
    public static let rank = 3
    public static var list: WritableKeyPath<Account, [BalanceAdjustment]> { \.balanceAdjustments }
}

// MARK: - Split rule

/// One record per account, `SplitRule.<account ID>`, whose body is the
/// account's `SplitRule` and whose edit time is the rule's `updatedAt`.
///
/// Every account has a rule from the start, so like the settings, iCloud's
/// copy wins when a device that has never synced it meets it: a new device
/// takes on the person's rule instead of imposing the default. Nothing
/// deletes a rule on its own; it goes with its account.
public enum SplitRuleSyncKind: SyncKind {
    public static let type = SyncRecordType.splitRule
    public static let rank = 2
    public static let remoteWinsFirstMeeting = true

    public static func records(in database: Database) -> [SyncRecord] {
        database.accounts.map { record($0.splitRule, in: $0.id) }
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        guard let id = accountID(in: name), let account = database.accounts.first(where: { $0.id == id }) else { return nil }
        return record(account.splitRule, in: account.id)
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        guard let id = accountID(in: record.name), let rule = SyncCoding.value(SplitRule.self, from: record.body) else { return nil }
        return self.record(rule, in: id)
    }

    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        guard let id = accountID(in: record.name), let rule = SyncCoding.value(SplitRule.self, from: record.body) else { return .unreadable }
        guard let a = database.accounts.firstIndex(where: { $0.id == id }) else { return .needsAccount(id) }
        database.accounts[a].splitRule = rule
        return .applied
    }

    public static func remove(named name: String, from database: inout Database) {
        // A rule goes when its account goes; on its own it stays.
    }

    static func record(_ rule: SplitRule, in accountID: UUID) -> SyncRecord {
        SyncRecord(
            name: SyncRecordName.make(type, accountID), type: type,
            modifiedAt: rule.updatedAt, parent: accountID, body: SyncCoding.body(rule)
        )
    }

    /// The account a rule's record name stands for.
    private static func accountID(in name: String) -> UUID? {
        guard name.hasPrefix(type.rawValue + ".") else { return nil }
        return SyncRecordName.id(in: name)
    }
}

// MARK: - Orders

/// The order of the accounts, and of each account's categories, payment
/// methods and income categories: the IDs in order, stamped with the
/// container's `...OrderedAt`.
///
/// An order is sent only when this device rearranged the list (its stamp
/// is newer than iCloud's), never merely because items arrived from another
/// device before their order did. Items a list does not name keep their
/// place after the ones it does.
public enum OrderSyncKind: SyncKind {
    public static let type = SyncRecordType.order
    public static let rank = 4
    public static let remoteWinsFirstMeeting = true

    struct Body: Codable {
        var ids: [UUID]

        init(ids: [UUID]) {
            self.ids = ids
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ids = try c.decodeIfPresent([UUID].self, forKey: .ids) ?? []
        }
    }

    enum List: Equatable {
        case accounts
        case categories(UUID)
        case paymentMethods(UUID)
        case incomeCategories(UUID)

        init?(name: String) {
            if name == SyncRecordName.accountsOrder {
                self = .accounts
            } else if name.hasPrefix("Order.Categories."), let id = SyncRecordName.id(in: name) {
                self = .categories(id)
            } else if name.hasPrefix("Order.PaymentMethods."), let id = SyncRecordName.id(in: name) {
                self = .paymentMethods(id)
            } else if name.hasPrefix("Order.IncomeCategories."), let id = SyncRecordName.id(in: name) {
                self = .incomeCategories(id)
            } else {
                return nil
            }
        }

        var name: String {
            switch self {
            case .accounts: SyncRecordName.accountsOrder
            case .categories(let id): SyncRecordName.categoriesOrder(id)
            case .paymentMethods(let id): SyncRecordName.paymentMethodsOrder(id)
            case .incomeCategories(let id): SyncRecordName.incomeCategoriesOrder(id)
            }
        }

        var accountID: UUID? {
            switch self {
            case .accounts: nil
            case .categories(let id), .paymentMethods(let id), .incomeCategories(let id): id
            }
        }

        /// The ordered lists each account has.
        static func lists(of accountID: UUID) -> [List] {
            [.categories(accountID), .paymentMethods(accountID), .incomeCategories(accountID)]
        }
    }

    public static func records(in database: Database) -> [SyncRecord] {
        var records = [record(.accounts, in: database)].compactMap { $0 }
        for account in database.accounts {
            records += List.lists(of: account.id).compactMap { record($0, in: database) }
        }
        return records
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        List(name: name).flatMap { record($0, in: database) }
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        guard let list = List(name: record.name), let body = SyncCoding.value(Body.self, from: record.body) else { return nil }
        return make(list, ids: body.ids, modifiedAt: record.modifiedAt)
    }

    /// Takes on the other device's stamp and arranges the list by it.
    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        guard let list = List(name: record.name), let body = SyncCoding.value(Body.self, from: record.body) else { return .unreadable }
        switch list {
        case .accounts:
            database.accountsOrderedAt = record.modifiedAt
            database.accounts = arranged(database.accounts, by: body.ids)
        case .categories(let id):
            guard let a = database.accounts.firstIndex(where: { $0.id == id }) else { return .needsAccount(id) }
            database.accounts[a].categoriesOrderedAt = record.modifiedAt
            database.accounts[a].categories = arranged(database.accounts[a].categories, by: body.ids)
        case .paymentMethods(let id):
            guard let a = database.accounts.firstIndex(where: { $0.id == id }) else { return .needsAccount(id) }
            database.accounts[a].paymentMethodsOrderedAt = record.modifiedAt
            database.accounts[a].paymentMethods = arranged(database.accounts[a].paymentMethods, by: body.ids)
        case .incomeCategories(let id):
            guard let a = database.accounts.firstIndex(where: { $0.id == id }) else { return .needsAccount(id) }
            database.accounts[a].incomeCategoriesOrderedAt = record.modifiedAt
            database.accounts[a].incomeCategories = arranged(database.accounts[a].incomeCategories, by: body.ids)
        }
        return .applied
    }

    public static func remove(named name: String, from database: inout Database) {
        // An order goes when its account goes; the list itself stays.
    }

    /// Pending only when this device rearranged the list after iCloud's
    /// arrangement.
    public static func isPending(_ local: SyncRecord, known: KnownRecord) -> Bool {
        local.modifiedAt > known.modifiedAt
    }

    /// Puts every list this device has not rearranged since in iCloud's
    /// order again, so an item that arrived after its list's order still
    /// lands where the order says.
    static func arrangeByKnownOrders(_ database: inout Database, known: [String: KnownRecord]) {
        func order(_ list: List) -> KnownRecord? {
            guard let entry = known[list.name], entry.orderIDs != nil else { return nil }
            return entry
        }
        if let entry = order(.accounts), database.accountsOrderedAt <= entry.modifiedAt {
            database.accounts = arranged(database.accounts, by: entry.orderIDs ?? [])
        }
        for a in database.accounts.indices {
            let id = database.accounts[a].id
            if let entry = order(.categories(id)), database.accounts[a].categoriesOrderedAt <= entry.modifiedAt {
                database.accounts[a].categories = arranged(database.accounts[a].categories, by: entry.orderIDs ?? [])
            }
            if let entry = order(.paymentMethods(id)), database.accounts[a].paymentMethodsOrderedAt <= entry.modifiedAt {
                database.accounts[a].paymentMethods = arranged(database.accounts[a].paymentMethods, by: entry.orderIDs ?? [])
            }
            if let entry = order(.incomeCategories(id)), database.accounts[a].incomeCategoriesOrderedAt <= entry.modifiedAt {
                database.accounts[a].incomeCategories = arranged(database.accounts[a].incomeCategories, by: entry.orderIDs ?? [])
            }
        }
    }

    /// The IDs an order record lists.
    static func ids(in record: SyncRecord) -> [UUID]? {
        SyncCoding.value(Body.self, from: record.body)?.ids
    }

    /// The listed items in the listed order, then the rest as they were.
    static func arranged<T: Identifiable>(_ items: [T], by ids: [UUID]) -> [T] where T.ID == UUID {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = items.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        return listed + items.filter { rank[$0.id] == nil }
    }

    static func record(_ list: List, in database: Database) -> SyncRecord? {
        switch list {
        case .accounts:
            return make(list, ids: database.accounts.map(\.id), modifiedAt: database.accountsOrderedAt)
        case .categories(let id):
            guard let account = database.accounts.first(where: { $0.id == id }) else { return nil }
            return make(list, ids: account.categories.map(\.id), modifiedAt: account.categoriesOrderedAt)
        case .paymentMethods(let id):
            guard let account = database.accounts.first(where: { $0.id == id }) else { return nil }
            return make(list, ids: account.paymentMethods.map(\.id), modifiedAt: account.paymentMethodsOrderedAt)
        case .incomeCategories(let id):
            guard let account = database.accounts.first(where: { $0.id == id }) else { return nil }
            return make(list, ids: account.incomeCategories.map(\.id), modifiedAt: account.incomeCategoriesOrderedAt)
        }
    }

    static func make(_ list: List, ids: [UUID], modifiedAt: Date) -> SyncRecord {
        SyncRecord(
            name: list.name, type: type, modifiedAt: modifiedAt,
            parent: list.accountID, body: SyncCoding.body(Body(ids: ids))
        )
    }
}

// MARK: - Receipt photos

/// An expense that keeps receipt photos, by ID, in the order it shows them.
/// `Expense` adopts it once it holds photos (`receipts: [ReceiptPhoto]`):
///
///     extension Expense: ReceiptHolding {
///         public var receiptPhotoIDs: [UUID] { receipts.map(\.id) }
///     }
///
/// Until then no expense has photos and `ReceiptSyncKind` has no records.
public protocol ReceiptHolding {
    var receiptPhotoIDs: [UUID] { get }
}

/// One record per receipt photo, named by the photo's UUID, carrying the
/// JPEG as the CKAsset field `file`. The expense's own record carries the
/// list of photo IDs, so which photos an expense has, and their order, sync
/// (and win or lose) with the expense; these records only carry the bytes.
///
/// A photo never changes (another photo is another ID), so a record is
/// uploaded once. A photo no expense refers to any more (removed from its
/// expense, or its expense or account deleted) is no longer a record here,
/// so its record is deleted from iCloud, and the device receiving that
/// deletion removes the file too (`SyncMergeResult.removedAssets`), unless
/// an expense there still shows it. A device that has an expense's list but
/// not yet the file never creates the photo's record (the app skips records
/// whose file is missing), so an empty copy can never replace the real one.
public enum ReceiptSyncKind: SyncKind {
    public static let type = SyncRecordType("Receipt")
    /// After expenses, so the expense lists the photo before its file lands.
    public static let rank = 5
    /// The CKAsset field holding the JPEG.
    public static let fileField = "file"

    struct Body: Codable {
        var id: UUID
        var expenseID: UUID?
    }

    /// "receipt-<UUID>.jpg": `ReceiptPhoto.fileName`, the file in the
    /// Receipts folder.
    public static func fileName(for photoID: UUID) -> String {
        ReceiptPhoto(id: photoID).fileName
    }

    public static func records(in database: Database) -> [SyncRecord] {
        var seen = Set<UUID>()
        var records: [SyncRecord] = []
        for account in database.accounts {
            for expense in account.expenses {
                for id in photoIDs(of: expense) where seen.insert(id).inserted {
                    records.append(record(id, expense: expense.id, in: account.id))
                }
            }
        }
        return records
    }

    public static func record(named name: String, in database: Database) -> SyncRecord? {
        guard let id = SyncRecordName.id(in: name) else { return nil }
        for account in database.accounts {
            if let expense = account.expenses.first(where: { photoIDs(of: $0).contains(id) }) {
                return record(id, expense: expense.id, in: account.id)
            }
        }
        return nil
    }

    public static func canonical(_ record: SyncRecord) -> SyncRecord? {
        guard let body = SyncCoding.value(Body.self, from: record.body) else { return nil }
        return self.record(body.id, expense: body.expenseID, in: record.parent)
    }

    /// Nothing to write: the expense holds the reference, and the app
    /// stores the file as the record arrives.
    public static func apply(_ record: SyncRecord, to database: inout Database) -> SyncApplyOutcome {
        SyncCoding.value(Body.self, from: record.body) == nil ? .unreadable : .applied
    }

    public static func remove(named name: String, from database: inout Database) {}

    public static func assets(named name: String) -> [SyncAsset] {
        guard name.hasPrefix(type.rawValue + "."), let id = SyncRecordName.id(in: name) else { return [] }
        return [SyncAsset(field: fileField, fileName: fileName(for: id))]
    }

    static func photoIDs(of expense: Expense) -> [UUID] {
        (expense as Any as? any ReceiptHolding)?.receiptPhotoIDs ?? []
    }

    /// Never edited, so its edit time is fixed: a deletion always outlives
    /// an old copy of the photo.
    static func record(_ id: UUID, expense: UUID?, in accountID: UUID?) -> SyncRecord {
        SyncRecord(
            name: SyncRecordName.make(type, id), type: type, modifiedAt: .distantPast,
            parent: accountID, body: SyncCoding.body(Body(id: id, expenseID: expense))
        )
    }
}
