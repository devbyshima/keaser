import AppIntents
import Foundation
import KeaserKit
import WidgetKit

enum KeaserIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAccount
    case invalidAmount
    case dataUnavailable
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccount: "Create an account in Keaser first."
        case .invalidAmount: "Enter an amount greater than zero."
        case .dataUnavailable: "Keaser can't open its data right now. Unlock your iPhone and try again."
        case .saveFailed: "Keaser couldn't save this expense. Free up space on your iPhone and try again."
        }
    }
}

/// What every intent that writes does around the write.
@MainActor
enum IntentSupport {
    /// The app's store, re-read from disk. Intents may run while the app sits
    /// in the background with an older copy in memory. Throws when the file
    /// cannot be read (before first unlock), or when an earlier change still
    /// cannot be written (the reload retried it and failed again), since
    /// nothing written then would be kept.
    static func freshStore() throws -> KeaserStore {
        let store = AppEnvironment.store
        store.reloadFromDisk()
        if store.loadError != nil { throw KeaserIntentError.dataUnavailable }
        if store.lastSaveError != nil { throw KeaserIntentError.saveFailed }
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
    ///
    /// Throws when the expense did not reach the disk. It is taken back out
    /// of memory as well: kept there, a later save would write it anyway,
    /// and the person, told it failed, would add it a second time.
    static func save(_ expense: Expense, in account: Account, store: KeaserStore) async throws {
        store.saveExpense(expense, in: account.id)
        if store.lastSaveError != nil {
            store.deleteExpense(expense.id, in: account.id)
            throw KeaserIntentError.saveFailed
        }
        WidgetCenter.shared.reloadAllTimelines()
        WeeklySummaryScheduler.shared.attach(to: store)
        await WeeklySummaryScheduler.shared.refreshNow()
    }

    /// Above the card of an expense a shortcut or automation just added.
    static let addedDialog: IntentDialog = "Successfully added expense"

    /// The card for an expense as it was saved.
    static func card(for expense: Expense, in account: Account, store: KeaserStore) -> ShortcutCard {
        ShortcutCard(expense: expense, in: account, currencyCode: store.preferences.currencyCode)
    }
}
