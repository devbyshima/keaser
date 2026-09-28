import AppIntents
import Foundation
import KeaserKit
import SwiftUI

/// "Log Wallet Transaction": the action for a Shortcuts automation on the
/// Wallet "When I tap" trigger, which passes the merchant, the amount as text
/// and the card name. It finishes on the same "Successfully added expense"
/// card as the Add Expense shortcut, with no confirmation: it is an
/// automation.
struct LogWalletTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Wallet Transaction"
    static var description: IntentDescription {
        IntentDescription("Logs an Apple Wallet payment as an expense, filed like the last one at the same merchant.")
    }

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Amount", description: "The amount as Wallet passes it, such as \"$4.50\".")
    var amount: String

    @Parameter(title: "Card", description: "Matched to a payment method with the same name.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentSupport.freshStore()
        let target = try IntentSupport.account(nil, in: store)
        guard let value = QuickLog.amount(from: amount, currencyCode: store.preferences.currencyCode) else {
            throw KeaserIntentError.invalidAmount
        }
        // A new merchant gets Smart Suggestions' category, from the on-device
        // model too when it answers in time. This is a Shortcuts action, so
        // it follows Settings > Shortcut's switch, not New Expense's.
        let expense = await QuickLog.walletExpense(
            merchant: merchant, amount: value, card: card, in: target,
            suggestionsEnabled: store.preferences.shortcutSmartSuggestionsEnabled, model: CategoryModels.current
        )
        try await IntentSupport.save(expense, in: target, store: store)
        let card = IntentSupport.card(for: expense, in: target, store: store)
        return .result(dialog: IntentSupport.addedDialog, view: ExpenseCardView(card: card))
    }
}
