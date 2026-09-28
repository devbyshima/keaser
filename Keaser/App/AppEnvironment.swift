import CoreSpotlight
import KeaserKit
import SwiftUI

/// Process-wide singletons. The app injects them into the SwiftUI environment;
/// App Intents, which run outside any view, reach them here.
@MainActor
enum AppEnvironment {
    static let store: KeaserStore = {
        #if DEBUG
        if let seed = DebugLaunch.seed {
            // Seeded launches never touch the real file.
            var database = DemoData.database(seed)
            if DebugLaunch.int("KeaserLetter") == 1 { database.preferences.hasSeenWelcomeLetter = false }
            // `-KeaserSelectAccount 1` starts on another account, so an
            // opened expense can be seen switching back to its own.
            if let index = DebugLaunch.int("KeaserSelectAccount"), database.accounts.indices.contains(index) {
                database.preferences.selectedAccountID = database.accounts[index].id
            }
            // `-KeaserCurrency RWF -KeaserAmountScale 5000` shows the seed in
            // a currency with long totals ("RWF 100,000"), for layouts that
            // must make room for them.
            if let code = DebugLaunch.string("KeaserCurrency") { database.preferences.currencyCode = code }
            if let scale = DebugLaunch.int("KeaserAmountScale"), scale > 0 {
                for index in database.accounts.indices {
                    for item in database.accounts[index].expenses.indices {
                        database.accounts[index].expenses[item].amount *= Decimal(scale)
                    }
                }
            }
            // `-KeaserReceiptAttached 1` keeps a sample receipt with the
            // selected account's newest expense (in the seeded folder).
            if let sample = DebugLaunch.string("KeaserReceiptAttached"),
               let a = database.accounts.firstIndex(where: { $0.id == database.selectedAccount?.id }),
               let newest = database.accounts[a].expensesNewestFirst.first,
               let e = database.accounts[a].expenses.firstIndex(where: { $0.id == newest.id }),
               let jpeg = ReceiptImage.debugSample(sample) {
                database.accounts[a].expenses[e].receipt = try? receipts.add(jpeg)
            }
            return KeaserStore(database: database, file: nil)
        }
        #endif
        return KeaserStore(file: .shared)
    }()

    static let router: AppRouter = {
        let router = AppRouter()
        #if DEBUG
        // `-KeaserOpenExpense`, `-KeaserOpenAccount`, `-KeaserOpenSearch`:
        // a route waiting at launch, as when an App Intent or a Spotlight
        // result starts the app.
        router.pendingRoute = DebugLaunch.route(in: store.database)
        #endif
        return router
    }()

    static let pro = ProStore(store: store)

    /// Where receipt photos are kept. Seeded launches use a folder of their
    /// own in the temporary directory, emptied at each launch, and never
    /// touch the real one.
    nonisolated static let receipts: ReceiptFolder = {
        #if DEBUG
        if DebugLaunch.seed != nil {
            let url = FileManager.default.temporaryDirectory.appending(path: "SeededReceipts", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: url)
            return ReceiptFolder(url: url)
        }
        #endif
        return .shared
    }()

    /// Removes the receipt photos no expense has referred to for a day
    /// (`ReceiptFolder`), away from the main actor. Called once at launch,
    /// so a deletion's undo, which lives only as long as the process that
    /// deleted, never loses its photo; nothing is removed while the
    /// database cannot be read.
    static func removeOrphanedReceipts() {
        guard let inUse = store.receiptPhotosInUse else { return }
        let folder = receipts
        Task.detached(priority: .utility) {
            folder.removeOrphans(keeping: inUse)
        }
    }
}

/// App-level navigation requests that arrive from outside the view tree:
/// deep links from widgets and controls, App Intents that open the app, and
/// Spotlight results.
@MainActor
@Observable
final class AppRouter {
    enum Route: Equatable {
        /// Open the New Expense sheet on the selected account.
        case newExpense
        case settings
        /// Select the expense's account and show the expense in Edit
        /// Expense (`OpenExpenseIntent`, a Spotlight result).
        case expense(UUID)
        /// Select the account and show Home (`OpenAccountIntent`).
        case account(UUID)
        /// Show Search with this text (`SearchExpensesIntent`).
        case search(String)
    }

    /// Set by a deep link; the screen that can fulfil it clears it.
    var pendingRoute: Route?

    /// `keaser://new-expense`, `keaser://settings`.
    func handle(_ url: URL) {
        guard url.scheme == "keaser" else { return }
        switch url.host() {
        case "new-expense": pendingRoute = .newExpense
        case "settings": pendingRoute = .settings
        default: break
        }
    }

    /// A tapped Spotlight result, when the system hands it over as a user
    /// activity rather than running `OpenExpenseIntent` or
    /// `OpenAccountIntent`: the item's ID is an expense's or an account's.
    func handleSpotlight(_ activity: NSUserActivity, in database: Database) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = SpotlightPlan.entityID(inItemIdentifier: identifier)
        else { return }
        pendingRoute = database.accounts.contains { $0.id == id } ? .account(id) : .expense(id)
    }
}
