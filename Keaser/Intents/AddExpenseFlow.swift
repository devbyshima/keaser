import AppIntents
import Foundation
import KeaserKit
import SwiftUI

// The app's side of `AddExpenseIntent`, which is declared in
// KeaserWidgets/Shared so the Add Expense control can name it.

extension AddExpenseIntent {
    /// Asks for whatever the shortcut left empty, in the order `ShortcutFlow`
    /// decides, then shows the expense for confirmation when Settings >
    /// Shortcut asks for it, and saves. Returns the expense, so a shortcut
    /// can pass it on.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ExpenseEntity> & ProvidesDialog & ShowsSnippetView {
        let store = try IntentSupport.freshStore()
        let preferences = store.preferences
        let voiceOnly = isVoiceOnly
        var flow = try makeFlow(store: store)
        // Titles nothing else knows get their category from the on-device
        // model when it answers in time; otherwise the question is asked.
        let model = CategoryModels.current
        var step = await flow.start(model: model, budget: SmartLabels.intentBudget)
        while let current = step {
            let answer = try await ask(current, in: flow, currencyCode: preferences.currencyCode)
            step = await flow.next(after: current, answer: answer, model: model, budget: SmartLabels.intentBudget)
        }
        if preferences.shortcutConfirmsDetails {
            flow = try await confirm(flow, currencyCode: preferences.currencyCode, voiceOnly: voiceOnly)
        }

        // The questions may have taken a while: file the expense with the
        // account and labels as they are now.
        let latest = try IntentSupport.freshStore()
        guard var expense = flow.expense else { throw KeaserIntentError.invalidAmount }
        guard let account = latest.account(id: flow.account.id) else { throw KeaserIntentError.noAccount }
        expense.categoryID = account.category(id: expense.categoryID)?.id
        expense.paymentMethodID = account.paymentMethod(id: expense.paymentMethodID)?.id
        try await IntentSupport.save(expense, in: account, store: latest)
        let saved = latest.account(id: account.id)?.expenses.first { $0.id == expense.id } ?? expense
        let entity = ExpenseEntity(ExpenseSummary(saved, in: account, currencyCode: latest.preferences.currencyCode))

