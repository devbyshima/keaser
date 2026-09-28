import Foundation

/// An expense as Siri, Shortcuts and Spotlight see it: the expense itself
/// plus the names of the account, category and payment method it is filed
/// under, which live on the account rather than on the expense.
public struct ExpenseSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let accountID: UUID
    public let accountName: String
    public let title: String
    public let amount: Decimal
    public let currencyCode: String
    /// The day the money was spent.
    public let date: Date
    public let createdAt: Date
    public let categoryName: String?
    public let paymentMethodName: String?
    /// The category's SF Symbol, or the card an uncategorised expense shows.
    public let symbol: String

    public init(_ expense: Expense, in account: Account, currencyCode: String) {
        id = expense.id
        accountID = account.id
        accountName = account.name
        title = expense.title
        amount = expense.amount
        self.currencyCode = currencyCode
        date = expense.date
        createdAt = expense.createdAt
        categoryName = account.category(id: expense.categoryID)?.name
        paymentMethodName = account.paymentMethod(id: expense.paymentMethodID)?.name
        symbol = account.symbol(for: expense)
    }

    /// "$20.00 · Sep 27, 2026": the amount and the day, as Home's rows show
    /// them. Under the title wherever the system lists the expense.
    public func subtitle(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let amountText = MoneyFormat.string(amount, currencyCode: currencyCode, locale: locale)
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(locale)
        style.timeZone = timeZone
        return "\(amountText) · \(date.formatted(style))"
    }

    /// Other words the expense is found by: its category, payment method
    /// and account.
    public var keywords: [String] {
        [categoryName, paymentMethodName, accountName].compactMap { name in
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return name
        }
    }
}

/// The lookups behind the App Intents entity queries. Everything searches
/// every account, since a saved shortcut, a Spotlight result or something
/// Siri remembers keeps its ID after the user switches accounts.
public enum EntityCatalog {
    /// How many expenses a picker suggests before anything is typed.
    public static let suggestionLimit = 20
    /// How many expenses a typed search returns.
    public static let matchLimit = 50

    /// Every expense in every account, newest first (by day, then by
    /// creation time, as Home orders them).
    public static func allExpenses(in database: Database) -> [ExpenseSummary] {
        let currencyCode = database.preferences.currencyCode
        return database.accounts
            .flatMap { account in account.expenses.map { ExpenseSummary($0, in: account, currencyCode: currencyCode) } }
            .sorted(by: isNewer)
    }

    /// The expenses with these IDs, from any account, in the order asked
    /// for. IDs that no longer exist are left out.
    public static func expenses(withIDs ids: [UUID], in database: Database) -> [ExpenseSummary] {
        let currencyCode = database.preferences.currencyCode
        var found: [UUID: ExpenseSummary] = [:]
        let wanted = Set(ids)
        for account in database.accounts {
            for expense in account.expenses where wanted.contains(expense.id) {
                found[expense.id] = ExpenseSummary(expense, in: account, currencyCode: currencyCode)
            }
        }
        var seen = Set<UUID>()
        return ids.compactMap { id in seen.insert(id).inserted ? found[id] : nil }
    }

    /// The newest expenses across every account.
    public static func recentExpenses(in database: Database, limit: Int = suggestionLimit) -> [ExpenseSummary] {
        Array(allExpenses(in: database).prefix(max(0, limit)))
    }

    /// Expenses whose title contains `text`, ignoring case, accents and
    /// surrounding spaces, newest first. Nothing for empty text.
    public static func expenses(matching text: String, in database: Database, limit: Int = matchLimit) -> [ExpenseSummary] {
        let query = ExpenseQuery.normalized(text)
        guard !query.isEmpty else { return [] }
        let matches = allExpenses(in: database).filter { ExpenseQuery.normalized($0.title).contains(query) }
        return Array(matches.prefix(max(0, limit)))
    }

    /// The account an expense is filed in.
    public static func account(containingExpense id: UUID, in database: Database) -> Account? {
        database.accounts.first { account in account.expenses.contains { $0.id == id } }
    }

    /// Accounts whose name contains `text`, in the user's order.
    public static func accounts(matching text: String, in database: Database) -> [Account] {
        let query = ExpenseQuery.normalized(text)
        guard !query.isEmpty else { return [] }
        return database.accounts.filter { ExpenseQuery.normalized($0.name).contains(query) }
    }

    /// Categories whose name contains `text`: the selected account's, in
    /// its order. Only when it has none are the other accounts searched,
    /// one category per name, so "Food" never offers the same name twice.
    public static func categories(matching text: String, in database: Database) -> [ExpenseCategory] {
        labels(matching: text, in: database, of: \.categories, name: \.name)
    }

    /// Payment methods whose name contains `text`, searched like
    /// `categories(matching:in:)`.
    public static func paymentMethods(matching text: String, in database: Database) -> [PaymentMethod] {
        labels(matching: text, in: database, of: \.paymentMethods, name: \.name)
    }

    private static func labels<Label>(
        matching text: String,
        in database: Database,
        of list: KeyPath<Account, [Label]>,
        name: KeyPath<Label, String>
    ) -> [Label] {
        let query = ExpenseQuery.normalized(text)
        guard !query.isEmpty else { return [] }
        let matches: (Label) -> Bool = { ExpenseQuery.normalized($0[keyPath: name]).contains(query) }
        let selected = database.selectedAccount
        if let selected {
            let own = selected[keyPath: list].filter(matches)
            if !own.isEmpty { return own }
        }
        var names = Set<String>()
        return database.accounts
            .filter { $0.id != selected?.id }
            .flatMap { $0[keyPath: list] }
            .filter { matches($0) && names.insert(ExpenseQuery.normalized($0[keyPath: name])).inserted }
    }

    private static func isNewer(_ a: ExpenseSummary, than b: ExpenseSummary) -> Bool {
        (a.date, a.createdAt) > (b.date, b.createdAt)
    }
}
