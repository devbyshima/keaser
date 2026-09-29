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

    /// Wallet writes the amount in its own number style, which need not be
    /// the phone's: "4,50 €" on an English (US) phone is 4.50, not 450, and
    /// "$4.50" on a German one is 4.50 too.
    @Test(arguments: ["en_US", "en_GB", "de_DE", "fr_FR", "rw_RW"])
    func walletTextAmountsReadTheSameInEveryLocale(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        func amount(_ text: String, _ code: String = "USD") -> Decimal? {
            QuickLog.amount(from: text, currencyCode: code, locale: locale)
        }
        #expect(amount("4,50 €", "EUR") == Decimal(string: "4.5"))
        #expect(amount("4,50 €") == Decimal(string: "4.5"))
        #expect(amount("1.234,56 €") == Decimal(string: "1234.56"))
        #expect(amount("$4.50") == Decimal(string: "4.5"))
        #expect(amount("US$4.50") == Decimal(string: "4.5"))
        #expect(amount("4.50") == Decimal(string: "4.5"))
        #expect(amount("RWF 5,000", "RWF") == 5000)
        #expect(amount("5 000 RWF", "RWF") == 5000)
        #expect(amount("¥1,500", "JPY") == 1500)
        #expect(amount("CHF 1'234.50", "CHF") == Decimal(string: "1234.5"))
        #expect(amount("-$4.50") == nil)
        #expect(amount("$0.00") == nil)
        #expect(amount("free") == nil)
        // Rounded to Keaser's currency, as before.
        #expect(amount("$4.99", "JPY") == 5)
    }

    @Test func confirmationNamesAmountAndAccount() {
        let us = Locale(identifier: "en_US")
        let amount = Decimal(string: "16.99")!
        #expect(QuickLog.confirmation(amount: amount, currencyCode: "USD", accountName: "Personal", locale: us) == "Added $16.99 to Personal.")
        #expect(QuickLog.confirmation(amount: amount, currencyCode: "USD", accountName: "Personal", title: " Coffee ", locale: us) == "Added $16.99 for Coffee to Personal.")
        #expect(QuickLog.confirmation(amount: amount, currencyCode: "USD", accountName: "Personal", title: QuickLog.defaultTitle, locale: us) == "Added $16.99 to Personal.")
    }

    @Test func theSpokenQuestionNamesEveryDetail() {
        let us = Locale(identifier: "en_US")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 9))!
        let account = Account(name: "Personal")
        let shopping = account.categories.first { $0.name == "Shopping" }!
        let card = account.paymentMethods.first { $0.name == "Credit Card" }!
        let full = Expense(title: "Uniqlo", amount: Decimal(string: "19.90")!, categoryID: shopping.id, paymentMethodID: card.id, date: now)
        #expect(QuickLog.confirmationQuestion(for: full, in: account, currencyCode: "USD", now: now, calendar: cal, locale: us)
            == "Add $19.90 for Uniqlo to Personal, under Shopping, paid with Credit Card?")
        let bare = Expense(title: QuickLog.defaultTitle, amount: 5, date: cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0))!)
        #expect(QuickLog.confirmationQuestion(for: bare, in: account, currencyCode: "USD", now: now, calendar: cal, locale: us)
            == "Add $5.00 to Personal, dated September 20, 2026?")
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

/// A shortcut saved while Personal was selected keeps Personal's label IDs.
/// Once Business is selected, those IDs must still resolve, and the expense
/// is filed under Business's label with the same name.
struct ShortcutLabelTests {
    private let personal = Account(name: "Personal")
    private let business = Account(name: "Business")

    private var database: Database {
        Database(accounts: [personal, business], preferences: Preferences(selectedAccountID: business.id))
    }

    @Test func idsFromAnyAccountResolve() {
        let food = personal.categories.first { $0.name == "Food & Drinks" }!
        let cash = personal.paymentMethods.first { $0.name == "Cash" }!
        #expect(database.selectedAccount?.id == business.id)
        #expect(QuickLog.categories(withIDs: [food.id], in: database) == [food])
        #expect(QuickLog.paymentMethods(withIDs: [cash.id], in: database) == [cash])
        #expect(QuickLog.categories(withIDs: [UUID()], in: database).isEmpty)
    }

    @Test func anotherAccountsLabelIsFiledByName() {
        let food = personal.categories.first { $0.name == "Food & Drinks" }!
        let cash = personal.paymentMethods.first { $0.name == "Cash" }!
        let category = QuickLog.category(id: food.id, name: food.name, in: business)
        let method = QuickLog.paymentMethod(id: cash.id, name: cash.name, in: business)
        #expect(category == business.categories.first { $0.name == "Food & Drinks" })
        #expect(category?.id != food.id)
        #expect(method == business.paymentMethods.first { $0.name == "Cash" })
    }

    @Test func theSameAccountKeepsItsOwnLabel() {
        var account = personal
        let food = account.categories.first { $0.name == "Food & Drinks" }!
        // A second label with the same name must not win over the exact one.
        account.categories.append(ExpenseCategory(name: "Food & Drinks", symbol: "fork.knife"))
        #expect(QuickLog.category(id: food.id, name: food.name, in: account)?.id == food.id)
        #expect(QuickLog.category(id: UUID(), name: "food & drinks", in: account)?.id == food.id)
        #expect(QuickLog.category(id: UUID(), name: "Rent", in: account) == nil)
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
        #expect(week.spentCaption == "Spent This Week")

        let month = SpendingSnapshot.make(database: db, accountID: nil, period: .thisMonth, now: now, calendar: cal)
        #expect(month.total == Decimal(string: "946.5"))

        let year = SpendingSnapshot.make(database: db, accountID: nil, period: .thisYear, now: now, calendar: cal)
        #expect(year.total == Decimal(string: "1246.5"))

        let today = SpendingSnapshot.make(database: db, accountID: nil, period: .today, now: now, calendar: cal)
        #expect(today.total == 42)
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
        // A locked widget carries no spending, only the lock.
        #expect(locked.total == 0)
        let empty = SpendingSnapshot.make(database: Database(), accountID: nil, period: .thisMonth, now: now, calendar: cal)
        #expect(empty.state == .noAccount)
        #expect(empty.accountName == nil)
    }

