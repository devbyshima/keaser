import Foundation

/// The part of `Preferences` iCloud sync shares between a person's devices:
/// how amounts and weeks read, and how Smart Suggestions and the Add Expense
/// shortcut behave.
///
/// The rest of `Preferences` belongs to one device and never syncs:
/// - `hasCompletedOnboarding`, `hasSeenWelcomeLetter`: each device shows
///   its own onboarding and letter.
/// - `weeklySummaryEnabled`: the summary is a notification scheduled on
///   each device, under that device's notification permission.
/// - `hasProPurchase`, `proExpirationDate`: a cache of StoreKit, which each
///   device asks for itself (purchases already follow the Apple Account).
/// - `selectedAccountID`: each device shows the account chosen on it.
///
/// `trialStartDate` syncs, and the earliest wins whatever the edit times
/// say: the 7-day pass is one pass per person, not one per device.
public struct SyncedSettings: Codable, Hashable, Sendable {
    public var currencyCode: String
    public var firstWeekday: Weekday
    public var smartSuggestionsEnabled: Bool
    public var shortcutConfirmsDetails: Bool
    public var shortcutGoBackEnabled: Bool
    public var shortcutSmartSuggestionsEnabled: Bool
    public var trialStartDate: Date?
    /// `Preferences.settingsUpdatedAt`.
    public var updatedAt: Date

    public init(_ preferences: Preferences) {
        currencyCode = preferences.currencyCode
        firstWeekday = preferences.firstWeekday
        smartSuggestionsEnabled = preferences.smartSuggestionsEnabled
        shortcutConfirmsDetails = preferences.shortcutConfirmsDetails
        shortcutGoBackEnabled = preferences.shortcutGoBackEnabled
        shortcutSmartSuggestionsEnabled = preferences.shortcutSmartSuggestionsEnabled
        trialStartDate = preferences.trialStartDate
        updatedAt = preferences.settingsUpdatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? d.currencyCode
        firstWeekday = try c.decodeIfPresent(Weekday.self, forKey: .firstWeekday) ?? d.firstWeekday
        smartSuggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .smartSuggestionsEnabled) ?? d.smartSuggestionsEnabled
        shortcutConfirmsDetails = try c.decodeIfPresent(Bool.self, forKey: .shortcutConfirmsDetails) ?? d.shortcutConfirmsDetails
        shortcutGoBackEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortcutGoBackEnabled) ?? d.shortcutGoBackEnabled
        shortcutSmartSuggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortcutSmartSuggestionsEnabled) ?? d.shortcutSmartSuggestionsEnabled
        trialStartDate = try c.decodeIfPresent(Date.self, forKey: .trialStartDate)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    /// Writes these settings into `preferences`, leaving the device's own
    /// fields alone. The pass start becomes the earlier of the two.
    public func apply(to preferences: inout Preferences) {
        preferences.currencyCode = currencyCode
        preferences.firstWeekday = firstWeekday
        preferences.smartSuggestionsEnabled = smartSuggestionsEnabled
        preferences.shortcutConfirmsDetails = shortcutConfirmsDetails
        preferences.shortcutGoBackEnabled = shortcutGoBackEnabled
        preferences.shortcutSmartSuggestionsEnabled = shortcutSmartSuggestionsEnabled
        preferences.trialStartDate = Self.earlier(preferences.trialStartDate, trialStartDate)
        preferences.settingsUpdatedAt = updatedAt
    }

    /// Whether the settings differ, apart from when they were changed.
    public func differs(from other: SyncedSettings) -> Bool {
        var other = other
        other.updatedAt = updatedAt
        return self != other
    }

    /// The earlier of two optional dates; nil only when both are.
    public static func earlier(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (let a?, let b?): min(a, b)
        case (let a?, nil): a
        case (nil, let b): b
        }
    }
}
