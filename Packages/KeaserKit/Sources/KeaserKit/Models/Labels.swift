import Foundation

/// A spending category. `symbol` is an SF Symbol name.
///
/// Named `ExpenseCategory` rather than `Category` because Foundation already
/// exports an Objective-C `Category` type.
public struct ExpenseCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// When the name or symbol last changed, on whichever device changed
    /// it. `KeaserStore` stamps it; iCloud sync keeps the later of two
    /// edits. `.distantPast` for categories saved before it existed.
    public var updatedAt: Date
    /// Which envelope of the split rule its spending counts against.
    /// Guessed from the name for categories saved before it existed, and
    /// always written, so a rename never changes it.
    public var role: CategoryRole

    /// A nil `role` is guessed from the name (`CategoryRole.guess(forName:)`).
    public init(id: UUID = UUID(), name: String, symbol: String, updatedAt: Date = .now, role: CategoryRole? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.updatedAt = updatedAt
        self.role = role ?? .guess(forName: name)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? Self.fallbackSymbol
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        role = try c.decodeIfPresent(CategoryRole.self, forKey: .role) ?? .guess(forName: name)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(role, forKey: .role)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, updatedAt, role
    }
}

/// How an expense was paid, and the wallet the money is in: cash, a bank
/// account, mobile money, a credit card. `symbol` is an SF Symbol name.
/// The type keeps its name (and its IDs, intents, entities and sync
/// records) from before it held money.
///
/// - A wallet's balance is the money in it. A credit card that owes 500
///   has a balance of -500, so a card counts against the total as a
///   negative with no special case.
/// - A nil `currencyCode` means the wallet is in the display currency
///   (`Preferences.currencyCode`), whatever that is at the time, so the
///   Currency setting still relabels everything for someone who never
///   picks a wallet currency. An explicit code pins it.
/// - A nil `trackingSince` means the wallet is not tracking a balance
///   ("Not Tracking"). Otherwise the balance was `openingBalance` at that
///   moment, the wallet's first checkpoint.
public struct PaymentMethod: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// When anything about it last changed (see `ExpenseCategory.updatedAt`).
    public var updatedAt: Date
    /// Guessed from the name for methods saved before it existed, and
    /// always written, so a rename never changes it.
    public var kind: WalletKind
    /// The wallet's own currency; nil: the display currency.
    public var currencyCode: String?
    /// When the balance started being tracked; nil: not tracking.
    public var trackingSince: Date?
    /// The balance at `trackingSince`, in the wallet's currency.
    public var openingBalance: Decimal
    /// A credit card's limit, in the wallet's currency.
    public var creditLimit: Decimal?
    /// Where the split rule's Savings goes.
    public var isSavings: Bool
    /// Left out of the wallet list and the total balance.
    public var isHidden: Bool

    /// A nil `kind` is guessed from the name (`WalletKind.guess(forName:)`).
    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        updatedAt: Date = .now,
        kind: WalletKind? = nil,
        currencyCode: String? = nil,
        trackingSince: Date? = nil,
        openingBalance: Decimal = 0,
        creditLimit: Decimal? = nil,
        isSavings: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.updatedAt = updatedAt
        self.kind = kind ?? .guess(forName: name)
        self.currencyCode = currencyCode
        self.trackingSince = trackingSince
        self.openingBalance = openingBalance
        self.creditLimit = creditLimit
        self.isSavings = isSavings
        self.isHidden = isHidden
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ExpenseCategory.fallbackSymbol
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        kind = try c.decodeIfPresent(WalletKind.self, forKey: .kind) ?? .guess(forName: name)
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode)
        trackingSince = try c.decodeIfPresent(Date.self, forKey: .trackingSince)
        openingBalance = try c.decodeIfPresent(Decimal.self, forKey: .openingBalance) ?? 0
        creditLimit = try c.decodeIfPresent(Decimal.self, forKey: .creditLimit)
        isSavings = try c.decodeIfPresent(Bool.self, forKey: .isSavings) ?? false
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    // The wallet fields are left out at their defaults, so a method that
    // holds no money is written as before, plus its kind.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try c.encodeIfPresent(trackingSince, forKey: .trackingSince)
        if openingBalance != 0 { try c.encode(openingBalance, forKey: .openingBalance) }
        try c.encodeIfPresent(creditLimit, forKey: .creditLimit)
        if isSavings { try c.encode(isSavings, forKey: .isSavings) }
        if isHidden { try c.encode(isHidden, forKey: .isHidden) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, updatedAt, kind, currencyCode, trackingSince, openingBalance, creditLimit, isSavings, isHidden
    }

    /// Whether the wallet tracks a balance (Set Balance was used).
    public var isTracking: Bool { trackingSince != nil }

    public var isCreditCard: Bool { kind == .creditCard }

    /// The wallet's currency: its own, or the display currency.
    public func effectiveCurrency(display: String) -> String {
        currencyCode ?? display
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

/// What kind of wallet a payment method is. An open set: a kind written
/// by a later version reads, survives edits here and is written back.
public struct WalletKind: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let cash = WalletKind("cash")
    public static let bank = WalletKind("bank")
    public static let mobileMoney = WalletKind("mobileMoney")
    public static let creditCard = WalletKind("creditCard")
    public static let other = WalletKind("other")

    /// The kinds this version knows, in display order.
    public static let known: [WalletKind] = [.cash, .bank, .mobileMoney, .creditCard, .other]

    /// The kind a payment method of this name most likely is: the built-in
    /// methods by name, anything else `.other`.
    public static func guess(forName name: String) -> WalletKind {
        switch labelKey(name) {
        case "credit card": .creditCard
        case "debit card", "bank transfer", "bank account", "bank": .bank
        case "cash": .cash
        case "e-wallet", "mobile money", "momo": .mobileMoney
        default: .other
        }
    }
}

/// Which envelope of the split rule a spending category counts against:
/// Expenses (what has to be paid) or Free Money (what is chosen). An open
/// set, like `WalletKind`.
public struct CategoryRole: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let expenses = CategoryRole("expenses")
    public static let freeMoney = CategoryRole("freeMoney")

    /// The built-in categories by name; a category the person adds is
    /// Expenses until changed.
    public static func guess(forName name: String) -> CategoryRole {
        switch labelKey(name) {
        case "food & drinks", "transportation", "health", "services": .expenses
        case "shopping", "entertainment", "travel": .freeMoney
        default: .expenses
        }
    }
}

/// A name as the app compares names: trimmed, ignoring case and accents.
/// Also how iCloud sync recognises the same label or account made on two
/// devices.
func labelKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}
