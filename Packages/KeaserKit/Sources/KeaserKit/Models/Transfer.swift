import Foundation

/// Why money moved between two wallets. An open set, like `WalletKind`.
public struct TransferKind: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// One the person made.
    public static let manual = TransferKind("manual")
    /// The split rule's Savings, made with an income (`Transfer.incomeID`).
    public static let savings = TransferKind("savings")
    /// Paying off a credit card: a transfer into it.
    public static let cardPayment = TransferKind("cardPayment")
}

/// Money moved from one wallet to another. Between currencies, what
/// arrives (`amountIn`) differs from what left (`amountOut`).
public struct Transfer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: TransferKind
    /// Nil once that wallet is deleted.
    public var fromWalletID: UUID?
    public var toWalletID: UUID?
    /// What left `fromWalletID`, in `currencyOut`.
    public var amountOut: Decimal
    /// Nil: the from wallet's currency, and with no wallet, the display
    /// currency.
    public var currencyOut: String?
    /// What arrived in `toWalletID`, in `currencyIn`; the same as
    /// `amountOut` within one currency.
    public var amountIn: Decimal
    /// Nil: the to wallet's currency, and with no wallet, the display
    /// currency.
    public var currencyIn: String?
    /// The rate from `amountOut`'s currency to the display currency, saved
    /// when it was made.
    public var rate: ExchangeRate?
    public var date: Date
    public var note: String
    /// The income a `.savings` transfer belongs to.
    public var incomeID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    /// A nil `amountIn` is `amountOut` (one currency).
    public init(
        id: UUID = UUID(),
        kind: TransferKind = .manual,
        fromWalletID: UUID?,
        toWalletID: UUID?,
        amountOut: Decimal,
        currencyOut: String? = nil,
        amountIn: Decimal? = nil,
        currencyIn: String? = nil,
        rate: ExchangeRate? = nil,
        date: Date = .now,
        note: String = "",
        incomeID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.fromWalletID = fromWalletID
        self.toWalletID = toWalletID
        self.amountOut = amountOut
        self.currencyOut = currencyOut
        self.amountIn = amountIn ?? amountOut
        self.currencyIn = currencyIn
        self.rate = rate
        self.date = date
        self.note = note
        self.incomeID = incomeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(TransferKind.self, forKey: .kind) ?? .manual
        fromWalletID = try c.decodeIfPresent(UUID.self, forKey: .fromWalletID)
        toWalletID = try c.decodeIfPresent(UUID.self, forKey: .toWalletID)
        amountOut = try c.decodeIfPresent(Decimal.self, forKey: .amountOut) ?? 0
        currencyOut = try c.decodeIfPresent(String.self, forKey: .currencyOut)
        amountIn = try c.decodeIfPresent(Decimal.self, forKey: .amountIn) ?? amountOut
        currencyIn = try c.decodeIfPresent(String.self, forKey: .currencyIn)
        rate = try? c.decodeIfPresent(ExchangeRate.self, forKey: .rate)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        incomeID = try c.decodeIfPresent(UUID.self, forKey: .incomeID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(fromWalletID, forKey: .fromWalletID)
        try c.encodeIfPresent(toWalletID, forKey: .toWalletID)
        try c.encode(amountOut, forKey: .amountOut)
        try c.encodeIfPresent(currencyOut, forKey: .currencyOut)
        try c.encode(amountIn, forKey: .amountIn)
        try c.encodeIfPresent(currencyIn, forKey: .currencyIn)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encode(date, forKey: .date)
        try c.encode(note, forKey: .note)
        try c.encodeIfPresent(incomeID, forKey: .incomeID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, fromWalletID, toWalletID, amountOut, currencyOut, amountIn, currencyIn, rate
        case date, note, incomeID, createdAt, updatedAt
    }
}

/// "The balance of `walletID` was `balance` at `date`": what Set Balance
/// records on a wallet that is already tracking. A later checkpoint for
/// the balance maths; it never edits history.
public struct BalanceAdjustment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var walletID: UUID?
    /// In `currencyCode`'s currency.
    public var balance: Decimal
    /// Nil: the wallet's currency, as for entries. A code pins it, so a
    /// balance stated in a wallet that merged into one in another currency
    /// keeps the currency it was stated in. Written only when set.
    public var currencyCode: String?
    /// The moment the balance was stated.
    public var date: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        walletID: UUID?,
        balance: Decimal,
        currencyCode: String? = nil,
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.walletID = walletID
        self.balance = balance
        self.currencyCode = currencyCode
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        walletID = try c.decodeIfPresent(UUID.self, forKey: .walletID)
        balance = try c.decodeIfPresent(Decimal.self, forKey: .balance) ?? 0
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
