import Foundation

/// Everything the Spending widget shows, computed from the database the app
/// wrote. The widget extension only lays it out.
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
    /// illustration draws.
    public var caption: String { period.title }

    /// "Spent This Month" above the total on the medium widget.
    public var spentCaption: String { "Spent \(period.title)" }

    public var formattedTotal: String { MoneyFormat.string(total, currencyCode: currencyCode) }

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
