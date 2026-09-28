import Foundation

/// Everything the Spending widget shows, computed from the database the app
/// wrote, and the texts each size shows it with. The widget extension only
/// lays it out.
public struct SpendingSnapshot: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case ready
        /// Nothing to show until the user creates an account.
        case noAccount
        /// Widgets are a Pro feature and the pass is over, with or without
        /// an account.
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

    /// "This Month" above the total on the small widget the onboarding
    /// illustration draws (the recording's; the real small widget shows
    /// `spentCaption` like every other size).
    public var caption: String { period.title }

    /// "Spent This Month" above the total, on every home screen widget and
    /// the rectangular lock screen one.
    public var spentCaption: String { "Spent \(period.title)" }

    public var formattedTotal: String { MoneyFormat.string(total, currencyCode: currencyCode) }

    /// One word above the total on the circular lock screen widget: "Month".
    public var shortCaption: String {
        switch period {
        case .today: "Today"
        case .thisWeek: "Week"
        case .thisMonth: "Month"
        case .thisYear: "Year"
        case .allTime: "All Time"
        }
    }

    /// The total without cents, abbreviated from a thousand ("$148",
    /// "$1.4K", "RWF 12M"), for the circular lock screen widget.
    public func compactTotal(locale: Locale = .current) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        // Anything that would round up to a thousand is abbreviated too, so
        // "$1,000" never takes the place of "$1K".
        if abs(total) < Decimal(string: "999.5")! {
            return total.formatted(style.precision(.fractionLength(0)))
        }
        return total.formatted(style.notation(.compactName).precision(.significantDigits(1...2)))
    }

    /// "Spent This Month: $271.37", for the inline lock screen widget.
    public func inlineText(locale: Locale = .current) -> String {
        "\(spentCaption): \(MoneyFormat.string(total, currencyCode: currencyCode, locale: locale))"
    }

    /// "Month: $271", for the inline lock screen widget when the full line
    /// does not fit.
    public func shortInlineText(locale: Locale = .current) -> String {
        "\(shortCaption): \(compactTotal(locale: locale))"
    }

    /// The snapshot for `accountID` (or the selected account when it is nil or
    /// no longer exists). Pass `calendar` only in tests; otherwise the user's
    /// calendar, with their first weekday, is used.
    ///
    /// Once Pro has run out the widget is locked even without an account,
    /// since adding one would not bring it back; before the pass has
    /// started (a first run) it asks for an account instead.
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
        let isPro = ProEntitlement.isPro(preferences, now: now)
        guard let account else {
            let hasLapsed = !isPro && (preferences.trialStartDate != nil || preferences.hasProPurchase)
            return SpendingSnapshot(state: hasLapsed ? .locked : .noAccount, period: period, accountName: nil, total: 0, currencyCode: preferences.currencyCode)
        }
        // A locked widget carries no spending at all, only the lock.
        guard isPro else {
            return SpendingSnapshot(state: .locked, period: period, accountName: account.name, total: 0, currencyCode: preferences.currencyCode)
        }
        let interval = period.interval(containing: now, calendar: calendar)
        return SpendingSnapshot(state: .ready, period: period, accountName: account.name, total: account.total(in: interval), currencyCode: preferences.currencyCode)
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

    /// A believable month for the onboarding illustration and the widget
    /// picker, before any data exists.
    public static func sample(currencyCode: String = "USD") -> SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: .thisMonth, accountName: nil, total: Decimal(string: "271.37")!, currencyCode: currencyCode)
    }
}
