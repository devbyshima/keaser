import Foundation

/// The one local notification Keaser keeps pending: what it says and when it
/// fires. The app turns a plan into a `UNNotificationRequest`; everything that
/// can be decided without UserNotifications is decided here.
public struct WeeklySummaryPlan: Equatable, Sendable {
    /// When the notification fires: 7:00 pm on the last day of `week`.
    public var fireDate: Date
    /// The week whose spending `body` reports.
    public var week: DateInterval
    public var title: String
    public var body: String
}

public enum WeeklySummary {
    /// The request identifier. Reusing it replaces the pending notification
    /// instead of stacking a second one.
    public static let identifier = "weekly-summary"
    public static let title = "Weekly summary"
    /// Local time the summary arrives on the last day of the week.
    public static let hour = 19

    /// 7:00 pm on the last day of the week containing `now`, or on the last day
    /// of the following week once that moment has passed. `calendar` decides
    /// where weeks start, so pass `Preferences.calendar`.
    public static func nextFireDate(after now: Date, calendar: Calendar) -> Date? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let fire = fireDate(in: week, calendar: calendar)
        else { return nil }
        if fire > now { return fire }
        guard let next = calendar.dateInterval(of: .weekOfYear, for: week.end) else { return nil }
        return fireDate(in: next, calendar: calendar)
    }

    /// "You spent $188.20 this week."
    public static func body(total: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        "You spent \(MoneyFormat.string(total, currencyCode: currencyCode, locale: locale)) this week."
    }

    /// The notification to keep scheduled, or nil when there should be none
    /// (the user turned the summary off, or there is no account yet). The body
    /// reports the selected account's spending in the week the notification
    /// fires in, so rescheduling after every change keeps the number current.
    public static func plan(
        for database: Database,
        now: Date,
        calendar: Calendar? = nil,
        locale: Locale = .current
    ) -> WeeklySummaryPlan? {
        let preferences = database.preferences
        guard preferences.weeklySummaryEnabled, let account = database.selectedAccount else { return nil }
        let calendar = calendar ?? preferences.calendar
        guard let fire = nextFireDate(after: now, calendar: calendar),
              let week = calendar.dateInterval(of: .weekOfYear, for: fire)
        else { return nil }
        return WeeklySummaryPlan(
            fireDate: fire,
            week: week,
            title: title,
            body: body(total: account.total(in: week), currencyCode: preferences.currencyCode, locale: locale)
        )
    }

    private static func fireDate(in week: DateInterval, calendar: Calendar) -> Date? {
        // `week.end` is the first instant of the next week, so the last day is
        // the one containing the instant just before it.
        let lastDay = calendar.startOfDay(for: week.end.addingTimeInterval(-1))
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: lastDay)
    }
}
