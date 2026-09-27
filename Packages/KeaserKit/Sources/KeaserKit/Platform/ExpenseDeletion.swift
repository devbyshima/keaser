import Foundation

/// "Delete Expense" from Siri or Shortcuts: the expenses still there to
/// delete, the question asked before deleting them and what is said after.
public struct ExpenseDeletion: Hashable, Sendable {
    /// One expense to delete, with the account it is filed in, so it can be
    /// put back there.
    public struct Item: Hashable, Sendable {
        public let expense: Expense
        public let accountID: UUID
        public let accountName: String

        public init(expense: Expense, accountID: UUID, accountName: String) {
            self.expense = expense
            self.accountID = accountID
            self.accountName = accountName
        }
    }

    /// In the order asked for, each once. IDs no longer in the database (an
    /// expense deleted since Siri or Shortcuts found it) are left out.
    public let items: [Item]

    public init(ids: [UUID], in database: Database) {
        var found: [UUID: Item] = [:]
        let wanted = Set(ids)
        for account in database.accounts {
            for expense in account.expenses where wanted.contains(expense.id) {
                found[expense.id] = Item(expense: expense, accountID: account.id, accountName: account.name)
            }
        }
        var seen = Set<UUID>()
        items = ids.compactMap { id in seen.insert(id).inserted ? found[id] : nil }
    }

    public var isEmpty: Bool { items.isEmpty }

    public var total: Decimal {
        items.reduce(into: Decimal(0)) { $0 += $1.expense.amount }
    }

    /// Asked before anything is deleted, naming what goes:
    /// "Delete “Coffee” ($4.50 on Sep 26, 2026) from Personal?", or
    /// "Delete 3 expenses ($54.50 in all) from Personal?"
    public func question(currencyCode: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let accounts = Set(items.map(\.accountID))
        let from = accounts.count == 1 ? items.first?.accountName ?? "" : "\(accounts.count) accounts"
        if items.count == 1, let item = items.first {
            let amount = MoneyFormat.string(item.expense.amount, currencyCode: currencyCode, locale: locale)
            let day = Self.dayText(item.expense.date, locale: locale, timeZone: timeZone)
            return "Delete \u{201C}\(item.expense.title)\u{201D} (\(amount) on \(day)) from \(from)?"
        }
        let amount = MoneyFormat.string(total, currencyCode: currencyCode, locale: locale)
        return "Delete \(items.count) expenses (\(amount) in all) from \(from)?"
    }

    /// Said once they are gone: "Deleted “Coffee” from Personal." or
    /// "Deleted 3 expenses."
    public var doneSentence: String {
        if items.count == 1, let item = items.first {
            return "Deleted \u{201C}\(item.expense.title)\u{201D} from \(item.accountName)."
        }
        return "Deleted \(items.count) expenses."
    }

    /// "Sep 26, 2026", as Spotlight and Siri list the expense.
    static func dayText(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

extension KeaserStore {
    /// Deletes the expenses of `deletion`. When the change cannot be written
    /// they are all put back in memory too, and false is returned: kept out
    /// of memory, a later save would delete them anyway, after the person
    /// was told it failed.
    @discardableResult
    public func delete(_ deletion: ExpenseDeletion) -> Bool {
        var removed: [ExpenseDeletion.Item] = []
        for item in deletion.items {
            deleteExpense(item.expense.id, in: item.accountID)
            removed.append(item)
            if lastSaveError != nil {
                putBack(removed)
                return false
            }
        }
        return true
    }

    /// Puts deleted expenses back into their accounts exactly as they were
    /// (undo). One that is back already, or whose account was deleted since,
    /// is skipped. When the change cannot be written they are taken out of
    /// memory again and false is returned.
    @discardableResult
    public func restore(_ items: [ExpenseDeletion.Item]) -> Bool {
        let restorable = items.filter { item in
            guard let account = account(id: item.accountID) else { return false }
            return !account.expenses.contains { $0.id == item.expense.id }
        }
        putBack(restorable)
        guard lastSaveError == nil else {
            for item in restorable { deleteExpense(item.expense.id, in: item.accountID) }
            return false
        }
        return true
    }

    private func putBack(_ items: [ExpenseDeletion.Item]) {
        // Stamped with its own last change, so it comes back unchanged.
        for item in items { saveExpense(item.expense, in: item.accountID, now: item.expense.updatedAt) }
    }
}
