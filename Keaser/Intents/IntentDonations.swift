import AppIntents
import Foundation
import KeaserKit

/// Tells the system about expenses added in the app, so it can learn what
/// the person logs and when, and suggest "Add Expense" with those details
/// (on the lock screen, in Spotlight, in Shortcuts). Learned on the iPhone.
@MainActor
enum IntentDonations {
    /// After New Expense saves `expense` to `accountID`: donates Add Expense
    /// with its title, amount, category, payment method and account. Not
    /// its date, so a suggestion taken later is dated when it is taken.
    /// Nothing is donated for an edit or a save that did not reach the disk.
    static func addedInApp(_ expense: Expense, accountID: UUID, store: KeaserStore) {
        // As the store kept it (the title trimmed), and only once it is
        // on disk.
        guard store.lastSaveError == nil,
              let account = store.account(id: accountID),
              let saved = account.expenses.first(where: { $0.id == expense.id })
        else { return }
        let intent = AddExpenseIntent()
        intent.expenseTitle = saved.title
        intent.amount = IntentCurrencyAmount(amount: saved.amount, currencyCode: store.preferences.currencyCode)
        intent.category = account.category(id: saved.categoryID).map { CategoryEntity($0) }
        intent.paymentMethod = account.paymentMethod(id: saved.paymentMethodID).map { PaymentMethodEntity($0) }
        intent.account = AccountEntity(account)
        Task {
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }
}
