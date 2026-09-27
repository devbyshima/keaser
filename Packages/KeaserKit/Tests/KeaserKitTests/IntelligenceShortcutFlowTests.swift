import Foundation
import Testing
@testable import KeaserKit

/// The Add Expense shortcut asking the on-device model for the category of
/// a title nothing else knows, through `start(model:budget:)` and
/// `next(after:answer:model:budget:)`.
@MainActor
struct IntelligenceShortcutFlowTests {
    private let budget = Duration.milliseconds(300)

    private func category(_ name: String, in account: Account) -> UUID {
        account.categories.first { $0.name == name }!.id
    }

    private func method(_ name: String, in account: Account) -> UUID {
        account.paymentMethods.first { $0.name == name }!.id
    }

    private func flow(
        _ accounts: [Account],
        title: String? = nil,
        amount: Decimal? = nil,
        category: ShortcutFlow.Label? = nil,
        suggestions: Bool = true
    ) -> ShortcutFlow {
        ShortcutFlow(
            accounts: accounts,
            accountID: accounts[0].id,
            title: title,
            amount: amount,
            category: category,
            suggestionsEnabled: suggestions
        )!
    }

    @Test func aSuppliedUnknownTitleSkipsTheCategoryQuestion() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health")
        var f = flow([account], title: "Watsons", amount: 5)
        #expect(await f.start(model: model, budget: budget) == nil)
        #expect(f.categoryID == category("Health", in: account))
        // A recognised title in a fresh account is paid in Cash, as in the reference.
        #expect(f.paymentMethodID == method("Cash", in: account))
        #expect(model.asked == ["Watsons"])
    }

    @Test func withoutTheModelTheCategoryIsAsked() async {
        let account = Account(name: "Personal")
        var plain = flow([account], title: "Watsons", amount: 5)
        #expect(await plain.start(model: nil, budget: budget) == .category)

        for model in [FakeCategoryModel(nil), FakeCategoryModel("Health", delay: .seconds(5)), FakeCategoryModel("Pets")] {
            var f = flow([account], title: "Watsons", amount: 5)
            #expect(await f.start(model: model, budget: budget) == .category)
            #expect(f.categoryID == nil)
        }
    }

    @Test func theModelIsAskedOnlyWhenTheMoveReachesTheCategory() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health")
        var f = flow([account])
        #expect(await f.start(model: model, budget: budget) == .title)
        #expect(await f.next(after: .title, answer: .title(" Watsons "), model: model, budget: budget) == .amount)
        #expect(model.asked.isEmpty)
        #expect(await f.next(after: .amount, answer: .amount(12), model: model, budget: budget) == nil)
        #expect(model.asked == ["Watsons"])
        #expect(f.categoryID == category("Health", in: account))
        #expect(f.expense?.title == "Watsons")
    }

    @Test func itAsksAboutTheAccountPicked() async {
        let personal = Account(name: "Personal")
        let family = Account(name: "Family", categories: ["Kids", "Pets"].map { ExpenseCategory(name: $0, symbol: "tag") })
        let model = FakeCategoryModel("Kids")
        var f = flow([personal, family], title: "Diapers", amount: 9)
        #expect(await f.start(model: model, budget: budget) == .account)
        #expect(await f.next(after: .account, answer: .account(family.id), model: model, budget: budget) == nil)
        #expect(model.prompts == [CategoryPrompt(categories: family.categories)])
        #expect(f.categoryID == family.categories[0].id)
    }

    @Test func aTitleIsNeverAskedAboutTwice() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health", delay: .seconds(5))
        var f = flow([account], title: "Watsons")
        #expect(await f.start(model: model, budget: budget) == .amount)
        #expect(await f.next(after: .amount, answer: .amount(5), model: model, budget: budget) == .category)
        #expect(await f.next(after: .category, answer: .goBack, model: model, budget: budget) == .amount)
        #expect(await f.next(after: .amount, answer: .amount(6), model: model, budget: budget) == .category)
        #expect(model.asked == ["Watsons"])
    }

    @Test func goingBackFromPaymentDoesNotAsk() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health")
        var f = flow([account], title: "Watsons", amount: 5)
        #expect(await f.start(model: model, budget: budget) == nil)
        model.answer = "Shopping"
        #expect(await f.next(after: .paymentMethod, answer: .goBack, model: model, budget: budget) == .category)
        #expect(model.asked == ["Watsons"])
    }

    @Test func knownTitlesSuppliedLabelsAndSuggestionsOffNeverAsk() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health")

        var known = flow([account], title: "Lunch", amount: 5)
        #expect(await known.start(model: model, budget: budget) == nil)
        #expect(known.categoryID == category("Food & Drinks", in: account))

        let shopping = account.categories[1]
        var supplied = flow([account], title: "Watsons", amount: 5, category: .init(id: shopping.id, name: shopping.name))
        #expect(await supplied.start(model: model, budget: budget) == .paymentMethod)
        #expect(supplied.categoryID == shopping.id)

        var off = flow([account], title: "Watsons", amount: 5, suggestions: false)
        #expect(await off.start(model: model, budget: budget) == .category)

        #expect(model.asked.isEmpty)
        #expect(model.prewarmed.isEmpty)
    }

    @Test func itLoadsTheModelWhileTheTitleIsStillToCome() async {
        let account = Account(name: "Personal")
        let model = FakeCategoryModel("Health")
        var f = flow([account])
        _ = await f.start(model: model, budget: budget)
        #expect(model.prewarmed == [CategoryPrompt(categories: account.categories)])
    }

    @Test func withoutAModelTheAsyncStepsMatchThePlainOnes() async {
        let accounts = [Account(name: "Personal"), Account(name: "Business")]
        var plain = flow(accounts)
        var viaModel = flow(accounts)
        let first = plain.start()
        #expect(await viaModel.start(model: nil, budget: budget) == first)
        let answers: [(ShortcutFlow.Step, ShortcutFlow.Answer)] = [
            (.title, .title("Watsons")), (.amount, .amount(3)), (.account, .account(accounts[1].id)),
        ]
        for (step, answer) in answers {
            let expected = plain.next(after: step, answer: answer)
            #expect(await viaModel.next(after: step, answer: answer, model: nil, budget: budget) == expected)
        }
        #expect(plain.title == viaModel.title)
        #expect(plain.amount == viaModel.amount)
        #expect(plain.accountID == viaModel.accountID)
        #expect(plain.categoryID == viaModel.categoryID)
        #expect(plain.paymentMethodID == viaModel.paymentMethodID)
        #expect(viaModel.modelAnswer == nil)
    }
}
