import Foundation

/// The whole persisted state: one JSON file shared by the app and the widget
/// extension through the app group container.
public struct Database: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var accounts: [Account]
    public var preferences: Preferences

    public init(accounts: [Account] = [], preferences: Preferences = Preferences()) {
        self.version = Self.currentVersion
        self.accounts = accounts
        self.preferences = preferences
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }

    /// The account the user is looking at: the stored selection when it still
    /// exists, otherwise the first account.
    public var selectedAccount: Account? {
        accounts.first { $0.id == preferences.selectedAccountID } ?? accounts.first
    }
}

public enum Weekday: Int, Codable, CaseIterable, Sendable, Identifiable {
    // Raw values match `Calendar.firstWeekday`.
    case sunday = 1
    case monday = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        }
    }
}

public struct Preferences: Codable, Hashable, Sendable {
    /// ISO 4217 code used to display every amount.
    public var currencyCode: String
    public var firstWeekday: Weekday
    public var smartSuggestionsEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var hasSeenWelcomeLetter: Bool
    /// The user's choice; the system permission is checked separately.
    public var weeklySummaryEnabled: Bool
    /// When the 7-day Pro pass began. Nil until onboarding grants it.
    public var trialStartDate: Date?
    /// Cached StoreKit entitlement, so the widget extension can read it.
    public var hasProPurchase: Bool
    /// When the cached purchase stops granting Pro. Nil for a lifetime
    /// purchase. For a subscription it is the period end, plus a short
    /// allowance when it will auto-renew, or the end of a billing grace
    /// period. Once it passes, the app and the widget confirm with StoreKit
    /// before treating the subscription as lapsed.
    public var proExpirationDate: Date?
    public var selectedAccountID: UUID?

    public init(
        currencyCode: String = Preferences.defaultCurrencyCode,
        firstWeekday: Weekday = .sunday,
        smartSuggestionsEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false,
        hasSeenWelcomeLetter: Bool = false,
        weeklySummaryEnabled: Bool = false,
        trialStartDate: Date? = nil,
        hasProPurchase: Bool = false,
        proExpirationDate: Date? = nil,
        selectedAccountID: UUID? = nil
    ) {
        self.currencyCode = currencyCode
        self.firstWeekday = firstWeekday
        self.smartSuggestionsEnabled = smartSuggestionsEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasSeenWelcomeLetter = hasSeenWelcomeLetter
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.trialStartDate = trialStartDate
        self.hasProPurchase = hasProPurchase
        self.proExpirationDate = proExpirationDate
        self.selectedAccountID = selectedAccountID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? d.currencyCode
        firstWeekday = try c.decodeIfPresent(Weekday.self, forKey: .firstWeekday) ?? d.firstWeekday
        smartSuggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .smartSuggestionsEnabled) ?? d.smartSuggestionsEnabled
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        hasSeenWelcomeLetter = try c.decodeIfPresent(Bool.self, forKey: .hasSeenWelcomeLetter) ?? d.hasSeenWelcomeLetter
        weeklySummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled) ?? d.weeklySummaryEnabled
        trialStartDate = try c.decodeIfPresent(Date.self, forKey: .trialStartDate)
        hasProPurchase = try c.decodeIfPresent(Bool.self, forKey: .hasProPurchase) ?? d.hasProPurchase
        proExpirationDate = try c.decodeIfPresent(Date.self, forKey: .proExpirationDate)
        selectedAccountID = try c.decodeIfPresent(UUID.self, forKey: .selectedAccountID)
    }

    public static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// The user's calendar with their chosen first day of the week. Every
    /// "this week" computation must go through this.
    public var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday.rawValue
        return calendar
    }
}
