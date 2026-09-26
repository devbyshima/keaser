import Foundation
import Testing
@testable import KeaserKit

private func calendar(firstWeekday: Int = 1, timeZone: String = "America/New_York") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: timeZone)!
    c.locale = Locale(identifier: "en_US")
    c.firstWeekday = firstWeekday
    return c
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct WeeklySummaryTests {
    @Test func firesAtSevenOnTheLastDayOfASundayWeek() {
        let cal = calendar(firstWeekday: 1)
        // Wednesday 23 Sep 2026; a Sunday-first week ends on Saturday the 26th.
        let fire = WeeklySummary.nextFireDate(after: date(2026, 9, 23, in: cal), calendar: cal)
        #expect(fire == date(2026, 9, 26, 19, in: cal))
    }

    @Test func firesOnSundayWhenWeeksStartOnMonday() {
        let cal = calendar(firstWeekday: 2)
        let fire = WeeklySummary.nextFireDate(after: date(2026, 9, 23, in: cal), calendar: cal)
        #expect(fire == date(2026, 9, 27, 19, in: cal))
    }

    @Test func movesToNextWeekOnceTheMomentHasPassed() {
        let cal = calendar(firstWeekday: 1)
        let atSeven = WeeklySummary.nextFireDate(after: date(2026, 9, 26, 19, 0, in: cal), calendar: cal)
        let later = WeeklySummary.nextFireDate(after: date(2026, 9, 26, 21, 30, in: cal), calendar: cal)
        #expect(atSeven == date(2026, 10, 3, 19, in: cal))
        #expect(later == date(2026, 10, 3, 19, in: cal))
        let justBefore = WeeklySummary.nextFireDate(after: date(2026, 9, 26, 18, 59, in: cal), calendar: cal)
        #expect(justBefore == date(2026, 9, 26, 19, in: cal))
    }

    @Test func keepsLocalTimeAcrossDaylightSavingChange() {
        // US clocks go back on Sunday 1 Nov 2026; a Monday-first week ends that day.
        let cal = calendar(firstWeekday: 2)
        let fire = WeeklySummary.nextFireDate(after: date(2026, 10, 28, in: cal), calendar: cal)
        #expect(fire == date(2026, 11, 1, 19, in: cal))
        #expect(cal.component(.hour, from: fire!) == 19)
    }

    @Test func planReportsTheSelectedAccountsWeek() throws {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 9, 23, in: cal)
        var personal = Account(name: "Personal")
        personal.expenses = [
            Expense(title: "Coffee", amount: Decimal(string: "4.50")!, date: date(2026, 9, 20, 9, in: cal)),
            Expense(title: "Groceries", amount: Decimal(string: "87.23")!, date: date(2026, 9, 26, 10, in: cal)),
            // Previous week: not counted.
            Expense(title: "Gas", amount: 42, date: date(2026, 9, 19, 10, in: cal)),
        ]
        var business = Account(name: "Business")
        business.expenses = [Expense(title: "Lunch", amount: 99, date: now)]
        var prefs = Preferences(currencyCode: "USD", firstWeekday: .sunday, weeklySummaryEnabled: true)
        prefs.selectedAccountID = personal.id
        let database = Database(accounts: [personal, business], preferences: prefs)

        let plan = try #require(WeeklySummary.plan(for: database, now: now, calendar: cal, locale: Locale(identifier: "en_US")))
        #expect(plan.title == "Weekly summary")
        #expect(plan.body == "You spent $91.73 this week.")
        #expect(plan.fireDate == date(2026, 9, 26, 19, in: cal))
        #expect(plan.week.start == date(2026, 9, 20, 0, in: cal))
    }

    @Test func noPlanWhenDisabledOrWithoutAccount() {
        let cal = calendar()
        let now = date(2026, 9, 23, in: cal)
        let off = Database(accounts: [Account(name: "Personal")], preferences: Preferences(weeklySummaryEnabled: false))
        let empty = Database(accounts: [], preferences: Preferences(weeklySummaryEnabled: true))
        #expect(WeeklySummary.plan(for: off, now: now, calendar: cal) == nil)
        #expect(WeeklySummary.plan(for: empty, now: now, calendar: cal) == nil)
    }

    @Test func planForNextWeekCountsNextWeeksExpenses() throws {
        let cal = calendar(firstWeekday: 1)
        let saturdayNight = date(2026, 9, 26, 22, in: cal)
        var account = Account(name: "Personal")
        account.expenses = [
            Expense(title: "This week", amount: 10, date: date(2026, 9, 25, in: cal)),
            Expense(title: "Next week", amount: 5, date: date(2026, 9, 28, in: cal)),
        ]
        let database = Database(accounts: [account], preferences: Preferences(currencyCode: "USD", weeklySummaryEnabled: true))
        let plan = try #require(WeeklySummary.plan(for: database, now: saturdayNight, calendar: cal, locale: Locale(identifier: "en_US")))
        #expect(plan.fireDate == date(2026, 10, 3, 19, in: cal))
        #expect(plan.body == "You spent $5.00 this week.")
    }
}

