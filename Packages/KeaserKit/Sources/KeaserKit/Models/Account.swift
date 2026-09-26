import Foundation

/// A separate ledger ("Personal", "Business"). Each account owns its own
/// categories, payment methods and expenses, and may be linked to a Notion
/// database.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var categories: [ExpenseCategory]
    public var paymentMethods: [PaymentMethod]
    public var expenses: [Expense]
    /// Non-nil when this account mirrors a Notion database.
    public var notion: NotionConnection?
    /// Notion pages whose expenses were deleted locally and still need to be
    /// archived in Notion. The sync engine drains this list.
    public var deletedNotionPageIDs: [String]
    /// Expenses deleted in a Notion-linked account before they were linked
    /// to a page. A page for one may still exist (its create reached Notion
    /// but the response was lost); every sync trashes any page carrying one
    /// of these Keaser IDs instead of pulling it back in, until a sync began
    /// long enough after the deletion to be sure it saw that page.
    public var unlinkedDeletions: [UnlinkedDeletion]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        categories: [ExpenseCategory] = ExpenseCategory.defaults(),
        paymentMethods: [PaymentMethod] = PaymentMethod.defaults(),
        expenses: [Expense] = [],
        notion: NotionConnection? = nil,
        deletedNotionPageIDs: [String] = [],
        unlinkedDeletions: [UnlinkedDeletion] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.expenses = expenses
        self.notion = notion
        self.deletedNotionPageIDs = deletedNotionPageIDs
        self.unlinkedDeletions = unlinkedDeletions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Account"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        categories = try c.decodeIfPresent([ExpenseCategory].self, forKey: .categories) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        notion = try c.decodeIfPresent(NotionConnection.self, forKey: .notion)
        deletedNotionPageIDs = try c.decodeIfPresent([String].self, forKey: .deletedNotionPageIDs) ?? []
        if let deletions = try c.decodeIfPresent([UnlinkedDeletion].self, forKey: .unlinkedDeletions) {
            unlinkedDeletions = deletions
        } else {
            // Before the deletion time was kept, only the IDs were. Count
            // them as deleted now, so they wait a full window like new ones.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let ids = try legacy.decodeIfPresent([UUID].self, forKey: .deletedUnlinkedExpenseIDs) ?? []
            let now = Date.now
            unlinkedDeletions = ids.map { UnlinkedDeletion(expenseID: $0, deletedAt: now) }
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case deletedUnlinkedExpenseIDs
    }

    /// First letter of the name, for the monogram tile in Settings.
    public var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    public var isNotionLinked: Bool { notion != nil }

    public func category(id: UUID?) -> ExpenseCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    public func paymentMethod(id: UUID?) -> PaymentMethod? {
        guard let id else { return nil }
        return paymentMethods.first { $0.id == id }
    }

    /// SF Symbol for an expense row: its category's symbol, or a card.
    public func symbol(for expense: Expense) -> String {
        category(id: expense.categoryID)?.symbol ?? ExpenseCategory.fallbackSymbol
    }

    /// Expenses newest first (by day, then by creation time).
    public var expensesNewestFirst: [Expense] {
        expenses.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    /// Sum of expenses dated in `interval` (half-open); all expenses when nil.
    public func total(in interval: DateInterval?) -> Decimal {
        expenses.reduce(into: Decimal(0)) { sum, expense in
            if interval.map({ $0.holds(expense.date) }) ?? true { sum += expense.amount }
        }
    }
}

/// An expense deleted in a Notion-linked account before it was linked to a
/// page, and when. See `Account.unlinkedDeletions`.
public struct UnlinkedDeletion: Codable, Hashable, Sendable {
    public var expenseID: UUID
    public var deletedAt: Date

    public init(expenseID: UUID, deletedAt: Date) {
        self.expenseID = expenseID
        self.deletedAt = deletedAt
    }

    // Tolerant decoding: a missing time counts as deleted now, which only
    // keeps the entry longer.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expenseID = try c.decode(UUID.self, forKey: .expenseID)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt) ?? .now
    }
}
