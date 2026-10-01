import Foundation
import Testing
@testable import KeaserKit

/// The split rule's envelopes for a month (`MonthEnvelopes`): the month's
/// income times each percentage, less that month's spending in each
/// envelope's categories, and Savings' progress from the savings transfers.
struct MoneyEnvelopeTests {
    static func calendar(firstWeekday: Int = 2, zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = firstWeekday
        return c
    }

    /// A moment of 2026 in UTC.
    private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Self.calendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// Expenses.
    private let food = ExpenseCategory(name: "Food & Drinks", symbol: "fork.knife")
    /// Free Money.
    private let shopping = ExpenseCategory(name: "Shopping", symbol: "cart.fill")
    /// Added by the person: Expenses until changed.
    private let rent = ExpenseCategory(name: "Rent", symbol: "house.fill")
    /// A role from a later version.
    private let investments = ExpenseCategory(name: "Investments", symbol: "chart.line.uptrend.xyaxis", role: CategoryRole("investments"))

    private let cash = PaymentMethod(name: "Cash", symbol: "banknote.fill")
    private let savings = PaymentMethod(name: "Savings", symbol: "banknote.fill", kind: .bank, isSavings: true)
    private let dollars = PaymentMethod(name: "Dollars", symbol: "dollarsign", kind: .bank, currencyCode: "USD")

    /// Savings 20%, Expenses 50%, Free Money 30%.
    private func account(
        expenses: [Expense] = [],
        incomes: [Income] = [],
        transfers: [Transfer] = [],
        rule: SplitRule? = nil
    ) -> Account {
        Account(
            name: "Personal", categories: [food, shopping, rent, investments], paymentMethods: [cash, savings, dollars],
            expenses: expenses, incomes: incomes, transfers: transfers,
            splitRule: rule ?? SplitRule(isEnabled: true, savingsWalletID: savings.id)
        )
    }

    private func envelopes(
        _ account: Account, month: Date, calendar: Calendar? = nil, display: String = "RWF", rates: ExchangeRates? = nil
    ) -> MonthEnvelopes {
        MonthEnvelopes.envelopes(
            for: account, month: month, calendar: calendar ?? Self.calendar(), display: display,
            converter: CurrencyConverter(displayCurrency: display, rates: rates)
        )
    }

