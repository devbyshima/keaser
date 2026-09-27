import AppIntents
import Foundation
import KeaserKit

// Compiled into the widget extension as well as the app, because the Add
// Expense control names this intent as its action. The app performs it
// (Keaser/Intents/AddExpenseFlow.swift): only there can it ask questions and
// show the expense card. The extension's own `perform` (AddExpenseControl.swift)
// is a fallback for a system that runs it there anyway.

/// "Add Expense": logs an expense without opening the app, from Shortcuts,
/// Siri, the lock screen, Control Center or the Action button. Whatever the
/// shortcut leaves empty is asked for in turn.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static var description: IntentDescription {
        IntentDescription("Adds an expense to Keaser without opening the app, asking for anything left empty.")
    }

    // A control's intent runs in the widget extension unless it can continue
    // in the app: these keep it in the app's process, in the background.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

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

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) as \(\.$expenseTitle)") {
            \.$category
            \.$paymentMethod
            \.$account
        }
    }

    init() {}
}

// Before iOS 26, conforming is what keeps the intent in the app's process
// (the protocol does not exist in app extensions).
@available(iOSApplicationExtension, unavailable)
@available(iOS, deprecated: 26.0, message: "supportedModes does this from iOS 26")
extension AddExpenseIntent: ForegroundContinuableIntent {}