struct QuickLogTests {
    private func account() -> Account {
        var account = Account(name: "Personal")
        let food = account.categories.first { $0.name == "Food & Drinks" }!
        let travel = account.categories.first { $0.name == "Travel" }!
        let credit = account.paymentMethods.first { $0.name == "Credit Card" }!
        let cash = account.paymentMethods.first { $0.name == "Cash" }!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        account.expenses = [
            Expense(title: "Blue Bottle", amount: 5, categoryID: travel.id, paymentMethodID: cash.id, date: now.addingTimeInterval(-86_400 * 10), createdAt: now.addingTimeInterval(-86_400 * 10)),
            Expense(title: "blue bottle ", amount: 6, categoryID: food.id, paymentMethodID: credit.id, date: now.addingTimeInterval(-86_400), createdAt: now.addingTimeInterval(-86_400)),
            Expense(title: "Uber", amount: 20, date: now),
        ]
        return account
    }

    @Test func doubleAmountsBecomeExactMoney() {
        #expect(QuickLog.amount(from: 16.99, currencyCode: "USD") == Decimal(string: "16.99"))
        #expect(QuickLog.amount(from: 0.1 + 0.2, currencyCode: "USD") == Decimal(string: "0.3"))
        #expect(QuickLog.amount(from: 1234.567, currencyCode: "USD") == Decimal(string: "1234.57"))
        #expect(QuickLog.amount(from: 1500.4, currencyCode: "JPY") == 1500)
        #expect(QuickLog.amount(from: 0, currencyCode: "USD") == nil)
        #expect(QuickLog.amount(from: -3, currencyCode: "USD") == nil)
        #expect(QuickLog.amount(from: 0.001, currencyCode: "USD") == nil)
        #expect(QuickLog.amount(from: .infinity, currencyCode: "USD") == nil)
    }

    @Test func walletTextAmounts() {
        let us = Locale(identifier: "en_US")
        #expect(QuickLog.amount(from: "$4.50", currencyCode: "USD", locale: us) == Decimal(string: "4.5"))
        #expect(QuickLog.amount(from: "1,299.00", currencyCode: "USD", locale: us) == 1299)
        #expect(QuickLog.amount(from: "4,50 €", currencyCode: "EUR", locale: Locale(identifier: "fr_FR")) == Decimal(string: "4.5"))
        #expect(QuickLog.amount(from: "free", currencyCode: "USD", locale: us) == nil)
        #expect(QuickLog.amount(from: "$0.00", currencyCode: "USD", locale: us) == nil)
    }

    @Test func confirmationNamesAmountAndAccount() {
        let text = QuickLog.confirmation(amount: Decimal(string: "16.99")!, currencyCode: "USD", accountName: "Personal", locale: Locale(identifier: "en_US"))
        #expect(text == "Added $16.99 to Personal")
    }

    @Test func findsTheMostRecentExpenseIgnoringCase() {
        let account = account()
        #expect(QuickLog.mostRecentExpense(titled: "BLUE BOTTLE", in: account)?.amount == 6)
        #expect(QuickLog.mostRecentExpense(titled: "Blüe  Bottle", in: account)?.amount == 6)
        #expect(QuickLog.mostRecentExpense(titled: "Starbucks", in: account) == nil)
        #expect(QuickLog.mostRecentExpense(titled: "  ", in: account) == nil)
    }