    private func d(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    private func expense(
        _ amount: Decimal, in category: UUID?, on date: Date, from wallet: UUID? = nil, currency: String? = nil, rate: ExchangeRate? = nil
    ) -> Expense {
        Expense(title: "Spend", amount: amount, categoryID: category, paymentMethodID: wallet ?? cash.id, date: date, currencyCode: currency, rate: rate)
    }

    private func income(_ amount: Decimal, on date: Date, into wallet: UUID? = nil, currency: String? = nil, rate: ExchangeRate? = nil) -> Income {
        Income(title: "Salary", amount: amount, currencyCode: currency, rate: rate, walletID: wallet ?? cash.id, date: date)
    }

    private func moved(
        _ amount: Decimal, on date: Date, kind: TransferKind = .savings, from: UUID? = nil, to: UUID? = nil,
        currency: String? = nil, rate: ExchangeRate? = nil
    ) -> Transfer {
        Transfer(
            kind: kind, fromWalletID: from ?? cash.id, toWalletID: to ?? savings.id, amountOut: amount,
            currencyOut: currency, rate: rate, date: date, incomeID: kind == .savings ? UUID() : nil
        )
    }

    private func rate(_ value: String, to code: String) -> ExchangeRate {
        ExchangeRate(rate: d(value), currencyCode: code, date: at(9, 1))
    }

    // MARK: The split

    @Test func theMonthsIncomeIsSplitByThePercentages() {
        let september = account(
            expenses: [
                expense(30_000, in: food.id, on: at(9, 3)),
                expense(20_000, in: rent.id, on: at(9, 1, 0)),
                expense(10_000, in: shopping.id, on: at(9, 12)),
            ],
            incomes: [
                income(150_000, on: at(9, 5)),
                // Into no wallet: still the month's income.
                Income(title: "Gift", amount: 50_000, walletID: nil, date: at(9, 25)),
            ],
            transfers: [moved(40_000, on: at(9, 5))]
        )
        let result = envelopes(september, month: at(9, 15))
        #expect(result.month == Self.calendar().dateInterval(of: .month, for: at(9, 15)))
        #expect(result.income == 200_000)
        #expect(result.savings == Envelope(percent: 20, budget: 40_000, spent: 40_000))
        #expect(result.expenses == Envelope(percent: 50, budget: 100_000, spent: 50_000))
        #expect(result.freeMoney == Envelope(percent: 30, budget: 60_000, spent: 10_000))
        #expect(result.savings.left == 0)
        #expect(result.expenses.left == 50_000)
        #expect(result.freeMoney.left == 50_000)
        #expect(result.unconverted == 0)
    }

    @Test func overspendingLeavesLessThanNothing() {
        let over = account(expenses: [expense(70_000, in: food.id, on: at(9, 3))], incomes: [income(100_000, on: at(9, 1))])
        #expect(envelopes(over, month: at(9, 1)).expenses.left == -20_000)
    }

    @Test func withoutIncomeTheEnvelopesShowSpendingOnly() {
        let spendingOnly = account(
            expenses: [expense(30_000, in: food.id, on: at(10, 3)), expense(10_000, in: shopping.id, on: at(10, 4))],
            transfers: [moved(5_000, on: at(10, 6))]
        )
        let result = envelopes(spendingOnly, month: at(10, 15))
        #expect(result.income == 0)
        #expect(result.expenses == Envelope(percent: 50, budget: nil, spent: 30_000))
        #expect(result.freeMoney == Envelope(percent: 30, budget: nil, spent: 10_000))
        #expect(result.savings == Envelope(percent: 20, budget: nil, spent: 5_000))
        #expect(result.expenses.left == nil && result.freeMoney.left == nil && result.savings.left == nil)
        // An empty month: nothing at all.
        let empty = envelopes(account(), month: at(10, 15))
        #expect(empty.income == 0 && empty.unconverted == 0)
        #expect(empty.expenses == Envelope(percent: 50, budget: nil, spent: 0))
    }

    @Test func uncategorisedAndDeletedCategoriesCountAsExpenses() {
        let spent = account(expenses: [
            expense(1_000, in: nil, on: at(9, 2)),
            // A category the account no longer has.
            expense(2_000, in: UUID(), on: at(9, 3)),
            // A role this version does not know: Expenses, the default.
            expense(4_000, in: investments.id, on: at(9, 4)),
            expense(8_000, in: food.id, on: at(9, 5)),
            expense(16_000, in: shopping.id, on: at(9, 6)),
        ])
        let result = envelopes(spent, month: at(9, 1))
        #expect(result.expenses.spent == 15_000)
        #expect(result.freeMoney.spent == 16_000)
    }

    @Test func theEnvelopesTakeTheRulesPercentages() {
        let rule = SplitRule(isEnabled: true, savingsPercent: 10, expensesPercent: 60, freeMoneyPercent: 30, savingsWalletID: savings.id)
        let paid = account(incomes: [income(100_000, on: at(9, 1))], rule: rule)
        let result = envelopes(paid, month: at(9, 1))
        #expect(result.savings.percent == 10 && result.savings.budget == 10_000)
        #expect(result.expenses.percent == 60 && result.expenses.budget == 60_000)
        #expect(result.freeMoney.percent == 30 && result.freeMoney.budget == 30_000)
        // Whether the rule is on is for the screen to decide.
        var off = rule
        off.isEnabled = false
        #expect(envelopes(account(incomes: paid.incomes, rule: off), month: at(9, 1)) == result)
    }

    @Test func budgetsAreRoundedToTheDisplayCurrency() {
        // 333 RWF: 66.6, 166.5 and 99.9, halves away from zero.
        let francs = envelopes(account(incomes: [income(333, on: at(9, 1))]), month: at(9, 1))
        #expect(francs.savings.budget == 67)
        #expect(francs.expenses.budget == 167)
        #expect(francs.freeMoney.budget == 100)
        // 33.33 USD: 6.666, 16.665 and 9.999.
        let dollarIncome = account(incomes: [income(d("33.33"), on: at(9, 1))])
        let inDollars = envelopes(dollarIncome, month: at(9, 1), display: "USD")
        #expect(inDollars.savings.budget == d("6.67"))
        #expect(inDollars.expenses.budget == d("16.67"))
        #expect(inDollars.freeMoney.budget == 10)
    }

    // MARK: Months

    @Test func onlyTheMonthsEntriesCountAndNothingCarriesOver() {
        let twoMonths = account(
            expenses: [
                expense(1, in: food.id, on: at(8, 31, 23, 59, 59)),
                expense(80_000, in: food.id, on: at(9, 1, 0)),
                expense(2, in: food.id, on: at(9, 30, 23, 59, 59)),
                expense(10_000, in: food.id, on: at(10, 1, 0)),
            ],
            incomes: [income(100_000, on: at(9, 30, 23, 59, 59)), income(100_000, on: at(10, 1, 0))],
            transfers: [moved(4, on: at(8, 31, 23, 59, 59)), moved(20_000, on: at(9, 30)), moved(8, on: at(10, 1, 0))]
        )
        let september = envelopes(twoMonths, month: at(9, 30, 23, 59, 59))
        #expect(september.month.start == at(9, 1, 0) && september.month.end == at(10, 1, 0))
        #expect(september.income == 100_000)
        #expect(september.expenses.spent == 80_002)
        #expect(september.expenses.left == -30_002)
        #expect(september.savings.spent == 20_000)
        // October starts afresh: September's overspending is not carried.
        let october = envelopes(twoMonths, month: at(10, 1, 0))
        #expect(october.month.start == at(10, 1, 0))
        #expect(october.income == 100_000)
        #expect(october.expenses.spent == 10_000)
        #expect(october.expenses.left == 40_000)
        #expect(october.savings.spent == 8)
    }

    @Test func aMonthWithoutIncomeShowsSpendingOnlyWhateverCameBefore() {
        let paidOnce = account(
            expenses: [expense(10_000, in: food.id, on: at(9, 3)), expense(5_000, in: food.id, on: at(10, 3))],
            incomes: [income(100_000, on: at(9, 1))]
        )
        #expect(envelopes(paidOnce, month: at(9, 3)).expenses.budget == 50_000)
        let october = envelopes(paidOnce, month: at(10, 3))
        #expect(october.expenses == Envelope(percent: 50, budget: nil, spent: 5_000))
    }

    @Test func theMonthIsTheSameWhicheverDayTheWeekStarts() {
        // The week of 28 September (Monday) to 4 October 2026 spans both
        // months; so does the week of Sunday 27 September.
        let sunday = Self.calendar(firstWeekday: 1)
        let monday = Self.calendar(firstWeekday: 2)
        let straddling = account(
            expenses: [
                expense(1, in: food.id, on: at(9, 27)),
                expense(2, in: food.id, on: at(9, 30)),
                expense(4, in: food.id, on: at(10, 1)),
                expense(8, in: food.id, on: at(10, 3)),
                expense(16, in: food.id, on: at(10, 4)),
            ],
            incomes: [income(1_000, on: at(9, 28)), income(3_000, on: at(10, 2))]
        )
        for calendar in [sunday, monday] {
            let september = envelopes(straddling, month: at(9, 28), calendar: calendar)
            #expect(september.month == DateInterval(start: at(9, 1, 0), end: at(10, 1, 0)))
            #expect(september.income == 1_000)
            #expect(september.expenses.spent == 3)
            let october = envelopes(straddling, month: at(10, 4), calendar: calendar)
            #expect(october.month == DateInterval(start: at(10, 1, 0), end: at(11, 1, 0)))
            #expect(october.income == 3_000)
            #expect(october.expenses.spent == 28)
        }
        #expect(envelopes(straddling, month: at(9, 28), calendar: sunday) == envelopes(straddling, month: at(9, 28), calendar: monday))
        #expect(envelopes(straddling, month: at(10, 4), calendar: sunday) == envelopes(straddling, month: at(10, 4), calendar: monday))
    }

    @Test func theMonthIsTheCalendarsMonth() {
        // 02:00 UTC on 1 October is 22:00 on 30 September in New York.
        let newYork = Self.calendar(zone: "America/New_York")
        let lateNight = account(
            expenses: [expense(500, in: food.id, on: at(10, 1, 2))],
            incomes: [income(10_000, on: at(9, 1, 2))]
        )
        let utc = envelopes(lateNight, month: at(9, 15))
        #expect(utc.income == 10_000)
        #expect(utc.expenses.spent == 0)
        let local = envelopes(lateNight, month: at(9, 15), calendar: newYork)
        #expect(local.income == 0)
        #expect(local.expenses == Envelope(percent: 50, budget: nil, spent: 500))
        #expect(local.month == newYork.dateInterval(of: .month, for: at(9, 15)))
    }

    // MARK: Savings

    @Test func savingsProgressComesFromSavingsTransfersOnly() {
        let transfers = account(
            incomes: [income(200_000, on: at(9, 5))],
            transfers: [
                moved(40_000, on: at(9, 5)),
                // Moved by hand into the savings wallet: not the split's.
                moved(25_000, on: at(9, 6), kind: .manual),
                moved(5_000, on: at(9, 7), kind: .cardPayment),
                // Its wallets deleted since: still saved that month.
                Transfer(kind: .savings, fromWalletID: nil, toWalletID: nil, amountOut: 1_000, date: at(9, 8), incomeID: UUID()),
                // Other months.
                moved(2_000, on: at(8, 31)),
                moved(3_000, on: at(10, 1, 0)),
            ]
        )
        let result = envelopes(transfers, month: at(9, 5))
        #expect(result.savings == Envelope(percent: 20, budget: 40_000, spent: 41_000))
        #expect(result.savings.left == -1_000)
        // Transfers are never spending.
        #expect(result.expenses.spent == 0 && result.freeMoney.spent == 0)
    }

    // MARK: Currencies

    @Test func entriesInOtherCurrenciesUseTheirSavedRates() {
        // Today 1 USD is 1,400 RWF and 0.9 EUR; the entries saved other rates.
        let table = ExchangeRates(base: "USD", rates: ["RWF": 1400, "EUR": d("0.9")], date: at(9, 30), fetchedAt: at(9, 30))
        let mixed = account(
            expenses: [
                expense(10, in: food.id, on: at(9, 3), currency: "EUR", rate: rate("1500", to: "RWF")),
                expense(20, in: shopping.id, on: at(9, 4), from: dollars.id, rate: rate("1350", to: "RWF")),
            ],
            incomes: [
                // Into the dollar wallet, saved at 1,350.
                income(100, on: at(9, 1), into: dollars.id, rate: rate("1350", to: "RWF")),
                // Saved while the display currency was USD.
                income(100, on: at(9, 2), currency: "EUR", rate: rate("1.1", to: "USD")),
                // No saved rate: today's.
                income(50, on: at(9, 3), into: dollars.id),
            ],
            transfers: [moved(30, on: at(9, 1), from: dollars.id, currency: "USD", rate: rate("1350", to: "RWF"))]
        )
        let result = envelopes(mixed, month: at(9, 1), rates: table)
        // 135,000 + 154,000 + 70,000.
        #expect(result.income == 359_000)
        #expect(result.expenses.spent == 15_000)
        #expect(result.freeMoney.spent == 27_000)
        #expect(result.savings.spent == 40_500)
        #expect(result.savings.budget == 71_800)
        #expect(result.expenses.budget == 179_500)
        #expect(result.freeMoney.budget == 107_700)
        #expect(result.unconverted == 0)
    }

    @Test func whatCannotBeConvertedIsLeftOutAndCounted() {
        let unknown = account(
            expenses: [
                expense(10, in: food.id, on: at(9, 3), currency: "GBP"),
                expense(1_000, in: food.id, on: at(9, 4)),
            ],
            incomes: [income(100, on: at(9, 1), into: dollars.id), income(200_000, on: at(9, 2))],
            transfers: [moved(10, on: at(9, 5), currency: "GBP")]
        )
        let result = envelopes(unknown, month: at(9, 1))
        #expect(result.income == 200_000)
        #expect(result.expenses.spent == 1_000)
        #expect(result.savings.spent == 0)
        #expect(result.unconverted == 3)
        // A month whose only income cannot be converted has no budgets.
        let dollarsOnly = account(expenses: [expense(1_000, in: food.id, on: at(10, 4))], incomes: [income(100, on: at(10, 1), into: dollars.id)])
        let october = envelopes(dollarsOnly, month: at(10, 1))
        #expect(october.income == 0)
        #expect(october.expenses == Envelope(percent: 50, budget: nil, spent: 1_000))
        #expect(october.unconverted == 1)
    }
}
