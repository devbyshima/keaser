import Foundation

/// The features the 7-day pass unlocks and a purchase keeps.
public enum ProFeature: String, CaseIterable, Sendable, Identifiable {
    case widgets
    case moreFilters
    case multipleAccounts
    case longTermInsights

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .widgets: "Widgets"
        case .moreFilters: "More Filters"
        case .multipleAccounts: "Multiple Accounts"
        case .longTermInsights: "Long-term Insights"
        }
    }

    public var symbol: String {
        switch self {
        case .widgets: "plus.square.fill"
        case .moreFilters: "line.3.horizontal.decrease.circle.fill"
        case .multipleAccounts: "person.2.fill"
        case .longTermInsights: "chart.bar.fill"
        }
    }
}

/// Pure trial arithmetic, shared by the app and the widget extension. StoreKit
/// lives in the app; this only reads what the app cached in `Preferences`.
public enum ProEntitlement {
    public static let trialDays = 7

    /// Whole days left in the pass, rounded up, so a pass started a minute
    /// ago reads "7 days left". Nil when no pass was ever started; 0 once it
    /// has run out.
    public static func trialDaysRemaining(trialStart: Date?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let trialStart,
              let end = calendar.date(byAdding: .day, value: trialDays, to: trialStart)
        else { return nil }
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return min(trialDays, Int((seconds / 86_400).rounded(.up)))
    }

    public static func isTrialActive(trialStart: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        (trialDaysRemaining(trialStart: trialStart, now: now, calendar: calendar) ?? 0) > 0
    }

    public static func isPro(_ preferences: Preferences, now: Date) -> Bool {
        preferences.hasProPurchase || isTrialActive(trialStart: preferences.trialStartDate, now: now)
    }
}
