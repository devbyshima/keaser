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
    /// What each category took in the period, largest first, for the large
    /// widgets. Empty unless the snapshot is ready.
    public var categories: [CategoryTotal]
    /// The newest expenses in the period (at most `latestLimit`), newest
    /// first, for the large widgets (see `breakdownPlans(extraLarge:)`).
    /// Empty unless the snapshot is ready.
    public var latest: [LatestExpense]

    public init(
        state: State,
        period: Period,
        accountName: String?,
        total: Decimal,
        currencyCode: String,
        categories: [CategoryTotal] = [],
        latest: [LatestExpense] = []
    ) {
        self.state = state
        self.period = period
        self.accountName = accountName
        self.total = total
        self.currencyCode = currencyCode
        self.categories = categories
        self.latest = latest
    }

    /// One line of the category breakdown: a category, the expenses without
    /// one, or everything that did not fit.
    public struct CategoryTotal: Equatable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable {
            case category(UUID)
            /// Expenses with no category, or one that has since been deleted.
            case uncategorized
            /// The categories past the rows a widget has room for.
            case other
        }

        public var kind: Kind
        public var name: String
        /// An SF Symbol name.
        public var symbol: String
        public var amount: Decimal

        public var id: Kind { kind }

        public init(kind: Kind, name: String, symbol: String, amount: Decimal) {
            self.kind = kind
            self.name = name
            self.symbol = symbol
            self.amount = amount
        }

        public static let uncategorizedName = "Uncategorized"
        public static let otherName = "Other"
        public static let otherSymbol = "ellipsis"
    }

    /// An expense as the large widgets list it.
    public struct LatestExpense: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var amount: Decimal
        public var date: Date
        /// Its category's SF Symbol, or the fallback card.
        public var symbol: String

        public init(id: UUID, title: String, amount: Decimal, date: Date, symbol: String) {
            self.id = id
            self.title = title
            self.amount = amount
            self.date = date
            self.symbol = symbol
        }
    }

    /// How many expenses `latest` keeps.
    public static let latestLimit = 6

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

    /// Any amount in the snapshot's currency.
    public func formatted(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: currencyCode)
    }

    /// "No expenses this month.", where the breakdown would be.
    public var emptyText: String {
        switch period {
        case .today: "No expenses today."
        case .thisWeek: "No expenses this week."
        case .thisMonth: "No expenses this month."
        case .thisYear: "No expenses this year."
        case .allTime: "No expenses yet."
        }
    }

    /// The breakdown in at most `maxRows` rows: every category when they
    /// fit, otherwise the largest `maxRows - 1` and one "Other" row that
    /// adds up the rest, so the rows always sum to the total.
    public func categoryRows(maxRows: Int) -> [CategoryTotal] {
        guard maxRows > 0 else { return [] }
        guard categories.count > maxRows else { return categories }
        let shown = categories.prefix(maxRows - 1)
        let rest = categories.dropFirst(maxRows - 1).reduce(Decimal(0)) { $0 + $1.amount }
        let other = CategoryTotal(kind: .other, name: CategoryTotal.otherName, symbol: CategoryTotal.otherSymbol, amount: rest)
        return Array(shown) + [other]
    }

    /// `amount` as a share of the total, from 0 to 1, for a proportional
    /// bar. Zero when nothing was spent.
    public func share(of amount: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return min(max((amount / total).doubleValue, 0), 1)
    }

    /// How many breakdown rows (`categoryRows(maxRows:)`) and latest
    /// expenses a large widget shows under its headline.
    public struct BreakdownPlan: Equatable, Sendable {
        public var categories: Int
        public var latest: Int

        public init(categories: Int, latest: Int) {
            self.categories = categories
            self.latest = latest
        }
    }

    /// The most breakdown rows the large widget has room for.
    public static let largeBreakdownRows = 6

    /// The plans a large widget tries, most first. It shows the first one
    /// that fits, so larger text sizes drop rows instead of cutting one off.
    ///
    /// The extra large portrait widget always lists the latest expenses
    /// under the breakdown. The large widget gives its room to the
    /// breakdown and fills what a short one leaves with the latest
    /// expenses, so a quiet day does not leave its bottom half empty. It
    /// never gives up a breakdown row for an expense. Empty when there is
    /// no breakdown to show.
    public func breakdownPlans(extraLarge: Bool) -> [BreakdownPlan] {
        guard !categories.isEmpty else { return [] }
        if extraLarge {
            return [(5, 5), (5, 4), (5, 3), (4, 3), (4, 2), (3, 2), (3, 1), (2, 1)]
                .map { BreakdownPlan(categories: $0.0, latest: $0.1) }
        }
        let rows = min(categories.count, Self.largeBreakdownRows)
        let filled = stride(from: min(latest.count, 5), through: 1, by: -1)
            .map { BreakdownPlan(categories: rows, latest: $0) }
        let breakdownOnly = stride(from: rows, through: 1, by: -1)
            .map { BreakdownPlan(categories: $0, latest: 0) }
        return filled + breakdownOnly
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
        let interval = period.interval(containing: now, calendar: calendar)
        // A locked widget carries no spending at all, only the lock.
        guard isPro else {
            return SpendingSnapshot(state: .locked, period: period, accountName: account.name, total: 0, currencyCode: preferences.currencyCode)
        }
        let expenses = account.expensesNewestFirst.filter { interval?.holds($0.date) ?? true }
        return SpendingSnapshot(
            state: .ready,
            period: period,
            accountName: account.name,
            total: account.total(in: interval),
            currencyCode: preferences.currencyCode,
            categories: categoryTotals(of: expenses, in: account),
            latest: expenses.prefix(latestLimit).map {
                LatestExpense(id: $0.id, title: $0.title, amount: $0.amount, date: $0.date, symbol: account.symbol(for: $0))
            }
        )
    }

    /// Each category's spending, largest first; equal amounts keep the
    /// account's category order, with Uncategorized after them. Categories
    /// with nothing spent are left out.
    static func categoryTotals(of expenses: [Expense], in account: Account) -> [CategoryTotal] {
        var sums: [UUID: Decimal] = [:]
        var uncategorized = Decimal(0)
        for expense in expenses {
            if let category = account.category(id: expense.categoryID) {
                sums[category.id, default: 0] += expense.amount
            } else {
                uncategorized += expense.amount
            }
        }
        var rows = account.categories.compactMap { category -> CategoryTotal? in
            guard let amount = sums[category.id], amount != 0 else { return nil }
            // A second label with the same id cannot count twice.
            sums[category.id] = nil
            return CategoryTotal(kind: .category(category.id), name: category.name, symbol: category.symbol, amount: amount)
        }
        if uncategorized != 0 {
            rows.append(CategoryTotal(kind: .uncategorized, name: CategoryTotal.uncategorizedName, symbol: ExpenseCategory.fallbackSymbol, amount: uncategorized))
        }
        // Stable, so ties keep the order built above.
        return rows.enumerated()
            .sorted { $0.element.amount != $1.element.amount ? $0.element.amount > $1.element.amount : $0.offset < $1.offset }
            .map(\.element)
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
    /// picker, before any data exists. The categories add up to the total.
    public static func sample(currencyCode: String = "USD", now: Date = .now) -> SpendingSnapshot {
        func money(_ text: String) -> Decimal { Decimal(string: text)! }
        func category(_ name: String, _ symbol: String, _ amount: String) -> CategoryTotal {
            CategoryTotal(kind: .category(UUID()), name: name, symbol: symbol, amount: money(amount))
        }
        func expense(_ title: String, _ symbol: String, _ amount: String, daysAgo: Double) -> LatestExpense {
            LatestExpense(id: UUID(), title: title, amount: money(amount), date: now.addingTimeInterval(-86_400 * daysAgo), symbol: symbol)
        }
        return SpendingSnapshot(
            state: .ready,
            period: .thisMonth,
            accountName: nil,
            total: money("271.37"),
            currencyCode: currencyCode,
            categories: [
                category("Food & Drinks", "fork.knife", "98.40"),
                category("Shopping", "cart.fill", "83.33"),
                category("Transportation", "car.fill", "42.50"),
                category("Entertainment", "gamecontroller.fill", "31.25"),
                category("Health", "heart.fill", "15.89"),
            ],
            latest: [
                expense("Coffee", "fork.knife", "6.74", daysAgo: 0),
                expense("New shoes", "cart.fill", "83.33", daysAgo: 1),
                expense("Taxi", "car.fill", "18.20", daysAgo: 2),
                expense("Movie tickets", "gamecontroller.fill", "31.25", daysAgo: 3),
                expense("Groceries", "fork.knife", "54.10", daysAgo: 4),
            ]
        )
    }
}
