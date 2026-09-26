import Foundation

/// A spending category. `symbol` is an SF Symbol name.
///
/// Named `ExpenseCategory` rather than `Category` because Foundation already
/// exports an Objective-C `Category` type.
public struct ExpenseCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String

    public init(id: UUID = UUID(), name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

/// How an expense was paid. `symbol` is an SF Symbol name.
public struct PaymentMethod: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String

    public init(id: UUID = UUID(), name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

extension ExpenseCategory {
    /// What a new account starts with, in display order.
    public static func defaults() -> [ExpenseCategory] {
        [
            ExpenseCategory(name: "Food & Drinks", symbol: "fork.knife"),
            ExpenseCategory(name: "Shopping", symbol: "cart.fill"),
            ExpenseCategory(name: "Travel", symbol: "airplane"),
            ExpenseCategory(name: "Services", symbol: "wrench.and.screwdriver.fill"),
            ExpenseCategory(name: "Entertainment", symbol: "gamecontroller.fill"),
            ExpenseCategory(name: "Health", symbol: "heart.fill"),
            ExpenseCategory(name: "Transportation", symbol: "car.fill"),
        ]
    }

    /// Shown for an expense with no category.
    public static let fallbackSymbol = "creditcard"
}

extension PaymentMethod {
    /// What a new account starts with, in display order.
    public static func defaults() -> [PaymentMethod] {
        [
            PaymentMethod(name: "Credit Card", symbol: "creditcard.fill"),
            PaymentMethod(name: "Debit Card", symbol: "creditcard.and.123"),
            PaymentMethod(name: "Cash", symbol: "banknote.fill"),
            PaymentMethod(name: "Bank Transfer", symbol: "building.columns.fill"),
            PaymentMethod(name: "E-Wallet", symbol: "wallet.bifold.fill"),
        ]
    }
}
