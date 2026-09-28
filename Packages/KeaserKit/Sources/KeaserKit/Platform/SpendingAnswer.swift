import Foundation

/// "How much did I spend": a spending question from Siri or Shortcuts. It is
/// answered like Home's total (the same period, filters, Pro rules and week
/// start), so the two never disagree.
public struct SpendingQuestion: Hashable, Sendable {
    public var period: Period
    /// Nil asks about the account selected in Keaser.
    public var accountID: UUID?
    /// A category picked in Shortcuts or by Siri. It may belong to another
    /// account, so it is matched by name in the account asked about, as the
    /// Add Expense shortcut does.
    public var category: ShortcutFlow.Label?
    /// A payment method, matched like `category`.
    public var paymentMethod: ShortcutFlow.Label?

    public init(period: Period, accountID: UUID? = nil, category: ShortcutFlow.Label? = nil, paymentMethod: ShortcutFlow.Label? = nil) {
        self.period = period
        self.accountID = accountID
        self.category = category
        self.paymentMethod = paymentMethod
    }

    /// The Pro feature this question needs, as Home gates it: This Year and
    /// All Time are Long-term Insights, a category or payment method filter
    /// is More Filters. Nil when it needs none.
    public var proFeature: ProFeature? {
        if period.isLongTerm { return .longTermInsights }
        if category != nil || paymentMethod != nil { return .moreFilters }
        return nil
    }

    /// The answer, or why there is none. Pass `calendar` only in tests;
    /// otherwise the user's calendar, with their first weekday, is used.
    public func answer(in database: Database, isPro: Bool, now: Date, calendar: Calendar? = nil) -> SpendingOutcome {
        guard !database.accounts.isEmpty else { return .noAccount }
        let account: Account
        if let accountID {
            guard let chosen = database.accounts.first(where: { $0.id == accountID }) else { return .accountGone }
            account = chosen
        } else {
            guard let selected = database.selectedAccount else { return .noAccount }
            account = selected
        }
        if let feature = proFeature, !isPro { return .needsPro(feature) }

        var categoryName: String?
        var categoryID: UUID?
        if let category {
            guard let match = QuickLog.category(id: category.id, name: category.name, in: account) else {
                return .missingCategory(name: category.name, account: account.name)
            }
            categoryID = match.id
            categoryName = match.name
        }
        var paymentMethodName: String?
        var paymentMethodID: UUID?
        if let paymentMethod {
            guard let match = QuickLog.paymentMethod(id: paymentMethod.id, name: paymentMethod.name, in: account) else {
                return .missingPaymentMethod(name: paymentMethod.name, account: account.name)
            }
            paymentMethodID = match.id
            paymentMethodName = match.name
        }

        let filter = ExpenseQuery.Filter(period: period, categoryID: categoryID, paymentMethodID: paymentMethodID)
        let expenses = ExpenseQuery.apply(filter, to: account.expenses, now: now, calendar: calendar ?? database.preferences.calendar)
        // Newest first, so of two equal amounts the newer one is named.
        let largest = expenses.max { $0.amount < $1.amount }
        return .answer(SpendingAnswer(
            period: period,
            accountName: account.name,
            categoryName: categoryName,
            paymentMethodName: paymentMethodName,
            total: ExpenseQuery.total(of: expenses),
            currencyCode: database.preferences.currencyCode,
            count: expenses.count,
            largest: largest.map { SpendingAnswer.Largest(title: $0.title, amount: $0.amount) }
        ))
    }
}

/// What a spending question comes to.
public enum SpendingOutcome: Hashable, Sendable {
    case answer(SpendingAnswer)
    /// There is no account yet.
    case noAccount
    /// The account asked about has been deleted.
    case accountGone
    /// The account asked about has no category with this name.
    case missingCategory(name: String, account: String)
    /// The account asked about has no payment method with this name.
    case missingPaymentMethod(name: String, account: String)
    /// The question needs Keaser Pro, which is not active.
    case needsPro(ProFeature)

