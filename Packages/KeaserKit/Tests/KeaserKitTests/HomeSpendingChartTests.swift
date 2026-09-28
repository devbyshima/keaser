import Foundation
import Testing
@testable import KeaserKit

struct HomeSpendingChartTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Saturday 26 Sep 2026.
    private var now: Date { date(2026, 9, 26) }

    private func buckets(_ period: Period, _ expenses: [Expense], firstWeekday: Int = 1) -> [SpendingChart.Bucket] {
        SpendingChart.buckets(for: expenses, period: period, now: now, calendar: calendar(firstWeekday: firstWeekday), locale: locale)
    }

    @Test func allTimeShowsAtLeastFourYearsEndingThisYear() {
        let result = buckets(.allTime, [Expense(title: "Outing", amount: 20, date: now)])
        #expect(result.map(\.label) == ["2023", "2024", "2025", "2026"])
        #expect(result.map(\.narrowLabel) == result.map(\.label))
        #expect(result.map(\.total) == [0, 0, 0, 20])
        #expect(result.map(\.index) == [0, 1, 2, 3])
        #expect(result.allSatisfy { $0.showsLabel })
    }

    @Test func allTimeReachesBackToTheEarliestExpense() {
        let result = buckets(.allTime, [
            Expense(title: "Old", amount: 5, date: date(2019, 5, 1)),
            Expense(title: "New", amount: 7, date: now),
        ])
        #expect(result.first?.label == "2019")
        #expect(result.last?.label == "2026")
        #expect(result.count == 8)
        #expect(result.first?.total == 5)
    }

    @Test func thisYearIsTwelveMonths() {
        let result = buckets(.thisYear, [
            Expense(title: "Jan", amount: 1, date: date(2026, 1, 31)),
            Expense(title: "Sep", amount: 2, date: date(2026, 9, 1)),
            Expense(title: "Sep", amount: 3, date: date(2026, 9, 26)),
            Expense(title: "Last year", amount: 100, date: date(2025, 12, 31)),
        ])
        #expect(result.count == 12)
        #expect(result.first?.label == "Jan")
        #expect(result[8].label == "Sep")
        #expect(result.map(\.narrowLabel).joined() == "JFMAMJJASOND")
        #expect(result[0].total == 1)
        #expect(result[8].total == 5)
        #expect(result.map(\.total).reduce(0, +) == 6)
    }

    @Test func monthLabelsSwitchToNarrowOnesOnlyWhenNeighboursWouldTouch() {
        let year = buckets(.thisYear, [])
        // 12 slots of 25pt: three letters of 7pt leave 4pt between labels.
        #expect(SpendingChart.labelsFit(year, plotWidth: 300) { Double($0.count) * 7 })
        #expect(!SpendingChart.labelsFit(year, plotWidth: 300) { Double($0.count) * 8 })
        // Days are labelled every seventh bar, so wide labels still fit.
        let month = buckets(.thisMonth, [])
        #expect(SpendingChart.labelsFit(month, plotWidth: 300) { Double($0.count) * 20 })
        // Before the plot is measured nothing is shortened.
        #expect(SpendingChart.labelsFit(year, plotWidth: 0) { _ in 100 })
    }

    @Test func thisMonthIsOneBarPerDayWithWeeklyLabels() {
        let result = buckets(.thisMonth, [
            Expense(title: "a", amount: 4, date: date(2026, 9, 1, hour: 0)),
            Expense(title: "b", amount: 6, date: date(2026, 9, 30, hour: 23)),
            Expense(title: "c", amount: 9, date: date(2026, 10, 1, hour: 0)),
        ])
        #expect(result.count == 30)
        #expect(result.filter(\.showsLabel).map(\.label) == ["1", "8", "15", "22", "29"])
        #expect(result.allSatisfy { $0.narrowLabel == $0.label })
        #expect(result[0].total == 4)
        #expect(result[29].total == 6)
    }

    /// What the axis prints under each bar: a month's days only every
    /// seventh day (the view draws nothing for the others, however many
    /// marks Charts asks it for), a year's months in either width.
    @Test func theAxisPrintsOnlyTheLabelledBars() {
        let month = buckets(.thisMonth, [])
        #expect(month.compactMap { SpendingChart.axisLabel(of: $0, narrow: false) } == ["1", "8", "15", "22", "29"])
        #expect(month.compactMap { SpendingChart.axisLabel(of: $0, narrow: true) } == ["1", "8", "15", "22", "29"])
        #expect(SpendingChart.axisLabel(of: month[1], narrow: false) == nil)
        let year = buckets(.thisYear, [])
        #expect(year.compactMap { SpendingChart.axisLabel(of: $0, narrow: false) }.first == "Jan")
        #expect(year.compactMap { SpendingChart.axisLabel(of: $0, narrow: true) }.joined() == "JFMAMJJASOND")
    }

    @Test func thisWeekStartsOnTheChosenWeekday() {
        let expenses = [Expense(title: "Brunch", amount: 10, date: date(2026, 9, 21))] // Monday
        let sunday = buckets(.thisWeek, expenses, firstWeekday: 1)
        let monday = buckets(.thisWeek, expenses, firstWeekday: 2)
        #expect(sunday.map(\.label) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(monday.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(monday.map(\.narrowLabel).joined() == "MTWTFSS")
        #expect(sunday[1].total == 10)
        #expect(monday[0].total == 10)
    }

    @Test func todayUsesTheTimeTheExpenseWasLogged() {
        let midnight = calendar().startOfDay(for: now)
        let result = buckets(.today, [
            // Dated at midnight (date-only) but logged at 9:30, so 8 AM block.
            Expense(title: "Coffee", amount: 3, date: midnight, createdAt: midnight.addingTimeInterval(9.5 * 3600)),
            // Logged on another day: falls back to the date itself.
            Expense(title: "Backfilled", amount: 5, date: midnight.addingTimeInterval(21 * 3600), createdAt: date(2026, 9, 28)),
            Expense(title: "Yesterday", amount: 50, date: date(2026, 9, 25)),
        ])
        #expect(result.count == 24 / SpendingChart.hoursPerBlock)
        // ICU puts a narrow no-break space before AM/PM.
        let labels = result.map { $0.label.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(labels == ["12 AM", "4 AM", "8 AM", "12 PM", "4 PM", "8 PM"])
        #expect(result[2].total == 3)
        #expect(result[5].total == 5)
        #expect(result.map(\.total).reduce(0, +) == 8)
    }

    @Test func bucketsTileTheirPeriodWithoutGaps() {
        for period in Period.allCases {
            let result = buckets(period, [])
            #expect(!result.isEmpty)
            for (a, b) in zip(result, result.dropFirst()) {
                #expect(a.interval.end == b.interval.start)
            }
            if let interval = period.interval(containing: now, calendar: calendar()) {
                #expect(result.first?.interval.start == interval.start)
                #expect(result.last?.interval.end == interval.end)
            }
        }
    }

    @Test func barsHaveSpokenNamesForVoiceOver() {
        let c = calendar(firstWeekday: 2)
        let en = Locale(identifier: "en_US")
        func names(_ period: Period) -> [String] {
            SpendingChart.buckets(for: [], period: period, now: now, calendar: c, locale: en)
                .map { SpendingChart.spokenName(of: $0, period: period, calendar: c, locale: en) }
                // Recent formatters put a narrow no-break space before "AM".
                .map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        }
        #expect(names(.today).first == "12 AM to 4 AM")
        #expect(names(.today).last == "8 PM to 12 AM")
        #expect(names(.thisWeek).first == "Monday, September 21")
        #expect(names(.thisMonth)[14] == "September 15")
        #expect(names(.thisYear).first == "January 2026")
        #expect(names(.allTime).last == "2026")
    }

    /// The long-press callout: "2026" over the All Time bar, as in the
    /// recording, and short forms for the other periods.
    @Test func calloutTitlesAreShort() {
        let c = calendar(firstWeekday: 2)
        let en = Locale(identifier: "en_US")
        func titles(_ period: Period) -> [String] {
            SpendingChart.buckets(for: [], period: period, now: now, calendar: c, locale: en)
                .map { SpendingChart.calloutTitle(of: $0, period: period, calendar: c, locale: en) }
                .map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        }
        #expect(titles(.allTime).last == "2026")
        #expect(titles(.thisYear)[8] == "September")
        #expect(titles(.thisMonth)[25] == "Sep 26")
        #expect(titles(.thisWeek).first == "Mon, Sep 21")
        #expect(titles(.today)[2] == "8 AM \u{2013} 12 PM")
    }
}

