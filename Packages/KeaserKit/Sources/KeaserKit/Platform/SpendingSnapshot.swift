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

    public var state: State
    public var period: Period
    public var accountName: String?
    public var total: Decimal
    public var currencyCode: String

    public init(state: State, period: Period, accountName: String?, total: Decimal, currencyCode: String) {
        self.state = state
        self.period = period
        self.accountName = accountName
        self.total = total
        self.currencyCode = currencyCode
    }

    /// "This Month" above the total on the small and lock screen widgets.
    public var caption: String { period.title }

    /// "Spent This Month" above the total on the medium widget.
    public var spentCaption: String { "Spent \(period.title)" }

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
            return SpendingSnapshot(state: .noAccount, period: period, accountName: nil, total: 0, currencyCode: preferences.currencyCode)
        }
        let isPro = ProEntitlement.isPro(preferences, now: now)
        return SpendingSnapshot(
            state: isPro ? .ready : .locked,
            period: period,
            accountName: account.name,
            total: account.total(in: period.interval(containing: now, calendar: calendar)),
            currencyCode: preferences.currencyCode
        )
    }

    /// When the widget must redraw on its own: the next midnight (totals move
    /// to a new day, week, month or year) or the moment the Pro pass or a
    /// subscription runs out, whichever comes first. Edits reload the widget
    /// from the app.
    public static func nextRefresh(after now: Date, preferences: Preferences, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? preferences.calendar
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        guard let change = ProEntitlement.nextChange(after: now, preferences: preferences, calendar: calendar) else { return midnight }
        return min(midnight, change)
    }

    /// A believable total for the onboarding illustration, before any data
    /// exists.
    public static func sample(currencyCode: String = "USD") -> SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: .thisMonth, accountName: nil, total: Decimal(string: "271.37")!, currencyCode: currencyCode)
    }
}
