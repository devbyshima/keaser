import Foundation
import Testing
@testable import KeaserKit

/// A stand-in for the on-device model: answers `answer` after `delay`,
/// within the caller's budget like the real one, and records what it was
/// asked.
@MainActor
final class FakeCategoryModel: CategoryModel {
    var isReady = true
    var answer: String?
    var delay: Duration
    private(set) var asked: [String] = []
    private(set) var prompts: [CategoryPrompt] = []
    private(set) var prewarmed: [CategoryPrompt] = []

    init(_ answer: String?, delay: Duration = .zero) {
        self.answer = answer
        self.delay = delay
    }

    func prewarm(_ prompt: CategoryPrompt) {
        prewarmed.append(prompt)
    }

    func category(for title: String, in prompt: CategoryPrompt, within budget: Duration) async -> String? {
        asked.append(title)
        prompts.append(prompt)
        return await Deadline.value(within: budget) { [delay, answer] in
            try? await Task.sleep(for: delay)
            return answer
        }
    }
}

@MainActor
struct IntelligenceSmartLabelsTests {
    private let account = Account(name: "Personal")
    private func category(_ name: String) -> UUID { account.categories.first { $0.name == name }!.id }
    private func method(_ name: String) -> UUID { account.paymentMethods.first { $0.name == name }!.id }

    @Test func anUnknownTitleTakesTheModelsCategory() async {
        let model = FakeCategoryModel("Health")
        let guess = await SmartLabels.guess(for: "Watsons", in: account, model: model, budget: .seconds(1))
        #expect(guess == .init(categoryID: category("Health"), paymentMethodID: method("Cash")))
        #expect(model.asked == ["Watsons"])
        #expect(model.prompts == [CategoryPrompt(categories: account.categories)])
    }

    @Test func aTitleTheRulesOrHistoryKnowNeverAsks() async {
        let model = FakeCategoryModel("Health")
        #expect(await SmartLabels.guess(for: "Lunch", in: account, model: model, budget: .seconds(1)).categoryID == category("Food & Drinks"))

        var known = account
        known.expenses = [Expense(title: "Watsons", amount: 4, categoryID: category("Shopping"))]
        #expect(await SmartLabels.guess(for: "watsons", in: known, model: model, budget: .seconds(1)).categoryID == category("Shopping"))
        #expect(model.asked.isEmpty)
    }

    @Test func theExpenseBeingEditedIsLeftOut() async {
        var edited = account
        let own = Expense(title: "Watsons", amount: 4, categoryID: category("Shopping"))
        edited.expenses = [own]
        let model = FakeCategoryModel("Health")
        let guess = await SmartLabels.guess(for: "Watsons", in: edited, excluding: own.id, model: model, budget: .seconds(1))
        #expect(guess.categoryID == category("Health"))
        #expect(model.asked == ["Watsons"])
    }

    @Test func withoutHelpItIsExactlyTheRuleGuess() async {
        let off = FakeCategoryModel("Health")
        off.isReady = false
        let models: [FakeCategoryModel?] = [
            nil, off, FakeCategoryModel("Health", delay: .seconds(5)), FakeCategoryModel("Pets"), FakeCategoryModel(nil),
        ]
        for model in models {
            #expect(await SmartLabels.guess(for: "Watsons", in: account, model: model, budget: .milliseconds(100)) == .init())
        }
        #expect(off.asked.isEmpty)
    }

    @Test func aSlowModelIsNotWaitedFor() async {
        let slow = FakeCategoryModel("Health", delay: .seconds(10))
        let start = ContinuousClock.now
        _ = await SmartLabels.guess(for: "Watsons", in: account, model: slow, budget: .milliseconds(100))
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func theModelBeatsARuleOnACategoryThePersonMade() async {
        let mine = Account(name: "Family", categories: ["Fun", "Subscriptions"].map { ExpenseCategory(name: $0, symbol: "tag") })
        let model = FakeCategoryModel("Subscriptions")
        let guess = await SmartLabels.guess(for: "Netflix", in: mine, model: model, budget: .seconds(1))
        #expect(guess.categoryID == mine.categories[1].id)
        #expect(model.asked == ["Netflix"])
    }

    @Test func modelCategoryNameIsAskedOnlyWhenWanted() async {
        let model = FakeCategoryModel("Health")
        #expect(await SmartLabels.modelCategoryName(for: "Watsons", in: account, model: model, budget: .seconds(1)) == "Health")
        #expect(await SmartLabels.modelCategoryName(for: "Taxi", in: account, model: model, budget: .seconds(1)) == nil)
        #expect(await SmartLabels.modelCategoryName(for: "Watsons", in: Account(name: "Empty", categories: []), model: model, budget: .seconds(1)) == nil)
        #expect(model.asked == ["Watsons"])
    }

    @Test func prewarmingNeedsAReadyModelAndCategories() {
        let model = FakeCategoryModel("Health")
        SmartLabels.prewarm(model, for: account)
        SmartLabels.prewarm(model, for: Account(name: "Empty", categories: []))
        model.isReady = false
        SmartLabels.prewarm(model, for: account)
        SmartLabels.prewarm(nil, for: account)
        #expect(model.prewarmed == [CategoryPrompt(categories: account.categories)])
    }

    @Test func theBudgetsAreShort() {
        #expect(SmartLabels.editorBudget == .seconds(2))
        #expect(SmartLabels.intentBudget == .milliseconds(1500))
    }
}

@MainActor
struct IntelligenceWalletTests {
    private let account = Account(name: "Personal")
    private func category(_ name: String) -> UUID { account.categories.first { $0.name == name }!.id }
    private func method(_ name: String) -> UUID { account.paymentMethods.first { $0.name == name }!.id }

