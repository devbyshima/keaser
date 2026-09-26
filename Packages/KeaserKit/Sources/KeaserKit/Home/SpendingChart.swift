import Foundation

/// Splits expenses into the bars of the home chart. Each period has its own
/// resolution: years for All Time, months for This Year, days for This Month,
/// weekdays for This Week and blocks of hours for Today.
public enum SpendingChart {
    public struct Bucket: Identifiable, Hashable, Sendable {
        /// Position from the left, starting at 0. Also the chart's x value,
        /// because labels repeat ("T" for Tuesday and Thursday).
        public let index: Int
        public let interval: DateInterval
        /// Axis text under the bar: "2026", "Sep", "Mon", "15", "4 PM".
        public let label: String
        /// Months have room for every label; days only for every seventh.
        public let showsLabel: Bool
        public var total: Decimal

        public var id: Int { index }

        public init(index: Int, interval: DateInterval, label: String, showsLabel: Bool, total: Decimal = 0) {
            self.index = index
            self.interval = interval
            self.label = label
            self.showsLabel = showsLabel
            self.total = total
        }
    }

    /// All Time always shows at least this many years, ending with the
    /// current one, so a new account does not draw one lonely bar.
    public static let minimumYears = 4
    /// Today is split into this many hours per bar.
    public static let hoursPerBlock = 4

    public static func buckets(
        for expenses: [Expense],
        period: Period,
        now: Date,
        calendar: Calendar,
        locale: Locale = .current
    ) -> [Bucket] {
        var buckets = emptyBuckets(for: period, earliest: expenses.map(\.date).min(), now: now, calendar: calendar, locale: locale)
        guard let first = buckets.first, let last = buckets.last else { return buckets }
        let span = DateInterval(start: first.interval.start, end: last.interval.end)
        for expense in expenses {
            let moment = period == .today ? timeOfDay(of: expense, calendar: calendar) : expense.date
            guard span.contains(moment),
                  let index = buckets.firstIndex(where: { $0.interval.start <= moment && moment < $0.interval.end })
            else { continue }
            buckets[index].total += expense.amount
        }
        return buckets
    }

    /// Grid line values for the value axis, from 0 up to a round number at or
    /// above the tallest bar: the smallest 1, 2, 2.5 or 5 step (times a power
    /// of ten) that needs at most five intervals. A tallest bar of 20 gives
    /// 0, 5, 10, 15, 20, as in the reference. An empty chart still gets a
    /// scale so the card keeps its shape.
    public static func axisTicks(for highest: Double) -> [Double] {
        guard highest > 0, highest.isFinite else { return [0, 5, 10, 15, 20] }
        let maximumIntervals = 5.0
        var magnitude = pow(10, floor(log10(highest / maximumIntervals)))
        while true {
            for multiple in [1, 2, 2.5, 5] {
                let step = multiple * magnitude
                // A hair of tolerance so 20 stays 20 rather than 25.
                let intervals = (highest / step - 1e-9).rounded(.up)
                if intervals <= maximumIntervals {
                    return (0...Int(max(intervals, 1))).map { Double($0) * step }
                }
            }
            magnitude *= 10
        }
    }

    /// Only the calendar day of `Expense.date` is meaningful, so the hour
    /// comes from when the expense was logged if that was the same day.
    public static func timeOfDay(of expense: Expense, calendar: Calendar) -> Date {
        calendar.isDate(expense.createdAt, inSameDayAs: expense.date) ? expense.createdAt : expense.date
    }

    static func emptyBuckets(
        for period: Period,
        earliest: Date?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [Bucket] {
        var calendar = calendar
        calendar.locale = locale
        switch period {
        case .allTime:
            let currentYear = calendar.component(.year, from: now)
            let earliestYear = earliest.map { calendar.component(.year, from: $0) } ?? currentYear
            let firstYear = min(earliestYear, currentYear - (minimumYears - 1))
            return (firstYear...currentYear).enumerated().compactMap { index, year in
                guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                      let interval = calendar.dateInterval(of: .year, for: start)
                else { return nil }
                return Bucket(index: index, interval: interval, label: String(year), showsLabel: true)
            }
        case .thisYear:
            guard let year = calendar.dateInterval(of: .year, for: now) else { return [] }
            let symbols = calendar.shortStandaloneMonthSymbols
            return subdivide(year, by: .month, calendar: calendar) { index, start in
                let month = calendar.component(.month, from: start)
                return (symbols[(month - 1) % symbols.count], true)
            }
        case .thisMonth:
            guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
            return subdivide(month, by: .day, calendar: calendar) { index, start in
                let day = calendar.component(.day, from: start)
                return (String(day), index % 7 == 0)
            }
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            let symbols = calendar.shortStandaloneWeekdaySymbols
            return subdivide(week, by: .day, calendar: calendar) { _, start in
                let weekday = calendar.component(.weekday, from: start)
                return (symbols[(weekday - 1) % symbols.count], true)
            }
        case .today:
            guard let day = calendar.dateInterval(of: .day, for: now) else { return [] }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("j")
            // Blocks start at wall-clock hours (0, 4, 8...), so a daylight
            // saving day still reads 12 AM, 4 AM, 8 AM.
            let starts = stride(from: 0, to: 24, by: hoursPerBlock).compactMap {
                calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day.start)
            }
            return starts.enumerated().map { index, start in
                let end = index + 1 < starts.count ? starts[index + 1] : day.end
                return Bucket(index: index, interval: DateInterval(start: start, end: max(start, end)), label: formatter.string(from: start), showsLabel: true)
            }
        }
    }

    /// Consecutive sub-intervals of `interval`. Steps through the calendar
    /// rather than adding seconds, so daylight saving days still line up.
    private static func subdivide(
        _ interval: DateInterval,
        by component: Calendar.Component,
        calendar: Calendar,
        label: (Int, Date) -> (String, Bool)
    ) -> [Bucket] {
        var result: [Bucket] = []
        var start = interval.start
        while start < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: start), next > start else { break }
            let end = min(next, interval.end)
            let (text, shows) = label(result.count, start)
            result.append(Bucket(index: result.count, interval: DateInterval(start: start, end: end), label: text, showsLabel: shows))
            start = end
        }
        return result
    }
}