    @Test(arguments: [
        ("credit card", "Credit Card"),
        ("Debit Mastercard", "Debit Card"),
        ("My E-Wallet", "E-Wallet"),
        ("Cash", "Cash"),
    ])
    func matchesCardsToPaymentMethods(card: String, expected: String) {
        #expect(QuickLog.paymentMethod(forCard: card, in: account())?.name == expected)
    }

    @Test func unknownCardsMatchNothing() {
        let account = account()
        #expect(QuickLog.paymentMethod(forCard: "Apple Card", in: account) == nil)
        #expect(QuickLog.paymentMethod(forCard: nil, in: account) == nil)
        #expect(QuickLog.paymentMethod(forCard: "", in: account) == nil)
    }

    @Test func walletExpenseReusesTheLastFiling() {
        let account = account()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expense = QuickLog.walletExpense(merchant: " Blue Bottle ", amount: Decimal(string: "4.5")!, card: "Apple Card", in: account, now: now)
        #expect(expense.title == "Blue Bottle")
        #expect(expense.amount == Decimal(string: "4.5"))
        #expect(account.category(id: expense.categoryID)?.name == "Food & Drinks")
        #expect(account.paymentMethod(id: expense.paymentMethodID)?.name == "Credit Card")
        #expect(expense.date == now)
    }

    @Test func aRecognisedCardWinsOverTheLastMethod() {
        let account = account()
        let expense = QuickLog.walletExpense(merchant: "Blue Bottle", amount: 5, card: "Debit Mastercard", in: account)
        #expect(account.paymentMethod(id: expense.paymentMethodID)?.name == "Debit Card")
        #expect(account.category(id: expense.categoryID)?.name == "Food & Drinks")
    }

    @Test func aNewMerchantIsUnfiled() {
        let account = account()
        let expense = QuickLog.walletExpense(merchant: "", amount: 5, card: nil, in: account)
        #expect(expense.title == "Expense")
        #expect(expense.categoryID == nil)
        #expect(expense.paymentMethodID == nil)
    }

    @Test func deletedCategoriesDoNotComeBack() {
        var account = account()
        account.categories.removeAll { $0.name == "Food & Drinks" }
        let expense = QuickLog.walletExpense(merchant: "Blue Bottle", amount: 5, card: nil, in: account)
        #expect(expense.categoryID == nil)
        #expect(account.paymentMethod(id: expense.paymentMethodID)?.name == "Credit Card")
    }
}

struct SpendingSnapshotTests {
    private let cal = calendar(firstWeekday: 2)

    private func database(pro: Bool = true, now: Date) -> Database {
        var personal = Account(name: "Personal")
        personal.expenses = [
            Expense(title: "Coffee", amount: Decimal(string: "4.50")!, date: date(2026, 9, 21, in: cal)), // Monday
            Expense(title: "Gas", amount: 42, date: date(2026, 9, 23, in: cal)), // Wednesday
            Expense(title: "Rent", amount: 900, date: date(2026, 9, 1, in: cal)),
            Expense(title: "Flight", amount: 300, date: date(2026, 3, 14, in: cal)),
        ]
        var business = Account(name: "Business")
        business.expenses = [Expense(title: "Lunch", amount: 20, date: date(2026, 9, 23, in: cal))]
        var prefs = Preferences(currencyCode: "USD", firstWeekday: .monday)
        prefs.selectedAccountID = personal.id
        prefs.trialStartDate = pro ? now : now.addingTimeInterval(-86_400 * 30)
        return Database(accounts: [personal, business], preferences: prefs)
    }

