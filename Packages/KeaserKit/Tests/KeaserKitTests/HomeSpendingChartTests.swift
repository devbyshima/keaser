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
        #expect(SpendingChart.calloutLeading(barCenter: 150, calloutWidth: 80, plotTrailing: 340) == 110)
    }

    @Test func calloutStaysOverThePlot() {
        // The first bar of a month sits against the leading edge, the All
        // Time bar of this year near the trailing one, where the value
        // labels begin.
        #expect(SpendingChart.calloutLeading(barCenter: 10, calloutWidth: 80, plotTrailing: 340) == 0)
        #expect(SpendingChart.calloutLeading(barCenter: 330, calloutWidth: 80, plotTrailing: 340) == 260)
    }

    @Test func calloutWiderThanThePlotStartsAtItsLeadingEdge() {
        #expect(SpendingChart.calloutLeading(barCenter: 50, calloutWidth: 120, plotTrailing: 100) == 0)
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

    // Round numbers for the home card: a plot ending at x 338 with its top
    // 6pt down, the total's line ending 40pt above the chart, and a callout
    // 106 by 66pt. The cases further down use the card as measured on an
    // iPhone 16 Pro, where the plot's top is the chart's top.
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
            plotTrailing: 338,
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

    @Test func calloutSinksIntoATallBarRatherThanLeaveIt() {
        // The tallest bar at the leading edge, right under the total: 6pt
        // above it would cover the total, so it sinks into the bar's top
        // just far enough to clear it (30pt, within half its height).
        let tallest = placement(barCenter: 12, barTop: 6, keepClear: total)
        #expect(tallest == SpendingChart.CalloutPlacement(leading: 0, bottom: -40 + 4 + 66))
        #expect(!total.overlaps(SpendingChart.Area(x: tallest.leading, y: tallest.bottom - 66, width: 106, height: 66)))
        // A total as wide as the chart ("RWF 100,000") over the one All Time
        // bar at the trailing edge: on top of that bar, not beside it.
        let wide = SpendingChart.Area(x: 0, y: -88, width: 338, height: 48)
        let allTime = placement(barCenter: 320, barTop: 6, keepClear: wide)
        #expect(allTime == SpendingChart.CalloutPlacement(leading: 338 - 106, bottom: -40 + 4 + 66))
        #expect(!wide.overlaps(SpendingChart.Area(x: allTime.leading, y: allTime.bottom - 66, width: 106, height: 66)))
    }

    @Test func calloutGoesBesideOnlyWhenSinkingIsNotEnough() {
        // A total reaching 20pt from the plot: clearing it would sink the
        // callout more than half its height into the bar, so it goes beside
        // the bar on the trailing side, its top just under the total.
        let tall = SpendingChart.Area(x: 0, y: -88, width: 190, height: 68)
        let tallest = placement(barCenter: 12, barTop: 6, keepClear: tall)
        #expect(tallest == SpendingChart.CalloutPlacement(leading: 12 + 8.75 + 4, bottom: -20 + 4 + 66))
        #expect(!tall.overlaps(SpendingChart.Area(x: tallest.leading, y: tallest.bottom - 66, width: 106, height: 66)))
        // As wide as the chart, with a bar at the trailing edge: beside it
        // on the leading side.
        let wide = SpendingChart.Area(x: 0, y: -88, width: 338, height: 68)
        #expect(placement(barCenter: 320, barTop: 6, keepClear: wide)
            == SpendingChart.CalloutPlacement(leading: 320 - 8.75 - 4 - 106, bottom: -20 + 4 + 66))
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

    // The card as measured on an iPhone 16 Pro at the default text size: the
    // plot runs from x 0 to 307 (the value labels start about 5pt further
    // on), its top is the chart's top, and the total's line (its frame,
    // descent included) ends 40pt above the chart. "RWF 100,000" is 255pt
    // wide; the All Time bar of this year spans 241.65 to 295.35.
    private let wideTotal = SpendingChart.Area(x: 0, y: -88, width: 255, height: 48)

    private func measured(
        barCenter: Double = 268.5,
        barWidth: Double = 53.7,
        barTop: Double = 0,
        calloutWidth: Double,
        calloutHeight: Double = 46,
        plotTrailing: Double = 307,
        keepClear: SpendingChart.Area
    ) -> SpendingChart.CalloutPlacement {
        SpendingChart.calloutPlacement(
            barCenter: barCenter,
            barWidth: barWidth,
            barTop: barTop,
            calloutWidth: calloutWidth,
            calloutHeight: calloutHeight,
            plotTrailing: plotTrailing,
            plotTop: 0,
            keepClear: keepClear,
            margin: 2
        )
    }

    @Test func calloutKeepsOffTheValueLabelsUnderAWideTotal() {
        // "RWF 100,000" over its full bar: centred, it would run 20pt past
        // the plot's end, over "100K", so it lines up with the plot's end
        // instead, still covering the whole bar. Resting 6pt above the bar
        // would cover the total, so its top sits 2pt under the total's line
        // and it sinks 8pt into the bar, no deeper than the 8pt corners of
        // an All Time bar.
        let spot = measured(calloutWidth: 117, keepClear: wideTotal)
        #expect(spot == SpendingChart.CalloutPlacement(leading: 190, bottom: 8))
        let frame = SpendingChart.Area(x: spot.leading, y: spot.bottom - 46, width: 117, height: 46)
        #expect(frame.maxX == 307)
        #expect(frame.minY == -38)
        #expect(frame.minX <= 241.65 && frame.maxX >= 295.35)
    }

    @Test func calloutKeepsOffTheValueLabelsAtTheLargestChartText() {
        // xxxLarge, where the chart's text stops growing: wider labels end
        // the plot at 294, and the callout is 154 by 60. Its top still sits
        // 2pt under the total's line, sinking 22pt (less than half its
        // height), so it stays on its bar.
        let total = SpendingChart.Area(x: 0, y: -96, width: 300, height: 56)
        let spot = measured(barCenter: 257.5, barWidth: 51.5, calloutWidth: 154, calloutHeight: 60, plotTrailing: 294, keepClear: total)
        #expect(spot == SpendingChart.CalloutPlacement(leading: 140, bottom: 22))
    }

    @Test func calloutSinksTheSameUnderAnySizeOfTotal() {
        // The total's line always ends 40pt above the chart, however large
        // its text, so the callout under it lands in the same place.
        for height in [48.0, 56, 84] {
            let total = SpendingChart.Area(x: 0, y: -40 - height, width: 300, height: height)
            #expect(measured(calloutWidth: 117, keepClear: total) == SpendingChart.CalloutPlacement(leading: 190, bottom: 8))
        }
    }

    @Test func calloutStaysCentredOverTheLastBarWhenItFits() {
        // "$20.00" fits over the last bar inside the plot, beside a short
        // total: centred and resting 6pt above the bar, as in the recording.
        let total = SpendingChart.Area(x: 0, y: -88, width: 138, height: 48)
        #expect(measured(calloutWidth: 71, keepClear: total) == SpendingChart.CalloutPlacement(leading: 233, bottom: -6))
    }

    /// The callout's height and where the plot ends, at xSmall, the default
    /// text size and xxxLarge (the chart's largest).
    static let textSizes: [(calloutHeight: Double, plotTrailing: Double)] = [(42.5, 309), (46, 307), (60.5, 294)]

    @Test(arguments: textSizes)
    func calloutNeverCoversTheValueLabelsOrTheTotal(_ size: (calloutHeight: Double, plotTrailing: Double)) {
        let height = size.calloutHeight
        // A short total, "RWF 100,000", and one as wide as the card at an
        // accessibility size.
        let totals = [
            SpendingChart.Area(x: 0, y: -88, width: 138, height: 48),
            wideTotal,
            SpendingChart.Area(x: 0, y: -124, width: 338, height: 84),
        ]
        // All Time, Today, This Week, This Year and the months.
        for count in [4, 6, 7, 12, 28, 31] {
            let slot = size.plotTrailing / Double(count)
            let barWidth = slot * 0.7
            for width in [58.0, 117, 195] {
                for total in totals {
                    for index in 0..<count {
                        let center = slot * (Double(index) + 0.5)
                        for barTop in stride(from: 0.0, through: 182, by: 13) {
                            let spot = measured(
                                barCenter: center, barWidth: barWidth, barTop: barTop,
                                calloutWidth: width, calloutHeight: height,
                                plotTrailing: size.plotTrailing, keepClear: total
                            )
                            let frame = SpendingChart.Area(x: spot.leading, y: spot.bottom - height, width: width, height: height)
                            let place = "\(width)pt wide, bar \(index) of \(count), top \(barTop)"
                            // Inside the plot, so never over a value label.
                            #expect(frame.minX >= 0 && frame.maxX <= size.plotTrailing, "\(place)")
                            #expect(!total.grown(by: 2).overlaps(frame), "\(place)")
                            // Above the plot's bottom, so never over a period label.
                            #expect(frame.maxY <= 182, "\(place)")
                            // On its bar, sunk at most half its height, and
                            // covering the whole bar when it is off-centre.
                            #expect(spot.bottom - barTop <= height / 2, "\(place)")
                            if spot.leading != center - width / 2 {
                                #expect(frame.minX <= center - barWidth / 2 && center + barWidth / 2 <= frame.maxX, "\(place)")
                            }
                        }
                    }
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