    private func wallet(
        _ merchant: String,
        card: String? = nil,
        in account: Account? = nil,
        suggestions: Bool = true,
        model: FakeCategoryModel?
    ) async -> Expense {
        await QuickLog.walletExpense(
            merchant: merchant, amount: 5, card: card, in: account ?? self.account,
            suggestionsEnabled: suggestions, model: model, budget: .milliseconds(200)
        )
    }

    @Test func aNewMerchantGetsTheModelsCategoryAndKeepsTheCard() async {
        let model = FakeCategoryModel("Health")
        let expense = await wallet(" Watsons ", card: "Debit Mastercard", model: model)
        #expect(expense.title == "Watsons")
        #expect(expense.categoryID == category("Health"))
        #expect(expense.paymentMethodID == method("Debit Card"))
        #expect(model.asked == ["Watsons"])
    }

    @Test func aRepeatMerchantIsFiledLikeLastTime() async {
        var known = account
        known.expenses = [Expense(title: "Watsons", amount: 3, categoryID: category("Shopping"), paymentMethodID: method("Cash"))]
        let model = FakeCategoryModel("Health")
        let expense = await wallet("WATSONS", in: known, model: model)
        #expect(expense.categoryID == category("Shopping"))
        #expect(expense.paymentMethodID == method("Cash"))
        #expect(model.asked.isEmpty)
    }

    @Test func aMerchantTheRulesKnowNeverAsks() async {
        let model = FakeCategoryModel("Health")
        let expense = await wallet("Blue Bottle Coffee", model: model)
        #expect(expense.categoryID == category("Food & Drinks"))
        // Only the card or the last expense choose the method.
        #expect(expense.paymentMethodID == nil)
        #expect(model.asked.isEmpty)
    }

    @Test func noHelpLeavesTheCategoryEmpty() async {
        #expect(await wallet("Watsons", model: nil).categoryID == nil)
        #expect(await wallet("Watsons", model: FakeCategoryModel("Health", delay: .seconds(5))).categoryID == nil)
        #expect(await wallet("Watsons", model: FakeCategoryModel(nil)).categoryID == nil)
    }

    @Test func suggestionsOffOrNoMerchantNeverAsk() async {
        let model = FakeCategoryModel("Health")
        #expect(await wallet("Watsons", suggestions: false, model: model).categoryID == nil)
        #expect(await wallet("Blue Bottle Coffee", suggestions: false, model: model).categoryID == nil)
        let blank = await wallet("  ", model: model)
        #expect(blank.title == QuickLog.defaultTitle)
        #expect(blank.categoryID == nil)
        #expect(model.asked.isEmpty)
    }
}

@MainActor
struct IntelligenceDeadlineTests {
    @Test func aFastResultArrives() async {
        #expect(await Deadline.value(within: .seconds(1)) { "done" } == "done")
        #expect(await Deadline.value(within: .seconds(1)) { () -> String? in nil } == nil)
    }

    @Test func aSlowResultIsDroppedAtTheDeadline() async {
        let start = ContinuousClock.now
        let result = await Deadline.value(within: .milliseconds(50)) { () -> String? in
            try? await Task.sleep(for: .seconds(10))
            return "late"
        }
        #expect(result == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func itReturnsAtTheDeadlineEvenIfTheWorkIgnoresCancellation() async {
        let start = ContinuousClock.now
        let result = await Deadline.value(within: .milliseconds(50)) { () -> String? in
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { done.resume() }
            }
            return "late"
        }
        #expect(result == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func cancellingTheCallerStopsTheWait() async {
        let start = ContinuousClock.now
        let wait = Task { @MainActor in
            await Deadline.value(within: .seconds(10)) { () -> String? in
                try? await Task.sleep(for: .seconds(10))
                return "late"
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        wait.cancel()
        #expect(await wait.value == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func noBudgetMeansNoWait() async {
        let model = FakeCategoryModel("Health")
        let result = await Deadline.value(within: .zero) { () -> String? in
            await model.category(for: "Watsons", in: CategoryPrompt(categories: ExpenseCategory.defaults())!, within: .seconds(1))
        }
        #expect(result == nil)
        #expect(model.asked.isEmpty)
    }
}