    @Test func totalsThePeriodForTheSelectedAccount() {
        let now = date(2026, 9, 23, 15, in: cal)
        let db = database(now: now)
        let week = SpendingSnapshot.make(database: db, accountID: nil, period: .thisWeek, now: now, calendar: cal)
        #expect(week.state == .ready)
        #expect(week.accountName == "Personal")
        #expect(week.total == Decimal(string: "46.5"))
        #expect(week.caption == "This Week")
        #expect(week.bars.count == 7)
        #expect(week.bars.map(\.label) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(week.bars[2].isCurrent)
        #expect(week.bars[2].amount == 42)

        let month = SpendingSnapshot.make(database: db, accountID: nil, period: .thisMonth, now: now, calendar: cal)
        #expect(month.total == Decimal(string: "946.5"))
        #expect(month.bars.count == 30)
        #expect(month.bars[0].amount == 900)
        #expect(month.bars[22].isCurrent)

        let year = SpendingSnapshot.make(database: db, accountID: nil, period: .thisYear, now: now, calendar: cal)
        #expect(year.total == Decimal(string: "1246.5"))
        #expect(year.bars.count == 12)
        #expect(year.bars[2].amount == 300)
        #expect(year.bars[8].isCurrent)

        let today = SpendingSnapshot.make(database: db, accountID: nil, period: .today, now: now, calendar: cal)
        #expect(today.total == 42)
        #expect(today.bars.count == 7)
        #expect(today.bars.last?.isCurrent == true)
        #expect(today.bars.last?.amount == 42)
    }

    @Test func aConfiguredAccountWinsAndAMissingOneFallsBack() {
        let now = date(2026, 9, 23, 15, in: cal)
        let db = database(now: now)
        let business = SpendingSnapshot.make(database: db, accountID: db.accounts[1].id, period: .today, now: now, calendar: cal)
        #expect(business.accountName == "Business")
        #expect(business.total == 20)
        let gone = SpendingSnapshot.make(database: db, accountID: UUID(), period: .today, now: now, calendar: cal)
        #expect(gone.accountName == "Personal")
    }

    @Test func lockedAfterThePassAndEmptyWithoutAccounts() {
        let now = date(2026, 9, 23, 15, in: cal)
        let locked = SpendingSnapshot.make(database: database(pro: false, now: now), accountID: nil, period: .thisMonth, now: now, calendar: cal)
        #expect(locked.state == .locked)
        let empty = SpendingSnapshot.make(database: Database(), accountID: nil, period: .thisMonth, now: now, calendar: cal)
        #expect(empty.state == .noAccount)
        #expect(empty.accountName == nil)
    }

    @Test func refreshesAtMidnightOrWhenThePassEnds() {
        let now = date(2026, 9, 23, 15, in: cal)
        var prefs = Preferences()
        #expect(SpendingSnapshot.nextRefresh(after: now, preferences: prefs, calendar: cal) == date(2026, 9, 24, 0, in: cal))
        // A pass that ends at 9:00 tonight.
        prefs.trialStartDate = date(2026, 9, 16, 21, in: cal)
        #expect(SpendingSnapshot.nextRefresh(after: now, preferences: prefs, calendar: cal) == date(2026, 9, 23, 21, in: cal))
        prefs.hasProPurchase = true
        #expect(SpendingSnapshot.nextRefresh(after: now, preferences: prefs, calendar: cal) == date(2026, 9, 24, 0, in: cal))
    }
}

struct HalfOpenSpendingTests {
    @Test func aMidnightExpenseCountsInOneDayOnly() {
        let cal = calendar(firstWeekday: 1)
        let midnight = date(2026, 9, 24, 0, in: cal)
        var account = Account(name: "Personal")
        account.expenses = [Expense(title: "Coffee", amount: 4, date: midnight)]
        let bars = SpendingSnapshot.bars(for: account, period: .thisWeek, now: date(2026, 9, 24, 9, in: cal), calendar: cal)
        #expect(bars.map(\.amount) == [0, 0, 0, 0, 4, 0, 0])
    }
}

struct SpendingSnapshotTextTests {
    private func snapshot(_ total: String, period: Period = .thisMonth) -> SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: period, accountName: "Personal", total: Decimal(string: total)!, currencyCode: "USD", bars: [])
    }

    @Test func compactTotals() {
        let us = Locale(identifier: "en_US")
        #expect(snapshot("271.37").compactTotal(locale: us) == "$271")
        #expect(snapshot("0").compactTotal(locale: us) == "$0")
        #expect(snapshot("1246.50").compactTotal(locale: us) == "$1.25K")
        #expect(snapshot("18900").compactTotal(locale: us) == "$18.9K")
    }

    @Test func captions() {
        #expect(snapshot("1", period: .thisWeek).shortCaption == "WEEK")
        #expect(snapshot("1", period: .today).caption == "Today")
    }
}
