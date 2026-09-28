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

struct SpendingBreakdownTests {
    private let cal = calendar(firstWeekday: 2)
    private let now = date(2026, 9, 23, 15, in: calendar(firstWeekday: 2))

    /// Personal, with Pro, and the given expenses (category names map to the
    /// account's default categories; nil is uncategorised).
    private func database(_ expenses: [(String, String, String?, Date)], pro: Bool = true) -> Database {
        var account = Account(name: "Personal")
        account.expenses = expenses.map { title, amount, category, day in
            Expense(
                title: title,
                amount: Decimal(string: amount)!,
                categoryID: category.flatMap { name in account.categories.first { $0.name == name }?.id },
                date: day,
                createdAt: day
            )
        }
        var prefs = Preferences(currencyCode: "USD", firstWeekday: .monday)
        prefs.selectedAccountID = account.id
        prefs.trialStartDate = pro ? now : now.addingTimeInterval(-86_400 * 30)
        return Database(accounts: [account], preferences: prefs)
    }

    private func snapshot(_ db: Database, _ period: Period = .thisMonth) -> SpendingSnapshot {
        SpendingSnapshot.make(database: db, accountID: nil, period: period, now: now, calendar: cal)
    }

    @Test func totalsEachCategoryForThePeriodLargestFirst() {
        let db = database([
            ("Coffee", "4.50", "Food & Drinks", date(2026, 9, 21, in: cal)),
            ("Lunch", "12.25", "Food & Drinks", date(2026, 9, 22, in: cal)),
            ("Shoes", "80", "Shopping", date(2026, 9, 2, in: cal)),
            ("Taxi", "9", "Transportation", date(2026, 9, 23, in: cal)),
            // Last month: not in This Month.
            ("Flight", "300", "Travel", date(2026, 8, 30, in: cal)),
        ])
        let month = snapshot(db)
        #expect(month.categories.map(\.name) == ["Shopping", "Food & Drinks", "Transportation"])
        #expect(month.categories.map(\.amount) == [80, Decimal(string: "16.75")!, 9])
        #expect(month.categories.map(\.symbol) == ["cart.fill", "fork.knife", "car.fill"])
        #expect(month.categories.reduce(Decimal(0)) { $0 + $1.amount } == month.total)

        let week = snapshot(db, .thisWeek)
        #expect(week.categories.map(\.name) == ["Food & Drinks", "Transportation"])
    }

    @Test func uncategorizedAndDeletedCategoriesShareOneRow() {
        var db = database([
            ("Gift", "20", nil, date(2026, 9, 10, in: cal)),
            ("Old", "5", "Health", date(2026, 9, 11, in: cal)),
            ("Coffee", "4", "Food & Drinks", date(2026, 9, 12, in: cal)),
        ])
        // Health is deleted after its expense was logged.
        db.accounts[0].categories.removeAll { $0.name == "Health" }
        let rows = snapshot(db).categories
        #expect(rows.map(\.name) == ["Uncategorized", "Food & Drinks"])
        #expect(rows[0].kind == .uncategorized)
        #expect(rows[0].amount == 25)
        #expect(rows[0].symbol == ExpenseCategory.fallbackSymbol)
    }

    @Test func tiesKeepTheAccountsCategoryOrder() {
        let db = database([
            ("Taxi", "10", "Transportation", date(2026, 9, 3, in: cal)),
            ("Gift", "10", nil, date(2026, 9, 4, in: cal)),
            ("Shoes", "10", "Shopping", date(2026, 9, 5, in: cal)),
        ])
        #expect(snapshot(db).categories.map(\.name) == ["Shopping", "Transportation", "Uncategorized"])
    }

    @Test func extraCategoriesAreGroupedAsOther() {
        let db = database([
            ("A", "50", "Food & Drinks", date(2026, 9, 3, in: cal)),
            ("B", "40", "Shopping", date(2026, 9, 3, in: cal)),
            ("C", "30", "Travel", date(2026, 9, 3, in: cal)),
            ("D", "20", "Services", date(2026, 9, 3, in: cal)),
            ("E", "7.50", "Health", date(2026, 9, 3, in: cal)),
            ("F", "2.50", nil, date(2026, 9, 3, in: cal)),
        ])
        let month = snapshot(db)
        #expect(month.categories.count == 6)

        // Room for all six: no Other.
        #expect(month.categoryRows(maxRows: 6).map(\.name) == ["Food & Drinks", "Shopping", "Travel", "Services", "Health", "Uncategorized"])
        #expect(month.categoryRows(maxRows: 9).count == 6)

        // Room for four: three categories and Other with the remaining three.
        let four = month.categoryRows(maxRows: 4)
        #expect(four.map(\.name) == ["Food & Drinks", "Shopping", "Travel", "Other"])
        #expect(four[3].kind == .other)
        #expect(four[3].amount == 30)
        #expect(four[3].symbol == SpendingSnapshot.CategoryTotal.otherSymbol)
        #expect(four.reduce(Decimal(0)) { $0 + $1.amount } == month.total)

        #expect(month.categoryRows(maxRows: 1).map(\.name) == ["Other"])
        #expect(month.categoryRows(maxRows: 0).isEmpty)
    }

