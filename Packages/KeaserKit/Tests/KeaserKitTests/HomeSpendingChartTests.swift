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

}
