import Foundation

/// A separate ledger ("Personal", "Business"). Each account owns its own
/// categories, payment methods (its wallets), expenses, income and
/// transfers.
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
    public var incomeCategories: [IncomeCategory]
    public var incomes: [Income]
    public var transfers: [Transfer]
    /// Set Balance on wallets already tracking (`PaymentMethod.trackingSince`).
    public var balanceAdjustments: [BalanceAdjustment]
    public var splitRule: SplitRule
    /// When the order of `incomeCategories` last changed.
    public var incomeCategoriesOrderedAt: Date

    /// A nil `incomeCategories` is the built-in ones
    /// (`IncomeCategory.defaults(for:)`).
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        categories: [ExpenseCategory] = ExpenseCategory.defaults(),
        paymentMethods: [PaymentMethod] = PaymentMethod.defaults(),
        expenses: [Expense] = [],
        updatedAt: Date? = nil,
        incomeCategories: [IncomeCategory]? = nil,
        incomes: [Income] = [],
        transfers: [Transfer] = [],
        balanceAdjustments: [BalanceAdjustment] = [],
        splitRule: SplitRule = SplitRule()
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
        self.incomeCategories = incomeCategories ?? IncomeCategory.defaults(for: id)
        self.incomes = incomes
        self.transfers = transfers
        self.balanceAdjustments = balanceAdjustments
        self.splitRule = splitRule
        self.incomeCategoriesOrderedAt = createdAt
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
        // An account from before income gets the built-in income
        // categories; a stored list, even an empty one, stays as it is.
        incomeCategories = try c.decodeIfPresent([IncomeCategory].self, forKey: .incomeCategories) ?? IncomeCategory.defaults(for: id)
        incomes = try c.decodeIfPresent([Income].self, forKey: .incomes) ?? []
        transfers = try c.decodeIfPresent([Transfer].self, forKey: .transfers) ?? []
        balanceAdjustments = try c.decodeIfPresent([BalanceAdjustment].self, forKey: .balanceAdjustments) ?? []
        splitRule = try c.decodeIfPresent(SplitRule.self, forKey: .splitRule) ?? SplitRule()
        incomeCategoriesOrderedAt = try c.decodeIfPresent(Date.self, forKey: .incomeCategoriesOrderedAt) ?? .distantPast
    }

    /// First letter of the name, for the monogram tile in Settings.
    public var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    public func category(id: UUID?) -> ExpenseCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// The payment method, which is also the wallet.
    public func paymentMethod(id: UUID?) -> PaymentMethod? {
        guard let id else { return nil }
        return paymentMethods.first { $0.id == id }
    }

    public func incomeCategory(id: UUID?) -> IncomeCategory? {
        guard let id else { return nil }
        return incomeCategories.first { $0.id == id }
    }

    public func income(id: UUID?) -> Income? {
        guard let id else { return nil }
        return incomes.first { $0.id == id }
    }

    public func transfer(id: UUID?) -> Transfer? {
        guard let id else { return nil }
        return transfers.first { $0.id == id }
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
