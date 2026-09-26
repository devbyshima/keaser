import AppIntents
import Foundation
import KeaserKit

/// "Log Wallet Transaction": the action for a Shortcuts automation on the
/// Wallet "When I tap" trigger, which passes the merchant, the amount as text
/// and the card name.
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
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentSupport.freshStore()
        let target = try IntentSupport.account(nil, in: store)
        guard let value = QuickLog.amount(from: amount, currencyCode: store.preferences.currencyCode) else {
            throw KeaserIntentError.invalidAmount
        }
        let expense = QuickLog.walletExpense(merchant: merchant, amount: value, card: card, in: target)
        let message = await IntentSupport.save(expense, in: target, store: store)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
