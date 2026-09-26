import AppIntents
import Foundation
import KeaserKit
import WidgetKit

enum KeaserIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAccount
    case invalidAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccount: "Create an account in Keaser first."
        case .invalidAmount: "Enter an amount greater than zero."
        }
    }
}

/// What every intent that writes does around the write.
@MainActor
enum IntentSupport {
    /// The app's store, re-read from disk. Intents may run while the app sits
    /// in the background with an older copy in memory.
    static func freshStore() -> KeaserStore {
        let store = AppEnvironment.store
        store.reloadFromDisk()
        return store
    }

    /// The account an expense goes to: the one chosen in the shortcut when it
    /// still exists, otherwise the one selected in the app.
    static func account(_ entity: AccountEntity?, in store: KeaserStore) throws -> Account {
        if let entity, let chosen = store.account(id: entity.id) { return chosen }
        guard let selected = store.selectedAccount else { throw KeaserIntentError.noAccount }
        return selected
    }

    /// Saves, then brings the widgets and the weekly summary up to date before
    /// the intent returns, since the system may suspend the app right after.
    static func save(_ expense: Expense, in account: Account, store: KeaserStore) async -> String {
        store.saveExpense(expense, in: account.id)
        WidgetCenter.shared.reloadAllTimelines()
        WeeklySummaryScheduler.shared.attach(to: store)
        await WeeklySummaryScheduler.shared.refreshNow()
        return QuickLog.confirmation(amount: expense.amount, currencyCode: store.preferences.currencyCode, accountName: account.name)
    }
}
