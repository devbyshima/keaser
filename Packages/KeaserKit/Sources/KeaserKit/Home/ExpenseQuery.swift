import Foundation

/// Which expenses the home screen shows: the period, category and payment
/// method filters from the filter menu, plus the search text.
public enum ExpenseQuery {
    public struct Filter: Hashable, Sendable {
        public var period: Period
        /// Nil means "All".
        public var categoryID: UUID?
        /// Nil means "All".
        public var paymentMethodID: UUID?
        public var searchText: String

        public init(period: Period, categoryID: UUID? = nil, paymentMethodID: UUID? = nil, searchText: String = "") {
            self.period = period
            self.categoryID = categoryID
            self.paymentMethodID = paymentMethodID
            self.searchText = searchText
        }

        /// The filter a freshly selected account starts with. Long-term
        /// periods are Pro, so everyone else starts on the current month.
        public static func initial(isPro: Bool) -> Filter {
            Filter(period: isPro ? .allTime : .thisMonth)
        }

        /// This filter without Pro: This Year and All Time fall back to This
        /// Month, and the category and payment filters go back to All. The
        /// search stays.
        public var withoutPro: Filter {
            var filter = self
            if filter.period.isLongTerm { filter.period = Filter.initial(isPro: false).period }
            filter.categoryID = nil
            filter.paymentMethodID = nil
            return filter
        }

        /// True when a category or payment method narrows the list, so the
        /// filter button can show that something is hidden.
        public var narrowsByLabel: Bool { categoryID != nil || paymentMethodID != nil }

        public var isSearching: Bool { !ExpenseQuery.normalized(searchText).isEmpty }
    }

    /// The matching expenses, newest first (by day, then creation time).
    public static func apply(
        _ filter: Filter,
        to expenses: [Expense],
        now: Date,
        calendar: Calendar
    ) -> [Expense] {
        let interval = filter.period.interval(containing: now, calendar: calendar)
        let query = normalized(filter.searchText)
        return expenses
            .filter { expense in
                if let interval, !interval.holds(expense.date) { return false }
                if let id = filter.categoryID, expense.categoryID != id { return false }
                if let id = filter.paymentMethodID, expense.paymentMethodID != id { return false }
                if !query.isEmpty, !normalized(expense.title).contains(query) { return false }
                return true
            }
            .sorted(by: isNewer)
    }

    /// What the search screen shows.
    public enum SearchResult: Hashable, Sendable {
        /// Nothing typed yet: "Search Expenses".
        case prompt
        /// Typed text that matches nothing: "No Results".
        case noMatches
        /// The matching expenses, newest first.
        case matches([Expense])
    }

    /// Searches for `text` among the expenses `filter` lets Home show (its
    /// period, category and payment method), so a search never reaches
    /// past what the current plan can see. Any search text already in
    /// `filter` is replaced by `text`.
    public static func search(
        _ text: String,
        filter: Filter,
        in expenses: [Expense],
        now: Date,
        calendar: Calendar
    ) -> SearchResult {
        var filter = filter
        filter.searchText = text
        guard filter.isSearching else { return .prompt }
        let found = apply(filter, to: expenses, now: now, calendar: calendar)
        return found.isEmpty ? .noMatches : .matches(found)
    }

    public static func total(of expenses: [Expense]) -> Decimal {
        expenses.reduce(into: Decimal(0)) { $0 += $1.amount }
    }

    /// Newest first: later day wins, then later creation time. Matches
    /// `Account.expensesNewestFirst`.
    public static func isNewer(_ a: Expense, than b: Expense) -> Bool {
        (a.date, a.createdAt) > (b.date, b.createdAt)
    }

    /// Case and diacritic insensitive form used for every title comparison,
    /// so "cafe" finds "Café".
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Filter menu order: alphabetical, the way Finder sorts names.
    public static func alphabetical(_ categories: [ExpenseCategory]) -> [ExpenseCategory] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func alphabetical(_ methods: [PaymentMethod]) -> [PaymentMethod] {
        methods.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
