import AppIntents
import Foundation
import KeaserKit

// Performed in Keaser/Intents/AddExpenseFlow.swift.

/// "Add Expense": logs an expense without opening the app, from Shortcuts,
/// Siri or a Wallet automation. Whatever the shortcut leaves empty is asked
/// for in turn. (The Add Expense control cannot ask questions, so it opens
/// New Expense instead; see AddExpenseControl.)
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static var description: IntentDescription {
        IntentDescription("Adds an expense to Keaser without opening the app, asking for anything left empty.")
    }

    @Parameter(title: "Amount", description: "Asked for when empty.")
    var amount: IntentCurrencyAmount?

    @Parameter(title: "Title", description: "Asked for when empty.")
    var expenseTitle: String?

    @Parameter(title: "Category", description: "Asked for when empty, unless Keaser can tell from the title.")
    var category: CategoryEntity?

    @Parameter(title: "Payment Method", description: "Asked for when empty, unless Keaser can tell from the title.")
    var paymentMethod: PaymentMethodEntity?

    @Parameter(title: "Account", description: "Asked for when empty and there is more than one account.")
    var account: AccountEntity?

    /// Never asked for. A Wallet automation sets it to Current Date.
    @Parameter(title: "Date", description: "The day of the expense. When empty, the moment it is added.", kind: .date)
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) as \(\.$expenseTitle)") {
            \.$category
            \.$paymentMethod
            \.$account
            \.$date
        }
    }

    init() {}
}
