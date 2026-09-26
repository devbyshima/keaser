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
            return KeaserStore(database: database, file: nil)
        }
        #endif
        return KeaserStore(file: .shared)
    }()

    static let router = AppRouter()

    static let pro = ProStore(store: store)
}

/// App-level navigation requests that arrive from outside the view tree:
/// deep links from widgets and controls, and App Intents that open the app.
@MainActor
@Observable
final class AppRouter {
    enum Route: Equatable {
        /// Open the New Expense sheet on the selected account.
        case newExpense
        case settings
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
}
