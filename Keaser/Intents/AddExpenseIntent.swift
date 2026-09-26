import AppIntents
import Foundation
import KeaserKit

/// "Add Expense": logs an expense without opening the app, from Shortcuts,
/// Siri, the lock screen or the Action button.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static var description: IntentDescription {
        IntentDescription("Adds an expense to Keaser without opening the app.")
    }

    @Parameter(title: "Amount", requestValueDialog: "Amount")
    var amount: Double

    @Parameter(title: "Title", description: "Defaults to \"Expense\".")
    var expenseTitle: String?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Payment Method")
    var paymentMethod: PaymentMethodEntity?

    @Parameter(title: "Account", description: "Leave empty to use the account selected in Keaser.")
    var account: AccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) as \(\.$expenseTitle)") {
            \.$category
            \.$paymentMethod
            \.$account
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntentSupport.freshStore()
        let target = try IntentSupport.account(account, in: store)
        guard let value = QuickLog.amount(from: amount, currencyCode: store.preferences.currencyCode) else {
            throw KeaserIntentError.invalidAmount
        }
        let title = expenseTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expense = Expense(
            title: title.isEmpty ? QuickLog.defaultTitle : title,
            amount: value,
            // Categories and methods are listed from the selected account; when
            // the shortcut targets another account, match them there by name.
            categoryID: category.flatMap { chosen in
                target.categories.first { $0.id == chosen.id } ?? target.categories.first { $0.name == chosen.name }
            }?.id,
            paymentMethodID: paymentMethod.flatMap { chosen in
                target.paymentMethods.first { $0.id == chosen.id } ?? target.paymentMethods.first { $0.name == chosen.name }
            }?.id
        )
        let message = await IntentSupport.save(expense, in: target, store: store)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
