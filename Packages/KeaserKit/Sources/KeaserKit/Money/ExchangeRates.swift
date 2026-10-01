import Foundation

/// A day's exchange rates: how many units of each currency one unit of
/// `base` buys. Kept on the device for today's balances and new entries,
/// never synced; what syncs is the rate saved on each transaction
/// (`ExchangeRate`).
public struct ExchangeRates: Codable, Hashable, Sendable {
    /// The currency the table is quoted against ("USD").
    public var base: String
    /// Units of each currency per one `base`; `base` itself is 1.
    public var rates: [String: Decimal]
    /// The day the rates are for.
    public var date: Date
    /// When they were fetched.
    public var fetchedAt: Date

    public init(base: String, rates: [String: Decimal], date: Date, fetchedAt: Date) {
        self.base = base
        self.rates = rates
        self.date = date
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.decodeIfPresent(String.self, forKey: .base) ?? ""
        rates = try c.decodeIfPresent([String: Decimal].self, forKey: .rates) ?? [:]
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? date
    }

    /// How many units of `to` one unit of `from` buys, or nil when the
    /// table lacks either currency (or has 0 for it). Codes compare
    /// upper-cased.
    public func rate(from: String, to: String) -> Decimal? {
        guard let from = units(of: from), let to = units(of: to) else { return nil }
        return to / from
    }

    /// `amount` of `from` in `to` at the table's rates, not rounded, or nil
    /// when `rate(from:to:)` is. It multiplies before it divides, so a
    /// result that is exact (7 RWF at 1400 to the dollar is 0.005 USD) is
    /// rounded as exactly that, not as a cut-short quotient.
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        guard let from = units(of: from), let to = units(of: to) else { return nil }
        return amount * to / from
    }

    /// Units of `code` per one `base`.
    private func units(of code: String) -> Decimal? {
        let code = code.uppercased()
        guard !code.isEmpty else { return nil }
        if code == base.uppercased() { return 1 }
        let found = rates[code] ?? rates.first { $0.key.uppercased() == code }?.value
        guard let found, found > 0 else { return nil }
        return found
    }
}