struct HomeChartCalloutTests {
    @Test func calloutCentresOverItsBar() {
        #expect(SpendingChart.calloutLeading(barCenter: 150, calloutWidth: 80, chartWidth: 340) == 110)
    }

    @Test func calloutStaysInsideTheChart() {
        // The first bar of a month sits against the leading edge, the All
        // Time bar of this year near the trailing one.
        #expect(SpendingChart.calloutLeading(barCenter: 10, calloutWidth: 80, chartWidth: 340) == 0)
        #expect(SpendingChart.calloutLeading(barCenter: 330, calloutWidth: 80, chartWidth: 340) == 260)
    }

    @Test func calloutWiderThanTheChartStartsAtItsLeadingEdge() {
        #expect(SpendingChart.calloutLeading(barCenter: 50, calloutWidth: 120, chartWidth: 100) == 0)
    }

    @Test func calloutRisesFromTheBarTop() {
        // A full-height bar: the callout starts just below its resting place.
        #expect(SpendingChart.calloutRise(barTop: 0, calloutBottom: -10) == 10)
        #expect(SpendingChart.calloutRise(barTop: 40, calloutBottom: -10) == 50)
    }

    @Test func calloutRiseIsCapped() {
        #expect(SpendingChart.calloutRise(barTop: 180, calloutBottom: -10) == 72)
        #expect(SpendingChart.calloutRise(barTop: 180, calloutBottom: -10, limit: 30) == 30)
    }

