import Foundation

/// How an account's income is split by percentage: Savings moves to the
/// savings wallet with each income, and Expenses and Free Money are
/// budgets for the month, decided by each spending category's role.
public struct SplitRule: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var savingsPercent: Int
    public var expensesPercent: Int
    public var freeMoneyPercent: Int
    /// Where Savings goes: normally a wallet marked `isSavings`.
    public var savingsWalletID: UUID?
    /// When the rule last changed. `KeaserStore` stamps it; iCloud sync
    /// keeps the later of two edits.
    public var updatedAt: Date

    public init(
        isEnabled: Bool = false,
        savingsPercent: Int = 20,
        expensesPercent: Int = 50,
        freeMoneyPercent: Int = 30,
        savingsWalletID: UUID? = nil,
        updatedAt: Date = .distantPast
    ) {
        self.isEnabled = isEnabled
        self.savingsPercent = savingsPercent
        self.expensesPercent = expensesPercent
        self.freeMoneyPercent = freeMoneyPercent
        self.savingsWalletID = savingsWalletID
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SplitRule()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        savingsPercent = try c.decodeIfPresent(Int.self, forKey: .savingsPercent) ?? d.savingsPercent
        expensesPercent = try c.decodeIfPresent(Int.self, forKey: .expensesPercent) ?? d.expensesPercent
        freeMoneyPercent = try c.decodeIfPresent(Int.self, forKey: .freeMoneyPercent) ?? d.freeMoneyPercent
        savingsWalletID = try c.decodeIfPresent(UUID.self, forKey: .savingsWalletID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? d.updatedAt
    }

    /// Each percentage is from 0 to 100 and the three add up to 100.
    public var isValid: Bool {
        let parts = [savingsPercent, expensesPercent, freeMoneyPercent]
        return parts.allSatisfy { (0...100).contains($0) } && parts.reduce(0, +) == 100
    }
}