    /// Adding an account would not bring a lapsed widget back, so it shows
    /// the lock, in the widget gallery too, rather than asking for one.
    @Test func withoutAnAccountTheLockWinsOnceProIsOver() {
        let now = date(2026, 9, 23, 15, in: cal)
        func state(_ change: (inout Preferences) -> Void) -> SpendingSnapshot.State {
            var prefs = Preferences()
            change(&prefs)
            return SpendingSnapshot.make(database: Database(preferences: prefs), accountID: nil, period: .thisMonth, now: now, calendar: cal).state
        }
        // Before the pass starts (a first run), and while it lasts.
        #expect(state { _ in } == .noAccount)
        #expect(state { $0.trialStartDate = now } == .noAccount)
        // The pass is over.
        #expect(state { $0.trialStartDate = now.addingTimeInterval(-86_400 * 30) } == .locked)
        // A subscription that ran out, and a lifetime purchase.
        #expect(state { $0.hasProPurchase = true; $0.proExpirationDate = now.addingTimeInterval(-60) } == .locked)
        #expect(state { $0.hasProPurchase = true } == .noAccount)
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
        var prefs = Preferences()
        prefs.hasProPurchase = true
        let db = Database(accounts: [account], preferences: prefs)
        let lateTheDayBefore = SpendingSnapshot.make(database: db, accountID: nil, period: .today, now: date(2026, 9, 23, 23, in: cal), calendar: cal)
        let thatMorning = SpendingSnapshot.make(database: db, accountID: nil, period: .today, now: date(2026, 9, 24, 9, in: cal), calendar: cal)
        #expect(lateTheDayBefore.total == 0)
        #expect(thatMorning.total == 4)
    }
}

struct SpendingSnapshotTextTests {
    private let us = Locale(identifier: "en_US")

    private func snapshot(_ total: String, period: Period = .thisMonth, currency: String = "USD") -> SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: period, accountName: "Personal", total: Decimal(string: total)!, currencyCode: currency)
    }

    @Test func captions() {
        #expect(snapshot("1", period: .today).caption == "Today")
    }

    @Test(arguments: [
        (Period.today, "Today"),
        (.thisWeek, "Week"),
        (.thisMonth, "Month"),
        (.thisYear, "Year"),
        (.allTime, "All Time"),
    ])
    func shortCaptions(_ example: (period: Period, caption: String)) {
        #expect(snapshot("1", period: example.period).shortCaption == example.caption)
    }

    /// Amounts in the currency's own style; U+00A0 is the no-break space
    /// Foundation puts between a currency code and the number.
    @Test(arguments: [
        ("USD", "148.13", "$148"),
        ("USD", "0", "$0"),
        ("USD", "999.49", "$999"),
        ("USD", "999.50", "$1K"),
        ("USD", "1400", "$1.4K"),
        ("USD", "1246.50", "$1.2K"),
        ("USD", "18900", "$19K"),
        ("USD", "150000", "$150K"),
        ("USD", "2340000", "$2.3M"),
        ("EUR", "86.40", "€86"),
        ("GBP", "4210", "£4.2K"),
        ("JPY", "980", "¥980"),
        ("JPY", "15800", "¥16K"),
        ("RWF", "12345678", "RWF\u{00A0}12M"),
        ("RWF", "650", "RWF\u{00A0}650"),
    ])
    func compactTotals(_ example: (currency: String, total: String, compact: String)) {
        #expect(snapshot(example.total, currency: example.currency).compactTotal(locale: us) == example.compact)
    }

    @Test func compactTotalsKeepTheSign() {
        #expect(snapshot("-148.13").compactTotal(locale: us) == "-$148")
        #expect(snapshot("-1400").compactTotal(locale: us) == "-$1.4K")
    }

    @Test(arguments: [
        (Period.thisWeek, "USD", "148.13", "Spent This Week: $148.13"),
        (.today, "EUR", "6.5", "Spent Today: €6.50"),
        (.thisMonth, "JPY", "15800", "Spent This Month: ¥15,800"),
        (.thisYear, "RWF", "12345678", "Spent This Year: RWF\u{00A0}12,345,678"),
    ])
    func inlineTexts(_ example: (period: Period, currency: String, total: String, text: String)) {
        let snapshot = snapshot(example.total, period: example.period, currency: example.currency)
        #expect(snapshot.inlineText(locale: us) == example.text)
    }

    @Test func shortInlineTexts() {
        #expect(snapshot("148.13", period: .thisWeek).shortInlineText(locale: us) == "Week: $148")
        #expect(snapshot("12345678", period: .thisYear, currency: "RWF").shortInlineText(locale: us) == "Year: RWF\u{00A0}12M")
        #expect(snapshot("15800", period: .today, currency: "JPY").shortInlineText(locale: us) == "Today: ¥16K")
    }

    @Test(arguments: [
        (Period.today, "Spent Today"),
        (.thisWeek, "Spent This Week"),
        (.thisMonth, "Spent This Month"),
        (.thisYear, "Spent This Year"),
        (.allTime, "Spent All Time"),
    ])
    func mediumCaptions(_ example: (period: Period, caption: String)) {
        #expect(snapshot("1", period: example.period).spentCaption == example.caption)
    }
}