    @Test func calloutNeverStartsAboveItsPlace() {
        #expect(SpendingChart.calloutRise(barTop: -20, calloutBottom: -10) == 0)
    }

    // The home card as laid out on an iPhone 16 Pro: a 338pt chart with its
    // plot starting 6pt down, the total's text 40pt above the chart, and a
    // callout 106 by 66pt as in the reference.
    private let total = SpendingChart.Area(x: 0, y: -88, width: 190, height: 48)

    private func placement(
        barCenter: Double,
        barTop: Double,
        keepClear: SpendingChart.Area?,
        barWidth: Double = 17.5,
        calloutWidth: Double = 106
    ) -> SpendingChart.CalloutPlacement {
        SpendingChart.calloutPlacement(
            barCenter: barCenter,
            barWidth: barWidth,
            barTop: barTop,
            calloutWidth: calloutWidth,
            calloutHeight: 66,
            chartWidth: 338,
            plotTop: 6,
            keepClear: keepClear
        )
    }

    @Test func calloutSitsOnTopOfItsBar() {
        // The All Time bar near the trailing edge, reaching the top of the
        // plot: 6pt above its top, clear of the total to its left.
        #expect(placement(barCenter: 280, barTop: 6, keepClear: total)
            == SpendingChart.CalloutPlacement(leading: 227, bottom: 0))
        // A short bar: the callout comes down with it instead of floating
        // at the top of the plot.
        #expect(placement(barCenter: 280, barTop: 150, keepClear: total)
            == SpendingChart.CalloutPlacement(leading: 227, bottom: 144))
        // Nothing to avoid (before the total is measured): the same rule.
        #expect(placement(barCenter: 12, barTop: 6, keepClear: nil)
            == SpendingChart.CalloutPlacement(leading: 0, bottom: 0))
        #expect(placement(barCenter: 12, barTop: 6, keepClear: SpendingChart.Area(x: 0, y: 0, width: 0, height: 0))
            == SpendingChart.CalloutPlacement(leading: 0, bottom: 0))
    }

    @Test func calloutSitsOnALowBarUnderTheTotal() {
        // January of This Year, $748 of a 2K scale: the bar's top is 110pt
        // into the plot, so the callout sits 6pt above it, under the total.
        let january = placement(barCenter: 12, barTop: 116, keepClear: total)
        #expect(january == SpendingChart.CalloutPlacement(leading: 0, bottom: 110))
        #expect(!total.overlaps(SpendingChart.Area(x: january.leading, y: january.bottom - 66, width: 106, height: 66)))
    }

    @Test func calloutGoesBesideATallBarUnderTheTotal() {
        // The tallest bar at the leading edge: no room above it, so beside
        // it on the trailing side, its top 4pt under the total.
        let tallest = placement(barCenter: 12, barTop: 6, keepClear: total)
        #expect(tallest == SpendingChart.CalloutPlacement(leading: 12 + 8.75 + 4, bottom: -40 + 4 + 66))
        #expect(!total.overlaps(SpendingChart.Area(x: tallest.leading, y: tallest.bottom - 66, width: 106, height: 66)))
        // A total as wide as the chart and a bar at the trailing edge:
        // beside it on the leading side.
        let wide = SpendingChart.Area(x: 0, y: -88, width: 338, height: 48)
        #expect(placement(barCenter: 320, barTop: 6, keepClear: wide)
            == SpendingChart.CalloutPlacement(leading: 320 - 8.75 - 4 - 106, bottom: -40 + 4 + 66))
    }

    @Test func calloutNeverCoversTheTotal() {
        // Every bar of a month and of a year, at every height.
        for count in [12, 31] {
            let slot = 300.0 / Double(count)
            for index in 0..<count {
                for barTop in stride(from: 6.0, through: 186, by: 20) {
                    let spot = placement(barCenter: slot * (Double(index) + 0.5), barTop: barTop, keepClear: total, barWidth: slot * 0.7)
                    let frame = SpendingChart.Area(x: spot.leading, y: spot.bottom - 66, width: 106, height: 66)
                    #expect(!total.overlaps(frame), "bar \(index) of \(count), top \(barTop)")
                    #expect(frame.minX >= 0 && frame.maxX <= 338)
                }
            }
        }
    }
}

