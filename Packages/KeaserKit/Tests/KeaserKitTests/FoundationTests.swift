import Foundation
import Testing
@testable import KeaserKit

@MainActor
struct StoreTests {
    @Test func createAccountSelectsItAndSeedsDefaults() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "  Personal ")
        #expect(account.name == "Personal")
        #expect(store.selectedAccount?.id == account.id)
        #expect(account.categories.map(\.name) == ["Food & Drinks", "Shopping", "Travel", "Services", "Entertainment", "Health", "Transportation"])
        #expect(account.paymentMethods.map(\.name) == ["Credit Card", "Debit Card", "Cash", "Bank Transfer", "E-Wallet"])
    }

    @Test func saveExpenseUpsertsByID() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var expense = Expense(title: "Outing", amount: 20)
        store.saveExpense(expense, in: account.id)
        expense.amount = 25
        store.saveExpense(expense, in: account.id)
        #expect(store.account(id: account.id)?.expenses.count == 1)
        #expect(store.account(id: account.id)?.expenses.first?.amount == 25)
    }

    @Test func deletingANotionExpenseQueuesItsPage() {
        let store = KeaserStore(file: nil)
        let map = NotionPropertyMap(title: "Name")
        let account = store.createAccount(name: "N", notion: NotionConnection(databaseID: "db", databaseTitle: "Expenses", properties: map))
        let expense = Expense(title: "Synced", amount: 1, notionPageID: "page-1")
        store.saveExpense(expense, in: account.id)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        store.deleteExpense(expense.id, in: account.id)
        #expect(store.account(id: account.id)?.deletedNotionPageIDs == ["page-1"])
        #expect(changes == [.expenseDeleted(accountID: account.id, expenseID: expense.id, notionPageID: "page-1")])
    }

    @Test func deletingACategoryUncategorisesItsExpenses() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let food = account.categories[0]
        store.saveExpense(Expense(title: "Lunch", amount: 10, categoryID: food.id), in: account.id)
        store.deleteCategory(food.id, in: account.id)
        #expect(store.account(id: account.id)?.expenses.first?.categoryID == nil)
    }

    @Test func deletingTheSelectedAccountSelectsTheNext() {
        let store = KeaserStore(file: nil)
        let first = store.createAccount(name: "One")
        let second = store.createAccount(name: "Two")
        store.deleteAccount(second.id)
        #expect(store.selectedAccount?.id == first.id)
    }

    @Test func roundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "keaser-\(UUID().uuidString)/database.json")
        let file = DatabaseFile(url: url)
        let store = KeaserStore(file: file)
        let account = store.createAccount(name: "Personal")
        store.saveExpense(Expense(title: "Coffee", amount: Decimal(string: "4.50")!), in: account.id)
        let reloaded = KeaserStore(file: file)
        #expect(reloaded.database == store.database)
    }

    @Test func anUnreadableFileIsMovedAsideNotLost() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "keaser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "database.json")
        try Data("not json".utf8).write(to: url)
        let database = DatabaseFile(url: url).load()
        #expect(database.accounts.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path())
        #expect(names.contains { $0.hasPrefix("database.unreadable-") })
    }

    @Test func moveMatchesSwiftUISemantics() {
        var items = ["a", "b", "c", "d"]
        items.keaserMove(fromOffsets: [0], toOffset: 3)
        #expect(items == ["b", "c", "a", "d"])
        items.keaserMove(fromOffsets: [3], toOffset: 0)
        #expect(items == ["d", "b", "c", "a"])
    }
}

struct LogicTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func weekHonoursFirstWeekday() throws {
        // Saturday 26 Sep 2026.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12)))
        var sunday = calendar
        sunday.firstWeekday = 1
        var monday = calendar
        monday.firstWeekday = 2
        let s = try #require(Period.thisWeek.interval(containing: now, calendar: sunday))
        let m = try #require(Period.thisWeek.interval(containing: now, calendar: monday))
        #expect(calendar.component(.day, from: s.start) == 20)
        #expect(calendar.component(.day, from: m.start) == 21)
        #expect(Period.allTime.interval(containing: now, calendar: calendar) == nil)
    }

    @Test func parsesAmounts() {
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        #expect(MoneyFormat.parse("20", locale: us) == 20)
        #expect(MoneyFormat.parse("$1,234.56", locale: us) == Decimal(string: "1234.56"))
        #expect(MoneyFormat.parse("1.234,56", locale: de) == Decimal(string: "1234.56"))
        #expect(MoneyFormat.parse("16,99", locale: de) == Decimal(string: "16.99"))
        #expect(MoneyFormat.parse("-5", locale: us) == nil)
        #expect(MoneyFormat.parse("1.2.3", locale: us) == nil)
        #expect(MoneyFormat.parse("", locale: us) == nil)
    }

    @Test func formatsMoney() {
        #expect(MoneyFormat.string(20, currencyCode: "USD", locale: Locale(identifier: "en_US")) == "$20.00")
    }

    @Test func trialCountsDownInWholeDays() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(ProEntitlement.trialDaysRemaining(trialStart: nil, now: start) == nil)
        #expect(ProEntitlement.trialDaysRemaining(trialStart: start, now: start.addingTimeInterval(60)) == 7)
        #expect(ProEntitlement.trialDaysRemaining(trialStart: start, now: start.addingTimeInterval(86_400 * 6.5)) == 1)
        #expect(ProEntitlement.trialDaysRemaining(trialStart: start, now: start.addingTimeInterval(86_400 * 8)) == 0)
    }

    @Test func demoDataIsDeterministic() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let a = DemoData.database(.demo, now: now, calendar: calendar).accounts[0].expenses
        let b = DemoData.database(.demo, now: now, calendar: calendar).accounts[0].expenses
        #expect(a.map(\.title) == b.map(\.title))
        #expect(a.map(\.amount) == b.map(\.amount))
        #expect(a.count > 100)
    }
}
