import Foundation

/// A separate ledger ("Personal", "Business"). Each account owns its own
/// categories, payment methods and expenses.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var categories: [ExpenseCategory]
    public var paymentMethods: [PaymentMethod]
    public var expenses: [Expense]
    /// When the name last changed. `KeaserStore` stamps it, and iCloud sync
    /// keeps the later of two renames. The creation time for accounts saved
    /// before it existed.
    public var updatedAt: Date
    /// When the order of `categories` last changed: one moved, added or
    /// deleted. iCloud sync keeps the later arrangement.
    public var categoriesOrderedAt: Date
    /// When the order of `paymentMethods` last changed.
    public var paymentMethodsOrderedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        categories: [ExpenseCategory] = ExpenseCategory.defaults(),
        paymentMethods: [PaymentMethod] = PaymentMethod.defaults(),
        expenses: [Expense] = [],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.expenses = expenses
        self.updatedAt = updatedAt ?? createdAt
        self.categoriesOrderedAt = createdAt
        self.paymentMethodsOrderedAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Account"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        categories = try c.decodeIfPresent([ExpenseCategory].self, forKey: .categories) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        categoriesOrderedAt = try c.decodeIfPresent(Date.self, forKey: .categoriesOrderedAt) ?? .distantPast
        paymentMethodsOrderedAt = try c.decodeIfPresent(Date.self, forKey: .paymentMethodsOrderedAt) ?? .distantPast
    }

    /// First letter of the name, for the monogram tile in Settings.
    public var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

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
