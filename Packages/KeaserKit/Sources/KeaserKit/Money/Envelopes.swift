import Foundation

/// One envelope of the split rule for a month: its share of the month's
/// income, and what went out of it. All in the display currency.
public struct Envelope: Hashable, Sendable {
    /// Its percentage of the income (`SplitRule`).
    public var percent: Int
    /// The month's income times `percent`, rounded to the display
    /// currency's places. Nil when the month has no income: the envelope
    /// then shows spending only.
    public var budget: Decimal?
    /// What went out of it this month; for Savings, what was saved.
    public var spent: Decimal

    public init(percent: Int, budget: Decimal?, spent: Decimal) {
        self.percent = percent
        self.budget = budget
        self.spent = spent
    }

    /// `budget - spent`, below 0 when overspent; nil without a budget.
    /// Nothing carries over to the next month.
    public var left: Decimal? {
        budget.map { $0 - spent }
    }
}

/// The split rule's three envelopes for one calendar month.
public struct MonthEnvelopes: Hashable, Sendable {
    /// The month, half-open (`DateInterval.holds`).
    public var month: DateInterval
    /// The month's income in the display currency.
    public var income: Decimal
    /// Savings: what the savings transfers moved this month.
    public var savings: Envelope
    /// Spending in categories whose role is Expenses, or with no category.
    public var expenses: Envelope
    /// Spending in categories whose role is Free Money.
    public var freeMoney: Envelope
    /// Incomes, expenses and savings transfers of the month that could not
    /// be converted: left out, never guessed.
    public var unconverted: Int

    public init(month: DateInterval, income: Decimal, savings: Envelope, expenses: Envelope, freeMoney: Envelope, unconverted: Int) {
        self.month = month
        self.income = income
        self.savings = savings
        self.expenses = expenses
        self.freeMoney = freeMoney
        self.unconverted = unconverted
    }

    /// The envelopes of the calendar month containing `containing`, with
    /// the account's split rule percentages (whether the rule is on is for
    /// the caller to decide):
    /// - Income: the incomes dated in the month.
    /// - Expenses: the month's expenses in a category whose role is
    ///   Expenses, with no category, or with one the account no longer has.
    ///   A role from a later version counts here too, as Expenses is the
    ///   role a category has until it is changed.
    /// - Free Money: the month's expenses in a category whose role is Free
    ///   Money.
    /// - Savings: the `.savings` transfers dated in the month, by what left
    ///   the income's wallet. Other transfers into the savings wallet are
    ///   not counted.
    ///
    /// Each entry is converted to the display currency at its saved rate
    /// (`CurrencyConverter`). Pass `Preferences.calendar`.
    public static func envelopes(
        for account: Account,
        month containing: Date,
        calendar: Calendar,
        display: String,
        converter: CurrencyConverter
    ) -> MonthEnvelopes {
        let month = calendar.dateInterval(of: .month, for: containing) ?? DateInterval(start: containing, duration: 0)
        var unconverted = 0
        func inDisplay(_ amount: Decimal, from currency: String, saved: ExchangeRate?) -> Decimal {
            if let converted = converter.convert(amount, from: currency, to: display, saved: saved) { return converted }
            unconverted += 1
            return 0
        }

        var income: Decimal = 0
        for entry in account.incomes where month.holds(entry.date) {
            income += inDisplay(entry.amount, from: account.effectiveCurrency(of: entry, display: display), saved: entry.rate)
        }
        var expensesSpent: Decimal = 0
        var freeMoneySpent: Decimal = 0
        for expense in account.expenses where month.holds(expense.date) {
            let amount = inDisplay(expense.amount, from: account.effectiveCurrency(of: expense, display: display), saved: expense.rate)
            if account.category(id: expense.categoryID)?.role == .freeMoney {
                freeMoneySpent += amount
            } else {
                expensesSpent += amount
            }
        }
        var saved: Decimal = 0
        for transfer in account.transfers where transfer.kind == .savings && month.holds(transfer.date) {
            saved += inDisplay(transfer.amountOut, from: account.effectiveCurrencyOut(of: transfer, display: display), saved: transfer.rate)
        }

        // No income (or none that converts): no budgets, spending only.
        func envelope(_ percent: Int, spent: Decimal) -> Envelope {
            let budget = income > 0 ? CurrencyMath.rounded(income * Decimal(percent) / 100, currencyCode: display) : nil
            return Envelope(percent: percent, budget: budget, spent: spent)
        }
        let rule = account.splitRule
        return MonthEnvelopes(
            month: month,
            income: income,
            savings: envelope(rule.savingsPercent, spent: saved),
            expenses: envelope(rule.expensesPercent, spent: expensesSpent),
            freeMoney: envelope(rule.freeMoneyPercent, spent: freeMoneySpent),
            unconverted: unconverted
        )
    }
}
