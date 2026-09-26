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

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        categories: [ExpenseCategory] = ExpenseCategory.defaults(),
        paymentMethods: [PaymentMethod] = PaymentMethod.defaults(),
        expenses: [Expense] = [],
        notion: NotionConnection? = nil,
        deletedNotionPageIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.expenses = expenses
        self.notion = notion
        self.deletedNotionPageIDs = deletedNotionPageIDs
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

    /// Sum of expenses whose date falls in `interval`; all expenses when nil.
    public func total(in interval: DateInterval?) -> Decimal {
        expenses.reduce(into: Decimal(0)) { sum, expense in
            if interval.map({ $0.contains(expense.date) }) ?? true { sum += expense.amount }
        }
    }
}
