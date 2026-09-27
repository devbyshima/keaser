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

extension ExpenseCategory {
    /// The icon a built-in category ("Food & Drinks", "Travel"...) starts
    /// with, for "Reset to Default". Matched by name, ignoring case and
    /// accents, so it also works for accounts created before this existed.
    /// Nil for a category the user added.
    public static func defaultSymbol(forName name: String) -> String? {
        let key = labelKey(name)
        return defaults().first { labelKey($0.name) == key }?.symbol
    }
}

extension PaymentMethod {
    /// The icon a built-in payment method starts with, for "Reset to
    /// Default". Nil for a method the user added.
    public static func defaultSymbol(forName name: String) -> String? {
        let key = labelKey(name)
        return defaults().first { labelKey($0.name) == key }?.symbol
    }
}

private func labelKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}
