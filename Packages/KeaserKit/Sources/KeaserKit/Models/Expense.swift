import Foundation

/// One spend. Money is `Decimal` so that 0.1 + 0.2 stays 0.3 on screen; it is
/// only ever converted to `Double` for chart geometry.
public struct Expense: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var amount: Decimal
    public var categoryID: UUID?
    public var paymentMethodID: UUID?
    /// The day the money was spent. Only the calendar day is meaningful.
    public var date: Date
    public var createdAt: Date
    public var updatedAt: Date
    /// The photos of receipts kept with the expense, oldest first, at most
    /// `ReceiptList.maximum`. The images are files in the Receipts folder,
    /// never in the database.
    public var receipts: [ReceiptPhoto]
    /// The currency of `amount`. Nil: its wallet's (`paymentMethodID`), and
    /// with no wallet, the display currency. Written only when the wallet
    /// has a currency of its own, or once that wallet is deleted.
    public var currencyCode: String?
    /// The rate to the display currency, saved when it was logged in
    /// another currency.
    public var rate: ExchangeRate?

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        categoryID: UUID? = nil,
        paymentMethodID: UUID? = nil,
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        receipts: [ReceiptPhoto] = [],
        currencyCode: String? = nil,
        rate: ExchangeRate? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.categoryID = categoryID
        self.paymentMethodID = paymentMethodID
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.receipts = receipts
        self.currencyCode = currencyCode
        self.rate = rate
    }

    // Tolerant decoding: a field added in a later version must not make an
    // older database file unreadable.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        amount = try c.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        paymentMethodID = try c.decodeIfPresent(UUID.self, forKey: .paymentMethodID)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        // A reference that does not read loses only that photo, never the
        // expense or its other photos. An expense from before the list
        // (a single `receipt`) keeps its one photo.
        if let list = try? c.decodeIfPresent([LossyReceipt].self, forKey: .receipts) {
            receipts = list.compactMap(\.photo)
        } else if let single = try? c.decodeIfPresent(ReceiptPhoto.self, forKey: .receipt) {
            receipts = [single]
        } else {
            receipts = []
        }
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode)
        // A rate that does not read is lost alone, never the expense.
        rate = try? c.decodeIfPresent(ExchangeRate.self, forKey: .rate)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(categoryID, forKey: .categoryID)
        try c.encodeIfPresent(paymentMethodID, forKey: .paymentMethodID)
        try c.encode(date, forKey: .date)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        // Left out when empty, so an expense without receipts is written
        // exactly as before.
        if !receipts.isEmpty { try c.encode(receipts, forKey: .receipts) }
        // The same for the currency and the rate.
        try c.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try c.encodeIfPresent(rate, forKey: .rate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, categoryID, paymentMethodID, date, createdAt, updatedAt, receipts, currencyCode, rate
        /// The single photo an expense could carry before the list; read,
        /// never written.
        case receipt
    }

    /// One entry of the list, or nil when it does not read.
    private struct LossyReceipt: Decodable {
        let photo: ReceiptPhoto?

        init(from decoder: any Decoder) throws {
            photo = try? ReceiptPhoto(from: decoder)
        }
    }
}