        if voiceOnly {
            // Nothing is shown, so the answer is said in full.
            let spoken = QuickLog.confirmation(amount: saved.amount, currencyCode: latest.preferences.currencyCode, accountName: account.name, title: saved.title)
            return .result(value: entity, dialog: "\(spoken)", view: EmptyView())
        }
        if preferences.shortcutConfirmsDetails {
            // Continue was the last word: the shortcut ends there, back where
            // it started, with nothing more to say or show.
            var quiet = IntentResultContainer.result(value: entity, dialog: "", view: EmptyView())
            quiet.dialog = nil
            return quiet
        }
        let card = IntentSupport.card(for: saved, in: account, store: latest)
        return .result(value: entity, dialog: IntentSupport.addedDialog, view: ExpenseCardView(card: card))
    }

    /// Whether Siri is answering with no screen to show the card on
    /// (iOS 27; earlier systems do not say).
    @MainActor
    private var isVoiceOnly: Bool {
        if #available(iOS 27.0, *) { return systemContext.isVoiceOnly }
        return false
    }

    /// The flow with everything the shortcut supplied. A supplied amount
    /// that is not a positive amount of money is refused, as before.
    @MainActor
    private func makeFlow(store: KeaserStore) throws -> ShortcutFlow {
        let preferences = store.preferences
        let target = try IntentSupport.account(account, in: store)
        var suppliedAmount: Decimal?
        if let amount {
            guard let value = QuickLog.amount(fromDecimal: amount.amount, currencyCode: preferences.currencyCode) else {
                throw KeaserIntentError.invalidAmount
            }
            suppliedAmount = value
        }
        let now = Date.now
        guard let flow = ShortcutFlow(
            accounts: store.accounts,
            accountID: target.id,
            accountSupplied: account != nil,
            title: expenseTitle,
            amount: suppliedAmount,
            category: category.map { ShortcutFlow.Label(id: $0.id, name: $0.name) },
            paymentMethod: paymentMethod.map { ShortcutFlow.Label(id: $0.id, name: $0.name) },
            goBackEnabled: preferences.shortcutGoBackEnabled,
            suggestionsEnabled: preferences.shortcutSmartSuggestionsEnabled,
            date: date ?? now,
            createdAt: now
        ) else { throw KeaserIntentError.noAccount }
        return flow
    }

    /// Asks one question. Lists show names only and end with Go Back when
    /// the flow offers it. Cancelling any of them ends the shortcut.
    @MainActor
    private func ask(_ step: ShortcutFlow.Step, in flow: ShortcutFlow, currencyCode: String) async throws -> ShortcutFlow.Answer {
        let goBack = flow.offersGoBack(at: step)
        switch step {
        case .title:
            return .title(try await $expenseTitle.requestValue("What is the expense about?"))
        case .amount:
            var dialog: IntentDialog = "What is the amount?"
            while true {
                let typed = try await $amount.requestValue(dialog)
                if let value = QuickLog.amount(fromDecimal: typed.amount, currencyCode: currencyCode) {
                    return .amount(value)
                }
                dialog = IntentDialog(KeaserIntentError.invalidAmount.localizedStringResource)
            }
        case .account:
            let choices = flow.accounts.map { AccountEntity($0) } + (goBack ? [.goBack] : [])
            let picked = try await $account.requestDisambiguation(among: choices, dialog: "Which account?")
            return picked.id == ShortcutFlow.goBackID ? .goBack : .account(picked.id)
        case .category:
            let choices = flow.account.categories.map { CategoryEntity($0, showsSymbol: false) } + (goBack ? [.goBack] : [])
            let picked = try await $category.requestDisambiguation(among: choices, dialog: "Which category?")
            return picked.id == ShortcutFlow.goBackID ? .goBack : .category(picked.id)
        case .paymentMethod:
            let choices = flow.account.paymentMethods.map { PaymentMethodEntity($0, showsSymbol: false) } + (goBack ? [.goBack] : [])
            let picked = try await $paymentMethod.requestDisambiguation(among: choices, dialog: "Which payment method?")
            return picked.id == ShortcutFlow.goBackID ? .goBack : .paymentMethod(picked.id)
        }
    }

    /// Shows the expense with Cancel and Continue; throws when cancelled.
    /// From iOS 26 the card is interactive (see `ExpenseCardView`) and the
    /// flow comes back with whatever was changed on it. With nothing shown
    /// (Siri by voice alone) every detail is asked out loud instead.
    @MainActor
    private func confirm(_ flow: ShortcutFlow, currencyCode: String, voiceOnly: Bool) async throws -> ShortcutFlow {
        if voiceOnly, let expense = flow.expense {
            let question = QuickLog.confirmationQuestion(for: expense, in: flow.account, currencyCode: currencyCode)
            try await requestConfirmation(actionName: .add, dialog: "\(question)")
            return flow
        }
        let dialog: IntentDialog = "Confirm expense details:"
        if #available(iOS 26.0, *) {
            let drafts = AddExpenseDrafts.shared
            let session = drafts.open(flow, currencyCode: currencyCode)
            defer { drafts.close(session) }
            try await requestConfirmation(actionName: .continue, dialog: dialog, snippetIntent: ExpenseCardSnippetIntent(session: session))
            return drafts.flow(session) ?? flow
        } else {
            guard let expense = flow.expense else { return flow }
            let card = ExpenseCardView(card: ShortcutCard(expense: expense, in: flow.account, currencyCode: currencyCode))
            try await requestConfirmation(actionName: .continue, dialog: dialog) { @Sendable in card }
            return flow
        }
    }
}
