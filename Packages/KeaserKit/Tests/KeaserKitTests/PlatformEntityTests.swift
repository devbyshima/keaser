import Foundation
import Testing
@testable import KeaserKit

private let utc = TimeZone(identifier: "UTC")!

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// Personal (selected) with three expenses and Business with one, in USD.
private func sampleDatabase() -> Database {
    var personal = Account(name: "Personal")
    let food = personal.categories.first { $0.name == "Food & Drinks" }!
    let cash = personal.paymentMethods.first { $0.name == "Cash" }!
    personal.expenses = [
        Expense(title: "Coffee", amount: Decimal(string: "4.50")!, categoryID: food.id, paymentMethodID: cash.id, date: day(2026, 9, 20), createdAt: day(2026, 9, 20)),
        Expense(title: "Café Latte", amount: 5, date: day(2026, 9, 25), createdAt: day(2026, 9, 25)),
        Expense(title: "Groceries", amount: 87, categoryID: food.id, date: day(2026, 9, 25), createdAt: day(2026, 9, 25, hour: 18)),
    ]
    var business = Account(name: "Business")
    business.expenses = [
        Expense(title: "Coffee with client", amount: 12, date: day(2026, 9, 26), createdAt: day(2026, 9, 26)),
    ]
    return Database(
        accounts: [personal, business],
        preferences: Preferences(currencyCode: "USD", selectedAccountID: personal.id)
    )
}

struct ExpenseSummaryTests {
    @Test func carriesTheNamesItIsFiledUnder() {
        let db = sampleDatabase()
        let personal = db.accounts[0]
        let coffee = personal.expenses[0]
        let summary = ExpenseSummary(coffee, in: personal, currencyCode: "USD")
        #expect(summary.id == coffee.id)
        #expect(summary.accountID == personal.id)
        #expect(summary.accountName == "Personal")
        #expect(summary.categoryName == "Food & Drinks")
        #expect(summary.paymentMethodName == "Cash")
        #expect(summary.symbol == "fork.knife")
        #expect(summary.keywords == ["Food & Drinks", "Cash", "Personal"])
    }

    @Test func uncategorisedExpenseShowsTheCard() {
        let db = sampleDatabase()
        let summary = ExpenseSummary(db.accounts[0].expenses[1], in: db.accounts[0], currencyCode: "USD")
        #expect(summary.categoryName == nil)
        #expect(summary.paymentMethodName == nil)
        #expect(summary.symbol == ExpenseCategory.fallbackSymbol)
        #expect(summary.keywords == ["Personal"])
    }

    @Test func subtitleIsAmountAndDay() {
        let db = sampleDatabase()
        let summary = ExpenseSummary(db.accounts[0].expenses[0], in: db.accounts[0], currencyCode: "USD")
        #expect(summary.subtitle(locale: Locale(identifier: "en_US"), timeZone: utc) == "$4.50 · Sep 20, 2026")
    }

    @Test func aLabelDeletedSinceIsLeftOut() {
        var db = sampleDatabase()
        let foodID = db.accounts[0].categories.first { $0.name == "Food & Drinks" }!.id
        db.accounts[0].categories.removeAll { $0.id == foodID }
        let summary = ExpenseSummary(db.accounts[0].expenses[0], in: db.accounts[0], currencyCode: "USD")
        #expect(summary.categoryName == nil)
        #expect(summary.symbol == ExpenseCategory.fallbackSymbol)
    }
}

struct EntityCatalogTests {
    @Test func allExpensesAreNewestFirstAcrossAccounts() {
        let titles = EntityCatalog.allExpenses(in: sampleDatabase()).map(\.title)
        // Same day: the later creation time comes first.
        #expect(titles == ["Coffee with client", "Groceries", "Café Latte", "Coffee"])
    }

    @Test func findsIDsInEveryAccountInTheOrderAsked() {
        let db = sampleDatabase()
        let business = db.accounts[1].expenses[0].id
        let coffee = db.accounts[0].expenses[0].id
        let found = EntityCatalog.expenses(withIDs: [coffee, UUID(), business, coffee], in: db)
        #expect(found.map(\.id) == [coffee, business])
        #expect(found[1].accountName == "Business")
    }

    @Test func recentIsCappedAtTheLimit() {
        let db = sampleDatabase()
        #expect(EntityCatalog.recentExpenses(in: db, limit: 2).map(\.title) == ["Coffee with client", "Groceries"])
        #expect(EntityCatalog.recentExpenses(in: db).count == 4)
        #expect(EntityCatalog.recentExpenses(in: db, limit: -1).isEmpty)
    }

    @Test func matchesTitlesIgnoringCaseAndAccents() {
        let db = sampleDatabase()
        #expect(EntityCatalog.expenses(matching: "  COFFEE ", in: db).map(\.title) == ["Coffee with client", "Coffee"])
        #expect(EntityCatalog.expenses(matching: "cafe", in: db).map(\.title) == ["Café Latte"])
        #expect(EntityCatalog.expenses(matching: "coffee", in: db, limit: 1).map(\.title) == ["Coffee with client"])
        #expect(EntityCatalog.expenses(matching: "   ", in: db).isEmpty)
        #expect(EntityCatalog.expenses(matching: "rent", in: db).isEmpty)
    }

    @Test func locatesTheAccountOfAnExpense() {
        let db = sampleDatabase()
        #expect(EntityCatalog.account(containingExpense: db.accounts[1].expenses[0].id, in: db)?.name == "Business")
        #expect(EntityCatalog.account(containingExpense: UUID(), in: db) == nil)
    }

    @Test func matchesAccountNames() {
        let db = sampleDatabase()
        #expect(EntityCatalog.accounts(matching: "bus", in: db).map(\.name) == ["Business"])
        #expect(EntityCatalog.accounts(matching: "s", in: db).map(\.name) == ["Personal", "Business"])
        #expect(EntityCatalog.accounts(matching: "", in: db).isEmpty)
    }

    @Test func labelsComeFromTheSelectedAccountFirst() {
        var db = sampleDatabase()
        db.accounts[1].categories.append(ExpenseCategory(name: "Food Truck", symbol: "truck.box"))
        // Personal (selected) has "Food & Drinks"; Business's extra match is not offered.
        #expect(EntityCatalog.categories(matching: "food", in: db).map(\.name) == ["Food & Drinks"])
        #expect(EntityCatalog.categories(matching: "food", in: db).first?.id == db.accounts[0].categories[0].id)
    }

    @Test func otherAccountsAreSearchedOncePerName() {
        var db = sampleDatabase()
        db.accounts[1].categories.append(ExpenseCategory(name: "Office", symbol: "building.2"))
        db.accounts.append(Account(name: "Side", categories: [ExpenseCategory(name: "office", symbol: "tray")]))
        #expect(EntityCatalog.categories(matching: "Offi", in: db).map(\.name) == ["Office"])
        #expect(EntityCatalog.paymentMethods(matching: "card", in: db).map(\.name) == ["Credit Card", "Debit Card"])
        #expect(EntityCatalog.paymentMethods(matching: "", in: db).isEmpty)
    }
}