    /// What is said instead of an answer; nil for an answer. A locked Pro
    /// feature says so rather than answering with a total the app would not
    /// show.
    public var refusal: String? {
        switch self {
        case .answer: nil
        case .noAccount: "Create an account in Keaser first."
        case .accountGone: "That account is no longer in Keaser."
        case .missingCategory(let name, let account): "\(account) has no category named \(name)."
        case .missingPaymentMethod(let name, let account): "\(account) has no payment method named \(name)."
        case .needsPro(.longTermInsights): "Spending for This Year and All Time is part of Keaser Pro. You can upgrade in Keaser's Settings."
        case .needsPro(.moreFilters): "Spending by category or payment method is part of Keaser Pro. You can upgrade in Keaser's Settings."
        case .needsPro(let feature): "\(feature.title) is part of Keaser Pro. You can upgrade in Keaser's Settings."
        }
    }
}

/// A spending total and how it is put into words.
public struct SpendingAnswer: Hashable, Sendable {
    /// The largest expense counted, for the spoken answer.
    public struct Largest: Hashable, Sendable {
        public let title: String
        public let amount: Decimal

        public init(title: String, amount: Decimal) {
            self.title = title
            self.amount = amount
        }
    }

    public let period: Period
    public let accountName: String
    /// The category it is narrowed to, as the account names it.
    public let categoryName: String?
    /// The payment method it is narrowed to, as the account names it.
    public let paymentMethodName: String?
    public let total: Decimal
    public let currencyCode: String
    /// How many expenses the total adds up.
    public let count: Int
    public let largest: Largest?

    public init(
        period: Period,
        accountName: String,
        categoryName: String? = nil,
        paymentMethodName: String? = nil,
        total: Decimal,
        currencyCode: String,
        count: Int,
        largest: Largest? = nil
    ) {
        self.period = period
        self.accountName = accountName
        self.categoryName = categoryName
        self.paymentMethodName = paymentMethodName
        self.total = total
        self.currencyCode = currencyCode
        self.count = count
        self.largest = largest
    }

    /// Shown above the snippet: "You spent $148.13 this week in Personal."
    /// Narrowed: "You spent $12.00 on Food & Drinks with Cash today in
    /// Personal." All time: "You've spent $1,204.50 in Personal altogether."
    /// Nothing: "You haven't spent anything this week in Personal."
    public func sentence(locale: Locale = .current) -> String {
        let labels = [categoryName.map { "on \($0)" }, paymentMethodName.map { "with \($0)" }]
            .compactMap { $0 }
            .map { " " + $0 }
            .joined()
        let amount = MoneyFormat.string(total, currencyCode: currencyCode, locale: locale)
        switch (count > 0, period.spokenPhrase) {
        case (true, let phrase?): return "You spent \(amount)\(labels) \(phrase) in \(accountName)."
        case (true, nil): return "You've spent \(amount)\(labels) in \(accountName) altogether."
        case (false, let phrase?): return "You haven't spent anything\(labels) \(phrase) in \(accountName)."
        case (false, nil): return "You haven't spent anything\(labels) in \(accountName) yet."
        }
    }

    /// Said when nothing is shown (Siri without the screen): the sentence,
    /// then how many expenses it is and the largest, so it stands on its
    /// own. "You spent $148.13 this week in Personal. That's 12 expenses.
    /// The largest was $45.00 for Dinner."
    public func spokenSentence(locale: Locale = .current) -> String {
        var text = sentence(locale: locale)
        guard count > 0 else { return text }
        text += count == 1 ? " That's 1 expense." : " That's \(count) expenses."
        if count > 1, let largest {
            text += " The largest was \(MoneyFormat.string(largest.amount, currencyCode: currencyCode, locale: locale)) for \(largest.title)."
        }
        return text
    }

    /// The total as the medium Spending widget draws it: "Spent This Week"
    /// over the amount.
    public var snapshot: SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: period, accountName: accountName, total: total, currencyCode: currencyCode)
    }
}

extension Period {
    /// "this week", as said after an amount; nil for all time, which is
    /// phrased differently.
    var spokenPhrase: String? {
        switch self {
        case .today: "today"
        case .thisWeek: "this week"
        case .thisMonth: "this month"
        case .thisYear: "this year"
        case .allTime: nil
        }
    }
}
