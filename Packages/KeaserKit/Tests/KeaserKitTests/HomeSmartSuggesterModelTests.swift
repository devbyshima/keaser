import Foundation
import Testing
@testable import KeaserKit

/// How the on-device model's category ranks against the person's history
/// and the word rules, and the rules that used to beat a right answer.
struct HomeSmartSuggesterModelTests {
    private let categories = ExpenseCategory.defaults()
    private let methods = PaymentMethod.defaults()
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func category(_ name: String) -> UUID { categories.first { $0.name == name }!.id }
    private func method(_ name: String) -> UUID { methods.first { $0.name == name }!.id }

    private func logged(_ title: String, _ categoryName: String, _ methodName: String, daysAgo: Double) -> Expense {
        let date = base.addingTimeInterval(-daysAgo * 86_400)
        return Expense(title: title, amount: 10, categoryID: category(categoryName), paymentMethodID: method(methodName), date: date, createdAt: date)
    }

    private func guess(
        _ title: String,
        history: [Expense] = [],
        model: UUID?,
        in labels: [ExpenseCategory]? = nil
    ) -> SmartSuggester.LabelGuess {
        SmartSuggester.guessLabels(for: title, categories: labels ?? categories, paymentMethods: methods, history: history, modelCategoryID: model)
    }

    private func wants(_ title: String, history: [Expense] = [], in labels: [ExpenseCategory]? = nil) -> Bool {
        SmartSuggester.wantsModelGuess(for: title, categories: labels ?? categories, history: history)
    }

    @Test func withoutTheModelNothingChanges() {
        #expect(guess("Outing", model: nil) == .init(categoryID: category("Travel"), paymentMethodID: method("Cash")))
        #expect(guess("Watsons", model: nil) == .init())
    }

    @Test func historyBeatsTheModel() {
        let history = [logged("Coffee", "Entertainment", "Debit Card", daysAgo: 1)]
        let result = guess("Coffee beans", history: history, model: category("Food & Drinks"))
        #expect(result == .init(categoryID: category("Entertainment"), paymentMethodID: method("Debit Card")))
    }

    @Test func aWordRuleOnABuiltInCategoryBeatsTheModel() {
        #expect(guess("Netflix", model: category("Services")).categoryID == category("Entertainment"))
        #expect(guess("Outing", model: category("Entertainment")) == .init(categoryID: category("Travel"), paymentMethodID: method("Cash")))
        #expect(guess("LUNCH", model: category("Health")) == .init(categoryID: category("Food & Drinks"), paymentMethodID: method("Cash")))
    }

    @Test func theModelFilesATitleNothingElseKnows() {
        // A fresh account pays a recognised title in Cash, as for the rules.
        #expect(guess("Watsons", model: category("Health")) == .init(categoryID: category("Health"), paymentMethodID: method("Cash")))
        // With history, the usual method wins; the model never picks one.
        let history = [logged("Groceries", "Food & Drinks", "Debit Card", daysAgo: 1)]
        #expect(guess("Watsons", history: history, model: category("Health")) == .init(
            categoryID: category("Health"), paymentMethodID: method("Debit Card")
        ))
    }

    @Test func theModelBeatsAWordRuleOnACategoryThePersonMade() {
        let mine = ["Fun", "Subscriptions"].map { ExpenseCategory(name: $0, symbol: "tag") }
        #expect(guess("Netflix", model: mine[1].id, in: mine).categoryID == mine[1].id)
        #expect(guess("Netflix", model: nil, in: mine).categoryID == mine[0].id)
    }

    @Test func aModelCategoryTheAccountLacksIsIgnored() {
        let mine = ["Fun", "Subscriptions"].map { ExpenseCategory(name: $0, symbol: "tag") }
        #expect(guess("Netflix", model: UUID(), in: mine).categoryID == mine[0].id)
        #expect(guess("Watsons", model: UUID()) == .init())
    }

    @Test func theModelIsWantedOnlyWhenNothingSettlesTheCategory() {
        let mine = ["Fun", "Subscriptions"].map { ExpenseCategory(name: $0, symbol: "tag") }
        #expect(!wants("Lunch"))
        #expect(!wants("Uber to airport"))
        #expect(wants("Watsons"))
        #expect(wants("Zxqv"))
        #expect(!wants("Watsons shampoo", history: [logged("Watsons", "Health", "Cash", daysAgo: 1)]))
        #expect(!wants("   "))
        #expect(!wants("Watsons", in: []))
        // A rule on a category the person made can still be improved on.
        #expect(wants("Netflix", in: mine))
    }

    @Test func historyWithoutACategoryStillWantsTheModel() {
        let uncategorised = Expense(title: "Watsons", amount: 5, paymentMethodID: method("Cash"), date: base, createdAt: base)
        #expect(wants("Watsons", history: [uncategorised]))
    }

    @Test func theExpenseBeingEditedDoesNotTeachItself() {
        let own = logged("Watsons", "Health", "Cash", daysAgo: 1)
        #expect(!SmartSuggester.wantsModelGuess(for: "Watsons", categories: categories, history: [own]))
        #expect(SmartSuggester.wantsModelGuess(for: "Watsons", categories: categories, history: [own], excluding: own.id))
    }

    // MARK: Rules the model evaluation showed were wrong

    @Test func uberEatsIsFoodNotATaxi() {
        #expect(guess("Uber Eats", model: nil) == .init(categoryID: category("Food & Drinks"), paymentMethodID: method("Cash")))
        #expect(guess("uber eats order", model: nil).categoryID == category("Food & Drinks"))
        #expect(guess("Uber", model: nil).categoryID == category("Transportation"))
        #expect(guess("Uber to airport", model: nil).categoryID == category("Transportation"))
        #expect(guess("Eats", model: nil).categoryID == nil)
    }

    @Test func aGasBillIsAServiceButGasIsFuel() {
        #expect(guess("Gas bill", model: nil).categoryID == category("Services"))
        #expect(guess("GAS BILLS", model: nil).categoryID == category("Services"))
        #expect(guess("Gas", model: nil).categoryID == category("Transportation"))
        #expect(guess("Gas station", model: nil).categoryID == category("Transportation"))
        #expect(guess("Bill", model: nil).categoryID == nil)
    }

    @Test func aPhraseMustBeInARow() {
        #expect(guess("Eats at Uber HQ", model: nil).categoryID == category("Transportation"))
    }
}
