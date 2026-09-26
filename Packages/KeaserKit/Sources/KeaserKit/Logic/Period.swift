import Foundation

/// The time window the home screen, widgets and notifications summarise.
public enum Period: String, CaseIterable, Codable, Sendable, Identifiable {
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case allTime

    public var id: String { rawValue }

    /// Menu title: "This Month".
    public var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .thisYear: "This Year"
        case .allTime: "All Time"
        }
    }

    /// Caption above the total: "Spent this month".
    public var spentCaption: String {
        switch self {
        case .today: "Spent today"
        case .thisWeek: "Spent this week"
        case .thisMonth: "Spent this month"
        case .thisYear: "Spent this year"
        case .allTime: "Spent all time"
        }
    }

    /// The window containing `now`, or nil for all time. Pass
    /// `Preferences.calendar` so weeks honour the user's first weekday.
    public func interval(containing now: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .today: calendar.dateInterval(of: .day, for: now)
        case .thisWeek: calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth: calendar.dateInterval(of: .month, for: now)
        case .thisYear: calendar.dateInterval(of: .year, for: now)
        case .allTime: nil
        }
    }

    /// Periods beyond the current month are the "Long-term Insights" Pro
    /// feature.
    public var isLongTerm: Bool { self == .thisYear || self == .allTime }
}

extension DateInterval {
    /// `start <= date < end`. Use this, never `contains`, for expenses:
    /// `contains` includes `end`, so an expense dated exactly at midnight
    /// (the usual case) would land in two adjacent days, weeks or months.
    public func holds(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
