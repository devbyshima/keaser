import Foundation
import Testing
@testable import KeaserKit

struct HomeSmartSuggesterTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func expense(_ title: String, _ amount: Decimal, daysAgo: Double) -> Expense {
        let date = base.addingTimeInterval(-daysAgo * 86_400)
        return Expense(title: title, amount: amount, date: date, createdAt: date)
    }

    private var history: [Expense] {
        [
            expense("Groceries", 80, daysAgo: 1),
            expense("Gas", 45, daysAgo: 2),
            expense("Groceries", 60, daysAgo: 5),
            expense("Big grocery run", 150, daysAgo: 3),
            expense("Gym membership", 40, daysAgo: 10),
            expense("Café Gris", 6, daysAgo: 4),
            expense("Outing", 20, daysAgo: 0),
        ]
    }

    @Test func prefixMatchesComeBeforeContainsMatches() {
        let result = SmartSuggester.suggestions(for: "gr", in: history)
        #expect(result.map(\.title) == ["Groceries", "Big grocery run", "Café Gris"])
    }

    @Test func eachTitleAppearsOnceWithItsMostRecentAmount() {
        let result = SmartSuggester.suggestions(for: "groc", in: history)
        #expect(result.map(\.title) == ["Groceries", "Big grocery run"])
        #expect(result.first?.amount == 80)
    }

    @Test func limitsToThreeByDefault() {
        let result = SmartSuggester.suggestions(for: "g", in: history)
        #expect(result.count == 3)
        #expect(result.map(\.title) == ["Groceries", "Gas", "Gym membership"])
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(SmartSuggester.suggestions(for: "CAFE", in: history).map(\.title) == ["Café Gris"])
        #expect(SmartSuggester.suggestions(for: "gris", in: history).map(\.title) == ["Café Gris"])
    }

    @Test func emptyQueryOrNoMatchSuggestsNothing() {
        #expect(SmartSuggester.suggestions(for: "", in: history).isEmpty)
        #expect(SmartSuggester.suggestions(for: "   ", in: history).isEmpty)
        #expect(SmartSuggester.suggestions(for: "xyz", in: history).isEmpty)
    }

    @Test func leavesOutTheExpenseBeingEdited() {
        let items = history
        let outing = items.first { $0.title == "Outing" }!
        #expect(SmartSuggester.suggestions(for: "out", in: items, excluding: outing.id).isEmpty)
        #expect(SmartSuggester.suggestions(for: "out", in: items).count == 1)
    }

    // MARK: Guessing labels

    private let categories = ExpenseCategory.defaults()
    private let methods = PaymentMethod.defaults()

    private func category(_ name: String) -> UUID { categories.first { $0.name == name }!.id }
    private func method(_ name: String) -> UUID { methods.first { $0.name == name }!.id }

    private func guess(_ title: String, history: [Expense] = [], excluding: UUID? = nil) -> SmartSuggester.LabelGuess {
        SmartSuggester.guessLabels(for: title, categories: categories, paymentMethods: methods, history: history, excluding: excluding)
    }

    private func logged(_ title: String, _ categoryName: String?, _ methodName: String?, daysAgo: Double) -> Expense {
        var item = expense(title, 10, daysAgo: daysAgo)
        item.categoryID = categoryName.map(category)
        item.paymentMethodID = methodName.map(method)
        return item
    }

    /// The recording: a new account, "Outing" typed, and the editor fills in
    /// Travel and Cash on its own.
    @Test func guessesFromTheTitleInANewAccount() {
        #expect(guess("Outing") == .init(categoryID: category("Travel"), paymentMethodID: method("Cash")))
        #expect(guess("Morning coffee").categoryID == category("Food & Drinks"))
        #expect(guess("Weekly groceries").categoryID == category("Food & Drinks"))
        #expect(guess("Uber home").categoryID == category("Transportation"))
        #expect(guess("Pharmacy").categoryID == category("Health"))
        #expect(guess("Netflix") == .init(categoryID: category("Entertainment"), paymentMethodID: method("Credit Card")))
        #expect(guess("Rent").paymentMethodID == method("Bank Transfer"))
    }

    @Test func aTieBetweenKeywordsGoesToTheFirstWord() {
        #expect(guess("Train ticket").categoryID == category("Transportation"))
        #expect(guess("Movie ticket").categoryID == category("Entertainment"))
    }

    @Test func shortKeywordsMatchWholeWordsOnly() {
        #expect(guess("Barber").categoryID == category("Services"))
        #expect(guess("Bar tab").categoryID == category("Food & Drinks"))
    }

    @Test func unknownTitleGuessesNothingWithoutHistory() {
        #expect(guess("Zxqv") == .init())
        #expect(guess("   ") == .init())
    }

    @Test func pastExpensesWithASharedWordWinOverKeywords() {
        let history = [
            logged("Coffee with Sam", "Entertainment", "Debit Card", daysAgo: 1),
            logged("Coffee", "Entertainment", "Debit Card", daysAgo: 3),
            logged("Coffees", "Food & Drinks", "Cash", daysAgo: 2),
        ]
        #expect(guess("Coffee beans", history: history) == .init(categoryID: category("Entertainment"), paymentMethodID: method("Debit Card")))
    }

    @Test func aTieInHistoryGoesToTheMostRecentUse() {
        let history = [
            logged("Lunch", "Food & Drinks", "Cash", daysAgo: 5),
            logged("Lunch", "Shopping", "E-Wallet", daysAgo: 1),
        ]
        #expect(guess("Lunch", history: history) == .init(categoryID: category("Shopping"), paymentMethodID: method("E-Wallet")))
    }

    @Test func paymentFallsBackToTheMethodUsedMostOften() {
        let history = [
            logged("Groceries", "Food & Drinks", "Debit Card", daysAgo: 1),
            logged("Gym", "Health", "Debit Card", daysAgo: 2),
            logged("Books", "Shopping", "Credit Card", daysAgo: 0),
        ]
        #expect(guess("Pharmacy", history: history) == .init(categoryID: category("Health"), paymentMethodID: method("Debit Card")))
        // A keyword still beats the habit.
        #expect(guess("Outing", history: history).paymentMethodID == method("Cash"))
    }

    @Test func onlyUsesLabelsTheAccountStillHas() {
        let gone = ExpenseCategory(name: "Old", symbol: "tag")
        var old = expense("Outing", 5, daysAgo: 1)
        old.categoryID = gone.id
        old.paymentMethodID = UUID()
        #expect(guess("Outing", history: [old]) == .init(categoryID: category("Travel"), paymentMethodID: method("Cash")))

        let custom = [ExpenseCategory(name: "Trips & Holidays", symbol: "airplane")]
        let result = SmartSuggester.guessLabels(for: "Hotel", categories: custom, paymentMethods: [], history: [])
        #expect(result == .init(categoryID: custom[0].id, paymentMethodID: nil))
        #expect(SmartSuggester.guessLabels(for: "Outing", categories: [], paymentMethods: [], history: []) == .init())
    }

    @Test func theExpenseBeingEditedDoesNotTeachItself() {
        let edited = logged("Outing", "Shopping", "Debit Card", daysAgo: 0)
        #expect(guess("Outing", history: [edited], excluding: edited.id) == .init(categoryID: category("Travel"), paymentMethodID: method("Cash")))
    }

    @Test func wordsMatchGiveOrTakeAnEnding() {
        #expect(SmartSuggester.wordsMatch("grocery", "groceries"))
        #expect(SmartSuggester.wordsMatch("coffee", "coffees"))
        #expect(!SmartSuggester.wordsMatch("bar", "barber"))
        #expect(!SmartSuggester.wordsMatch("book", "boots"))
    }
}
