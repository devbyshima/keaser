import CoreSpotlight
import KeaserKit
import SwiftUI
import UIKit

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
            // `-KeaserReceiptAttached <n>` keeps n sample receipts with the
            // selected account's newest expense (in the seeded folder).
            if let count = DebugLaunch.string("KeaserReceiptAttached"),
               let a = database.accounts.firstIndex(where: { $0.id == database.selectedAccount?.id }),
               let newest = database.accounts[a].expensesNewestFirst.first,
               let e = database.accounts[a].expenses.firstIndex(where: { $0.id == newest.id }) {
                database.accounts[a].expenses[e].receipts = ReceiptImage.debugSamples(count).compactMap { try? receipts.add($0) }
            }
            return KeaserStore(database: database, file: nil)
        }
        #endif
        return KeaserStore(file: .shared)
    }()

    static let router: AppRouter = {
        let router = AppRouter()
        #if DEBUG
        // `-KeaserTab settings` starts on that tab, and
        // `-KeaserSettingsPage currency` with the page already pushed in it.
        if let tab = DebugLaunch.tab { router.selectedTab = tab }
        router.settingsPath = SettingsPage.launchPath(store: store)
        // `-KeaserOpenExpense`, `-KeaserOpenAccount`, `-KeaserOpenSearch`,
        // `-KeaserOpenURL`: a route waiting at launch, as when an App Intent,
        // a Spotlight result or a widget starts the app.
        if let route = DebugLaunch.route(in: store.database) { router.open(route) }
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

/// Keaser's four tabs, in the order the tab bar shows them.
enum AppTab: String, CaseIterable {
    case home, wallets, summary, settings
}

/// App-level navigation: which tab is showing, the Settings tab's pushed
/// pages, and requests that arrive from outside the view tree (deep links
/// from widgets and controls, App Intents that open the app, and Spotlight
/// results).
@MainActor
@Observable
final class AppRouter {
    enum Route: Equatable {
        /// Open the New Expense sheet on the selected account.
        case newExpense
        /// New Expense with the document camera up (the Scan Receipt
        /// control).
        case scanReceipt
        /// The Settings tab at its root, where Upgrade is (the locked
        /// Spending widget).
        case settings
        /// Select the expense's account and show the expense's details
        /// (`OpenExpenseIntent`, a Spotlight result).
        case expense(UUID)
        /// Select the account and show Home (`OpenAccountIntent`).
        case account(UUID)
        /// Show Search with this text (`SearchExpensesIntent`).
        case search(String)

        /// The tab the route lands on: Settings for `.settings`, Home for
        /// everything else.
        var tab: AppTab {
            switch self {
            case .settings: .settings
            case .newExpense, .scanReceipt, .expense, .account, .search: .home
            }
        }
    }

    /// The tab on screen. Never remembered: every launch starts on Home.
    var selectedTab: AppTab = .home
    /// The pages pushed in the Settings tab, so a route can take it back
    /// to its root.
    var settingsPath: [SettingsPage] = []
    /// Goes up by one with every route. Whatever the Settings tab presents
    /// (the paywall, the label editor, alerts and dialogs) closes when it
    /// changes, since a sheet left up would hide the tab the route selects.
    private(set) var modalReset = 0
    /// The route Home still has to follow; HomeView takes it and clears it.
    /// `.settings` comes here too, so Home closes its own sheet.
    private(set) var pendingRoute: Route?
    /// Counts routes, so a route still waiting for a sheet to close gives
    /// way to a newer one.
    @ObservationIgnored private var routeCount = 0

    /// Where every route comes in: deep links, Spotlight, App Intents and
    /// DEBUG launches. On the tab showing, it lands at once (Home replaces
    /// its sheet, as it always has). For another tab, whatever is presented
    /// closes first (Settings' sheets, alerts and dialogs through
    /// `modalReset`, Home's sheet through `.settings`) and the tab changes
    /// once nothing is presented any more: a sheet whose tab leaves the
    /// screen while it is up stays stuck there, and the new tab could not
    /// present one while another is still going.
    func open(_ route: Route) {
        modalReset += 1
        routeCount += 1
        guard route.tab != selectedTab, Self.isPresenting else {
            land(route)
            return
        }
        if route == .settings { pendingRoute = .settings }
        let count = routeCount
        Task {
            // A sheet takes about a third of a second to leave; give up
            // waiting after two (the welcome letter, say, stays up).
            var waits = 0
            while Self.isPresenting, waits < 40 {
                try? await Task.sleep(for: .milliseconds(50))
                waits += 1
            }
            guard count == routeCount else { return }
            land(route, homeKnows: route == .settings)
        }
    }

    /// Shows the route's tab and hands Home its route.
    private func land(_ route: Route, homeKnows: Bool = false) {
        selectedTab = route.tab
        if route == .settings { settingsPath = [] }
        if !homeKnows { pendingRoute = route }
    }

    /// Whether the app's window has anything presented over it: a sheet, an
    /// alert or a dialog, or one still on its way out.
    private static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    /// Called by Home once it has followed `pendingRoute`.
    func clearPendingRoute() {
        pendingRoute = nil
    }

    /// `keaser://new-expense`, `keaser://scan-receipt`, `keaser://settings`.
    func handle(_ url: URL) {
        if let route = Self.route(for: url) { open(route) }
    }

    nonisolated static func route(for url: URL) -> Route? {
        guard url.scheme == "keaser" else { return nil }
        switch url.host() {
        case "new-expense": return .newExpense
        case "scan-receipt": return .scanReceipt
        case "settings": return .settings
        default: return nil
        }
    }

    /// A tapped Spotlight result, when the system hands it over as a user
    /// activity rather than running `OpenExpenseIntent` or
    /// `OpenAccountIntent`: the item's ID is an expense's or an account's.
    func handleSpotlight(_ activity: NSUserActivity, in database: Database) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = SpotlightPlan.entityID(inItemIdentifier: identifier)
        else { return }
        open(database.accounts.contains { $0.id == id } ? .account(id) : .expense(id))
    }
}
