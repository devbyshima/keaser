import Foundation

/// The rate saved on a transaction (an expense, an income or a transfer)
/// in another currency, so its converted value never moves when rates
/// change.
public struct ExchangeRate: Codable, Hashable, Sendable {
    /// One unit of the entry's currency is `rate` units of `currencyCode`.
    public var rate: Decimal
    /// What it converts into: the display currency when it was saved.
    public var currencyCode: String
    /// The day the rate is for (fetched), or when it was typed.
    public var date: Date
    /// True when the person typed it rather than taking the day's rate.
    public var isTyped: Bool

    public init(rate: Decimal, currencyCode: String, date: Date, isTyped: Bool = false) {
        self.rate = rate
        self.currencyCode = currencyCode
        self.date = date
        self.isTyped = isTyped
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate = try c.decodeIfPresent(Decimal.self, forKey: .rate) ?? 0
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        isTyped = try c.decodeIfPresent(Bool.self, forKey: .isTyped) ?? false
    }

    /// False for a rate of 0 or less, or one without a currency: the maths
    /// treats it as no saved rate at all.
    public var isUsable: Bool {
        rate > 0 && !currencyCode.isEmpty
    }
}
