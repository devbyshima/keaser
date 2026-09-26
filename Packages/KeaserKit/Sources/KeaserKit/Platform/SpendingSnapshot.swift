import Foundation

/// Everything the Spending widget shows, computed from the database the app
/// wrote. The widget extension only lays it out.
public struct SpendingSnapshot: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case ready
        /// Nothing to show until the user creates an account.
        case noAccount
        /// Widgets are a Pro feature and the pass is over.
        case locked
    }

    /// One bar of the medium widget's chart.
    public struct Bar: Identifiable, Equatable, Sendable {
        public var id: Int
        /// "M", "12", "J": short enough to sit under a thin bar.
        public var label: String
        public var amount: Decimal
        /// The bar containing today.
        public var isCurrent: Bool

        public init(id: Int, label: String, amount: Decimal, isCurrent: Bool) {
            self.id = id
            self.label = label
            self.amount = amount
            self.isCurrent = isCurrent
        }
    }

    public var state: State
    public var period: Period
    public var accountName: String?
    public var total: Decimal
    public var currencyCode: String
    public var bars: [Bar]

    public init(state: State, period: Period, accountName: String?, total: Decimal, currencyCode: String, bars: [Bar]) {
        self.state = state
        self.period = period
        self.accountName = accountName
        self.total = total
        self.currencyCode = currencyCode
        self.bars = bars
    }

    /// "This Month" above the total.
    public var caption: String { period.title }

    public var formattedTotal: String { MoneyFormat.string(total, currencyCode: currencyCode) }

    /// One word for the circular lock screen widget: "MONTH".
    public var shortCaption: String {
        switch period {
        case .today: "TODAY"
        case .thisWeek: "WEEK"
        case .thisMonth: "MONTH"
        case .thisYear: "YEAR"
        case .allTime: "ALL"
        }
    }

    /// The total without cents, abbreviated past a thousand ("$271",
    /// "$1.25K"), for the circular lock screen widget.
    public func compactTotal(locale: Locale = .current) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        if abs(total.doubleValue) < 1000 {
            return total.formatted(style.precision(.fractionLength(0)))
        }
        return total.formatted(style.notation(.compactName).precision(.significantDigits(2...3)))
    }

    /// "This Month: $271.37", for the inline lock screen widget.
    public var inlineText: String { "\(caption): \(formattedTotal)" }

    /// The snapshot for `accountID` (or the selected account when it is nil or
    /// no longer exists). Pass `calendar` only in tests; otherwise the user's
    /// calendar, with their first weekday, is used.
    public static func make(
        database: Database,
        accountID: UUID?,
        period: Period,
        now: Date,
        calendar: Calendar? = nil
    ) -> SpendingSnapshot {
        let preferences = database.preferences
        let calendar = calendar ?? preferences.calendar
        let account = accountID.flatMap { id in database.accounts.first { $0.id == id } } ?? database.selectedAccount
        guard let account else {
            return SpendingSnapshot(state: .noAccount, period: period, accountName: nil, total: 0, currencyCode: preferences.currencyCode, bars: [])
        }
        let isPro = ProEntitlement.isPro(preferences, now: now)
        return SpendingSnapshot(
            state: isPro ? .ready : .locked,
            period: period,
            accountName: account.name,
            total: account.total(in: period.interval(containing: now, calendar: calendar)),
            currencyCode: preferences.currencyCode,
            bars: bars(for: account, period: period, now: now, calendar: calendar)
        )
    }

    /// When the widget must redraw on its own: the next midnight (totals move
    /// to a new day, week, month or year) or the moment the Pro pass runs out,
    /// whichever comes first. Edits reload the widget from the app.
    public static func nextRefresh(after now: Date, preferences: Preferences, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? preferences.calendar
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        guard !preferences.hasProPurchase,
              let start = preferences.trialStartDate,
              let passEnd = calendar.date(byAdding: .day, value: ProEntitlement.trialDays, to: start),
              passEnd > now
        else { return midnight }
        return min(midnight, passEnd)
    }

    /// A believable total for the onboarding illustration, before any data
    /// exists.
    public static func sample(currencyCode: String = "USD") -> SpendingSnapshot {
        let amounts: [Decimal] = [12, 4.5, 0, 38.9, 87.23, 9.75, 42, 0, 21.4, 16.99, 0, 38.6]
        let bars = amounts.enumerated().map { Bar(id: $0.offset, label: "", amount: $0.element, isCurrent: $0.offset == amounts.count - 1) }
        return SpendingSnapshot(state: .ready, period: .thisMonth, accountName: nil, total: Decimal(string: "271.37")!, currencyCode: currencyCode, bars: bars)
    }

    // MARK: Bars

    /// The chart under the total: the days of the week or month, the months of
    /// the year. "Today" shows the last seven days so a single bar is never
    /// the whole chart; "All Time" shows the last five years.
    static func bars(for account: Account, period: Period, now: Date, calendar: Calendar) -> [Bar] {
        let today = calendar.startOfDay(for: now)
        switch period {
        case .today:
            let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            return dayBars(days, account: account, today: today, calendar: calendar, label: weekdayLabel)
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
            return dayBars(days, account: account, today: today, calendar: calendar, label: weekdayLabel)
        case .thisMonth:
            guard let month = calendar.dateInterval(of: .month, for: now),
                  let count = calendar.range(of: .day, in: .month, for: now)?.count
            else { return [] }
            let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month.start) }
            return dayBars(days, account: account, today: today, calendar: calendar) { date, calendar in
                String(calendar.component(.day, from: date))
            }
        case .thisYear:
            guard let year = calendar.dateInterval(of: .year, for: now) else { return [] }
            let months = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: year.start) }
            return months.enumerated().compactMap { index, start in
                guard let interval = calendar.dateInterval(of: .month, for: start) else { return nil }
                let symbols = calendar.veryShortMonthSymbols
                return Bar(
                    id: index,
                    label: symbols[calendar.component(.month, from: start) - 1],
                    amount: account.total(in: interval),
                    isCurrent: interval.holds(now)
                )
            }
        case .allTime:
            guard let thisYear = calendar.dateInterval(of: .year, for: now) else { return [] }
            let years = (0..<5).reversed().compactMap { calendar.date(byAdding: .year, value: -$0, to: thisYear.start) }
            return years.enumerated().compactMap { index, start in
                guard let interval = calendar.dateInterval(of: .year, for: start) else { return nil }
                return Bar(id: index, label: String(calendar.component(.year, from: start) % 100), amount: account.total(in: interval), isCurrent: interval.holds(now))
            }
        }
    }

    private static func dayBars(
        _ days: [Date],
        account: Account,
        today: Date,
        calendar: Calendar,
        label: (Date, Calendar) -> String
    ) -> [Bar] {
        days.enumerated().compactMap { index, day in
            guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            return Bar(id: index, label: label(day, calendar), amount: account.total(in: interval), isCurrent: day == today)
        }
    }

    private static func weekdayLabel(_ date: Date, _ calendar: Calendar) -> String {
        calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}
