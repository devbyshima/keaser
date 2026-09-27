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

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        categoryID: UUID? = nil,
        paymentMethodID: UUID? = nil,
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.categoryID = categoryID
        self.paymentMethodID = paymentMethodID
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    }
}
