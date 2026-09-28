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
        /// A shorter form for when `label` would collide with its
        /// neighbours at large text sizes: "S" for September, "M" for
        /// Monday. The same as `label` where there is none.
        public let narrowLabel: String
        /// Months have room for every label; days only for every seventh.
        public let showsLabel: Bool
        public var total: Decimal

        public var id: Int { index }

        public init(index: Int, interval: DateInterval, label: String, narrowLabel: String? = nil, showsLabel: Bool, total: Decimal = 0) {
            self.index = index
            self.interval = interval
            self.label = label
            self.narrowLabel = narrowLabel ?? label
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

    /// The value axis on a fixed 0...1 scale: bars and grid lines are placed
    /// as shares of the top tick rather than as amounts. Swift Charts lays
    /// its axis labels out with invalid (negative) frames while an animated
    /// change moves the scale's domain, as switching periods does when the
    /// tallest bar changes. With the domain fixed, only the bar heights and
    /// the label text change.
    public struct ValueScale: Equatable, Sendable {
        /// The grid line amounts, from `axisTicks(for:)`.
        public let ticks: [Double]

        public init(highest: Double) {
            ticks = SpendingChart.axisTicks(for: highest)
        }

        /// The chart's domain, the same for every period.
        public static let domain: ClosedRange<Double> = 0...1

        /// The top grid line's amount.
        public var top: Double { ticks.last ?? 0 }

        /// Where `amount` sits on the axis: 0 at the bottom, 1 at the top
        /// grid line.
        public func position(of amount: Double) -> Double {
            guard top > 0, amount.isFinite else { return 0 }
            return max(amount, 0) / top
        }

        /// The grid lines' positions.
        public var tickPositions: [Double] { ticks.map(position(of:)) }

        /// The amount printed beside the grid line at `position`: the
        /// nearest tick, so a label never shows a rounding error.
        public func tick(at position: Double) -> Double? {
            ticks.min { abs(self.position(of: $0) - position) < abs(self.position(of: $1) - position) }
        }
    }

    /// Whether the axis labels of `buckets`, each `width(label)` wide and
    /// centred under its bar, keep at least `gap` between neighbours on a
    /// plot `plotWidth` wide. When they do not, the chart shows
    /// `narrowLabel` instead.
    public static func labelsFit(
        _ buckets: [Bucket],
        plotWidth: Double,
        gap: Double = 4,
        width: (String) -> Double
    ) -> Bool {
        guard !buckets.isEmpty, plotWidth > 0 else { return true }
        let slot = plotWidth / Double(buckets.count)
        let labelled = buckets.filter(\.showsLabel)
        return zip(labelled, labelled.dropFirst()).allSatisfy { left, right in
            (width(left.label) + width(right.label)) / 2 + gap <= Double(right.index - left.index) * slot
        }
    }

    /// The text under `bucket` on the chart's axis: its label, or its
    /// `narrowLabel` when `narrow`, and nil for a bar that goes unlabelled
    /// (the days between a month's weekly labels). The chart asks this for
    /// every mark it draws, so the axis keeps to these labels even where
    /// Charts marks every category.
    public static func axisLabel(of bucket: Bucket, narrow: Bool) -> String? {
        guard bucket.showsLabel else { return nil }
        return narrow ? bucket.narrowLabel : bucket.label
    }

    /// What VoiceOver says for a bar, fuller than its axis label: "4 AM to
    /// 8 AM", "Monday, September 21", "September 15", "September 2026",
    /// "2026".
    public static func spokenName(
        of bucket: Bucket,
        period: Period,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        func string(_ date: Date, _ template: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }
        let start = bucket.interval.start
        switch period {
        case .today: return "\(string(start, "j")) to \(string(bucket.interval.end, "j"))"
        case .thisWeek: return string(start, "EEEEMMMMd")
        case .thisMonth: return string(start, "MMMMd")
        case .thisYear: return string(start, "MMMMyyyy")
        case .allTime: return string(start, "yyyy")
        }
    }

    /// The heading of the callout a long press shows over a bar: short
    /// enough to sit above its amount in a small card. "2026",
    /// "September", "Sep 26", "Sat, Sep 26", "8 AM – 12 PM".
    public static func calloutTitle(
        of bucket: Bucket,
        period: Period,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        func string(_ date: Date, _ template: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }
        let start = bucket.interval.start
        switch period {
        case .today: return "\(string(start, "j")) \u{2013} \(string(bucket.interval.end, "j"))"
        case .thisWeek: return string(start, "EEEMMMd")
        case .thisMonth: return string(start, "MMMd")
        case .thisYear: return string(start, "MMMM")
        case .allTime: return string(start, "yyyy")
        }
    }

    /// Where the long-press callout's leading edge goes: centred over the
    /// bar whose middle is at `barCenter`, but kept inside a chart
    /// `chartWidth` wide (flush with its leading edge if it cannot fit).
    public static func calloutLeading(barCenter: Double, calloutWidth: Double, chartWidth: Double) -> Double {
        let centred = barCenter - calloutWidth / 2
        return min(max(centred, 0), max(chartWidth - calloutWidth, 0))
    }

    /// Where the long-press callout rests, in the chart's coordinates (y
    /// grows downwards): its leading edge and its bottom edge.
    public struct CalloutPlacement: Equatable, Sendable {
        public var leading: Double
        public var bottom: Double

        public init(leading: Double, bottom: Double) {
            self.leading = leading
            self.bottom = bottom
        }
    }

    /// A rectangle in the chart's coordinates (y grows downwards).
    public struct Area: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            minX = x
            minY = y
            maxX = x + width
            maxY = y + height
        }

        public var isEmpty: Bool { maxX <= minX || maxY <= minY }

        /// Whether the two share more than an edge.
        public func overlaps(_ other: Area) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }

        func grown(by amount: Double) -> Area {
            Area(x: minX - amount, y: minY - amount, width: maxX - minX + 2 * amount, height: maxY - minY + 2 * amount)
        }
    }

    /// Where the long-press callout rests, never over `keepClear` (the
    /// period's total, printed above the chart; nil or empty when there is
    /// nothing to avoid). In order:
    ///
    /// 1. Centred over its bar, `gap` above the plot, as in the reference.
    /// 2. Where that would cover the total (a bar near the leading edge):
    ///    `gap` above the bar's top, inside the plot.
    /// 3. Where the bar is too tall for that: beside the bar, on the
    ///    trailing side if the chart has room there, else the leading one,
    ///    with its top just under the total.
    ///
    /// It always stays inside the chart, `chartWidth` wide. `barTop` and
    /// `plotTop` are y positions; `barWidth` is the drawn bar's width.
    public static func calloutPlacement(
        barCenter: Double,
        barWidth: Double,
        barTop: Double,
        calloutWidth: Double,
        calloutHeight: Double,
        chartWidth: Double,
        plotTop: Double,
        keepClear: Area?,
        gap: Double = 14,
        margin: Double = 4
    ) -> CalloutPlacement {
        let centred = calloutLeading(barCenter: barCenter, calloutWidth: calloutWidth, chartWidth: chartWidth)
        let abovePlot = CalloutPlacement(leading: centred, bottom: plotTop - gap)
        guard let keepClear, !keepClear.isEmpty else { return abovePlot }
        let avoided = keepClear.grown(by: margin)
        func isClear(_ placement: CalloutPlacement) -> Bool {
            !avoided.overlaps(Area(x: placement.leading, y: placement.bottom - calloutHeight, width: calloutWidth, height: calloutHeight))
        }
        if isClear(abovePlot) { return abovePlot }
        let aboveBar = CalloutPlacement(leading: centred, bottom: max(barTop, plotTop) - gap)
        if isClear(aboveBar) { return aboveBar }
        let bottom = avoided.maxY + calloutHeight
        let trailing = barCenter + barWidth / 2 + margin
        if trailing + calloutWidth <= chartWidth {
            return CalloutPlacement(leading: trailing, bottom: bottom)
        }
        let leading = barCenter - barWidth / 2 - margin - calloutWidth
        return CalloutPlacement(leading: max(leading, 0), bottom: bottom)
    }

    /// How far below its resting place the callout starts as it grows out
    /// of its bar: down to the bar's top (`barTop`, with y growing
    /// downwards), but never more than `limit`, so a short bar does not
    /// send it flying across the whole plot.
    public static func calloutRise(barTop: Double, calloutBottom: Double, limit: Double = 72) -> Double {
        min(max(barTop - calloutBottom, 0), limit)
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
            let narrow = calendar.veryShortStandaloneMonthSymbols
            return subdivide(year, by: .month, calendar: calendar) { index, start in
                let month = calendar.component(.month, from: start) - 1
                return (symbols[month % symbols.count], narrow[month % narrow.count], true)
            }
        case .thisMonth:
            guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
            return subdivide(month, by: .day, calendar: calendar) { index, start in
                let day = String(calendar.component(.day, from: start))
                return (day, day, index % 7 == 0)
            }
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            let symbols = calendar.shortStandaloneWeekdaySymbols
            let narrow = calendar.veryShortStandaloneWeekdaySymbols
            return subdivide(week, by: .day, calendar: calendar) { _, start in
                let weekday = calendar.component(.weekday, from: start) - 1
                return (symbols[weekday % symbols.count], narrow[weekday % narrow.count], true)
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
        label: (Int, Date) -> (label: String, narrow: String, shows: Bool)
    ) -> [Bucket] {
        var result: [Bucket] = []
        var start = interval.start
        while start < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: start), next > start else { break }
            let end = min(next, interval.end)
            let text = label(result.count, start)
            result.append(Bucket(
                index: result.count,
                interval: DateInterval(start: start, end: end),
                label: text.label,
                narrowLabel: text.narrow,
                showsLabel: text.shows
            ))
            start = end
        }
        return result
    }
}