struct HomeChartAxisTests {
    static let cases: [(highest: Double, ticks: [Double])] = [
        (0, [0, 5, 10, 15, 20]),
        (20, [0, 5, 10, 15, 20]),
        (22.63, [0, 5, 10, 15, 20, 25]),
        (7, [0, 2, 4, 6, 8]),
        (130, [0, 50, 100, 150]),
        (330.24, [0, 100, 200, 300, 400]),
        (9_000, [0, 2_000, 4_000, 6_000, 8_000, 10_000]),
        (0.3, [0, 0.1, 0.2, 0.3]),
    ]

    @Test(arguments: cases)
    func ticksAreRoundAndCoverTheTallestBar(_ example: (highest: Double, ticks: [Double])) {
        let ticks = SpendingChart.axisTicks(for: example.highest)
        #expect(ticks.count == example.ticks.count)
        for (tick, value) in zip(ticks, example.ticks) {
            #expect(abs(tick - value) < 0.000_1)
        }
        #expect((ticks.last ?? 0) >= example.highest)
        #expect(ticks.count <= 6)
    }

    @Test(arguments: cases)
    func theValueScaleMapsTheTicksOntoAFixedDomain(_ example: (highest: Double, ticks: [Double])) {
        let scale = SpendingChart.ValueScale(highest: example.highest)
        #expect(scale.ticks == SpendingChart.axisTicks(for: example.highest))
        #expect(scale.tickPositions.first == 0)
        #expect(scale.tickPositions.last == 1)
        #expect(scale.tickPositions.allSatisfy { SpendingChart.ValueScale.domain.contains($0) })
        #expect(SpendingChart.ValueScale.domain.contains(scale.position(of: example.highest)))
        // Every label reads back its own tick exactly.
        for (tick, position) in zip(scale.ticks, scale.tickPositions) {
            #expect(scale.tick(at: position) == tick)
        }
    }

    @Test func theValueScaleStaysInsideItsDomain() {
        let scale = SpendingChart.ValueScale(highest: 9_000)
        #expect(scale.position(of: 5_000) == 0.5)
        #expect(scale.position(of: 0) == 0)
        #expect(scale.position(of: -3) == 0)
        #expect(scale.position(of: .nan) == 0)
        #expect(scale.position(of: .infinity) == 0)
        // A period with a lower tallest bar keeps the same domain; only the
        // amounts on the grid lines change.
        let other = SpendingChart.ValueScale(highest: 1_700)
        #expect(other.top == 2_000)
        #expect(other.tickPositions == [0, 0.25, 0.5, 0.75, 1])
    }

}