    @Test func sharesAreFractionsOfTheTotal() {
        let db = database([
            ("A", "75", "Food & Drinks", date(2026, 9, 3, in: cal)),
            ("B", "25", "Shopping", date(2026, 9, 3, in: cal)),
        ])
        let month = snapshot(db)
        #expect(month.share(of: 75) == 0.75)
        #expect(month.share(of: 25) == 0.25)
        #expect(month.share(of: 500) == 1)
        let empty = snapshot(database([]))
        #expect(empty.total == 0)
        #expect(empty.share(of: 0) == 0)
        #expect(empty.categories.isEmpty)
        #expect(empty.emptyText == "No expenses this month.")
    }

    @Test func latestIsTheNewestExpensesOfThePeriod() {
        var expenses: [(String, String, String?, Date)] = (1...8).map { day in
            ("Day \(day)", "1", "Food & Drinks", date(2026, 9, day, in: cal))
        }
        expenses.append(("Last month", "1", nil, date(2026, 8, 31, in: cal)))
        let month = snapshot(database(expenses))
        #expect(month.latest.count == SpendingSnapshot.latestLimit)
        #expect(month.latest.map(\.title) == ["Day 8", "Day 7", "Day 6", "Day 5", "Day 4", "Day 3"])
        #expect(month.latest[0].symbol == "fork.knife")

        let today = snapshot(database(expenses), .today)
        #expect(today.latest.isEmpty)
        #expect(today.emptyText == "No expenses today.")
    }

    private func plans(_ list: [(Int, Int)]) -> [SpendingSnapshot.BreakdownPlan] {
        list.map { SpendingSnapshot.BreakdownPlan(categories: $0.0, latest: $0.1) }
    }

    @Test func theExtraLargeWidgetAlwaysListsTheLatest() {
        let db = database([
            ("Coffee", "4", "Food & Drinks", date(2026, 9, 21, in: cal)),
            ("Shoes", "80", "Shopping", date(2026, 9, 2, in: cal)),
        ])
        #expect(snapshot(db).breakdownPlans(extraLarge: true) == plans([(5, 5), (5, 4), (5, 3), (4, 3), (4, 2), (3, 2), (3, 1), (2, 1)]))
    }

    /// Today with two categories: the large widget fills the room under
    /// them with the latest expenses rather than leaving it empty.
    @Test func aShortBreakdownIsFollowedByTheLatest() {
        let db = database([
            ("Netflix", "15.89", "Entertainment", date(2026, 9, 23, 9, in: cal)),
            ("Coffee", "6.74", "Food & Drinks", date(2026, 9, 23, 8, in: cal)),
            ("Shoes", "80", "Shopping", date(2026, 9, 2, in: cal)),
        ])
        let today = snapshot(db, .today)
        #expect(today.breakdownPlans(extraLarge: false) == plans([(2, 2), (2, 1), (2, 0), (1, 0)]))
        // At most five, as on the extra large widget.
        let month = snapshot(database((1...8).map { ("Day \($0)", "1", "Food & Drinks", date(2026, 9, $0, in: cal)) }))
        #expect(month.breakdownPlans(extraLarge: false) == plans([(1, 5), (1, 4), (1, 3), (1, 2), (1, 1), (1, 0)]))
    }

    @Test func aFullBreakdownKeepsEveryRow() {
        let names = ["Food & Drinks", "Shopping", "Travel", "Services", "Entertainment", "Health", "Transportation"]
        let db = database(names.enumerated().map { index, name in ("E\(index)", "\(10 + index)", name, date(2026, 9, 3, in: cal)) })
        let month = snapshot(db)
        let large = month.breakdownPlans(extraLarge: false)
        // Every plan with expenses keeps all six rows (five and Other); the
        // fallbacks for larger text drop rows and never add expenses.
        #expect(large.filter { $0.latest > 0 }.allSatisfy { $0.categories == SpendingSnapshot.largeBreakdownRows })
        #expect(Array(large.suffix(6)) == plans([(6, 0), (5, 0), (4, 0), (3, 0), (2, 0), (1, 0)]))
        #expect(month.categoryRows(maxRows: large[0].categories).last?.kind == .other)
    }

    @Test func noBreakdownNoPlans() {
        let empty = snapshot(database([]))
        #expect(empty.breakdownPlans(extraLarge: false).isEmpty)
        #expect(empty.breakdownPlans(extraLarge: true).isEmpty)
    }

    @Test func aLockedSnapshotCarriesNoSpending() {
        let db = database([("Coffee", "4", "Food & Drinks", date(2026, 9, 21, in: cal))], pro: false)
        let locked = snapshot(db)
        #expect(locked.state == .locked)
        #expect(locked.total == 0)
        #expect(locked.categories.isEmpty)
        #expect(locked.latest.isEmpty)
    }

    @Test func theSampleAddsUp() {
        let sample = SpendingSnapshot.sample()
        #expect(sample.categories.reduce(Decimal(0)) { $0 + $1.amount } == sample.total)
        #expect(!sample.latest.isEmpty)
        #expect(sample.latest.count <= SpendingSnapshot.latestLimit)
    }

    @Test(arguments: [
        (Period.today, "No expenses today."),
        (.thisWeek, "No expenses this week."),
        (.thisYear, "No expenses this year."),
        (.allTime, "No expenses yet."),
    ])
    func emptyTexts(_ example: (period: Period, text: String)) {
        let snapshot = SpendingSnapshot(state: .ready, period: example.period, accountName: nil, total: 0, currencyCode: "USD")
        #expect(snapshot.emptyText == example.text)
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
    private func snapshot(_ total: String, period: Period = .thisMonth) -> SpendingSnapshot {
        SpendingSnapshot(state: .ready, period: period, accountName: "Personal", total: Decimal(string: total)!, currencyCode: "USD")
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
