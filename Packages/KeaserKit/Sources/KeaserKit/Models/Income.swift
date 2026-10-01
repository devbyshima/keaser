import Foundation

/// Where income comes from ("Salary", "Gifts"). `symbol` is an SF Symbol
/// name. Each account has its own, as it has its own spending categories.
public struct IncomeCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// When the name or symbol last changed (see `ExpenseCategory.updatedAt`).
    /// `.distantPast` for the built-in ones.
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, symbol: String, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ExpenseCategory.fallbackSymbol
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

extension IncomeCategory {
    /// The built-in ones, in display order.
    private static let builtIn: [(name: String, symbol: String)] = [
        ("Salary", "briefcase.fill"),
        ("Business", "storefront.fill"),
        ("Gifts", "gift.fill"),
        ("Refunds", "arrow.uturn.backward.circle.fill"),
    ]

    /// What an account starts with, in display order, also given to every
    /// account saved before income existed. Each ID is derived from the
    /// account's ID and the name, so two devices giving the same account
    /// its defaults make the same categories, and iCloud sync does not
    /// duplicate them.
    public static func defaults(for accountID: UUID) -> [IncomeCategory] {
        builtIn.map { item in
            IncomeCategory(
                id: .derived(from: "\(accountID.uuidString).income-category.\(item.name)"),
                name: item.name, symbol: item.symbol, updatedAt: .distantPast
            )
        }
    }

    /// The icon a built-in income category starts with, for "Reset to
    /// Default". Nil for a category the user added.
    public static func defaultSymbol(forName name: String) -> String? {
        let key = labelKey(name)
        return builtIn.first { labelKey($0.name) == key }?.symbol
    }
}

/// Money received: a salary, a gift, a refund.
public struct Income: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// In `currencyCode`'s currency.
    public var amount: Decimal
    /// Nil: its wallet's currency, and with no wallet, the display currency.
    public var currencyCode: String?
    /// The rate to the display currency, saved when it was logged.
    public var rate: ExchangeRate?
    /// An `IncomeCategory` of the account.
    public var categoryID: UUID?
    /// The wallet (`PaymentMethod`) it went into; nil: none.
    public var walletID: UUID?
    /// The day it was received. Only the calendar day is meaningful.
    public var date: Date
    public var createdAt: Date
    public var updatedAt: Date
    /// The split rule's Savings percentage applied to it, kept so it keeps
    /// the split it was logged with; nil: none.
    public var savingsPercent: Int?
    /// The `.savings` transfer that split made.
    public var savingsTransferID: UUID?
    /// Skip This Time: no savings transfer for this income.
    public var savingsSkipped: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        currencyCode: String? = nil,
        rate: ExchangeRate? = nil,
        categoryID: UUID? = nil,
        walletID: UUID? = nil,
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        savingsPercent: Int? = nil,
        savingsTransferID: UUID? = nil,
        savingsSkipped: Bool = false
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.rate = rate
        self.categoryID = categoryID
        self.walletID = walletID
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.savingsPercent = savingsPercent
        self.savingsTransferID = savingsTransferID
        self.savingsSkipped = savingsSkipped
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        amount = try c.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode)
        rate = try? c.decodeIfPresent(ExchangeRate.self, forKey: .rate)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        walletID = try c.decodeIfPresent(UUID.self, forKey: .walletID)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        savingsPercent = try c.decodeIfPresent(Int.self, forKey: .savingsPercent)
        savingsTransferID = try c.decodeIfPresent(UUID.self, forKey: .savingsTransferID)
        savingsSkipped = try c.decodeIfPresent(Bool.self, forKey: .savingsSkipped) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(categoryID, forKey: .categoryID)
        try c.encodeIfPresent(walletID, forKey: .walletID)
        try c.encode(date, forKey: .date)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(savingsPercent, forKey: .savingsPercent)
        try c.encodeIfPresent(savingsTransferID, forKey: .savingsTransferID)
        if savingsSkipped { try c.encode(savingsSkipped, forKey: .savingsSkipped) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, currencyCode, rate, categoryID, walletID, date, createdAt, updatedAt
        case savingsPercent, savingsTransferID, savingsSkipped
    }
}
