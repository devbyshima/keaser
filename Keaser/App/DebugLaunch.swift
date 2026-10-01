import Foundation
import KeaserKit

/// Launch arguments that put the app straight into a given state, so every
/// screen can be screenshotted from a cold launch without tapping.
///
/// Arguments are passed as `-Key value` pairs, which Foundation folds into the
/// `UserDefaults` argument domain. They are ignored entirely in Release.
///
/// Keys (see AGENTS.md for the full table):
/// - `-KeaserSeed fresh|onboarded|account|single|demo`
/// - `-KeaserOnboardingPage 0...4`
/// - `-KeaserTab home|wallets|summary|settings`
/// - `-KeaserSheet <name>` (each feature documents its own sheet names)
/// - `-KeaserSettingsPage <name>` (pushed in the Settings tab)
/// - `-KeaserPeriod today|thisWeek|thisMonth|thisYear|allTime`
enum DebugLaunch {
    static func string(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }

    static func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }

    static var seed: DemoData.Seed? {
        string("KeaserSeed").flatMap(DemoData.Seed.init(rawValue:))
    }

    /// The tab showing at launch, instead of Home.
    static var tab: AppTab? { string("KeaserTab").flatMap(AppTab.init(rawValue:)) }

    /// The sheet a screenshot wants presented at launch, e.g. "newExpense".
    static var sheet: String? { string("KeaserSheet") }

    /// A page inside Settings, e.g. "currency".
    static var settingsPage: String? { string("KeaserSettingsPage") }

    /// True the first time a launch asks for `hook`, false after that. A
    /// screen that applies its launch argument when it appears (scrolling,
    /// an alert) asks first, since switching tabs makes it appear again.
    @MainActor
    static func firstTime(_ hook: String) -> Bool {
        usedHooks.insert(hook).inserted
    }

    @MainActor private static var usedHooks: Set<String> = []

    /// A shortcut card drawn in a stand-in of the system's, e.g. "confirm"
    /// (see `SnippetPreview`).
    static var snippet: String? { string("KeaserSnippet") }

    /// The route an App Intent or a Spotlight result would leave waiting at
    /// launch, taken through `AppRouter` like the real thing:
    /// `-KeaserOpenExpense first` (the newest expense in any account) or an
    /// index into every expense newest first, `-KeaserOpenAccount <index>`,
    /// `-KeaserOpenSearch <text>`; and `-KeaserOpenURL <url>`, a deep link
    /// as a widget or control opens it (`keaser://scan-receipt`).
    static func route(in database: Database) -> AppRouter.Route? {
        if let link = string("KeaserOpenURL").flatMap(URL.init(string:)) {
            return AppRouter.route(for: link)
        }
        if let value = string("KeaserOpenExpense") {
            let expenses = EntityCatalog.allExpenses(in: database)
            let index = value == "first" ? 0 : Int(value) ?? -1
            return expenses.indices.contains(index) ? .expense(expenses[index].id) : nil
        }
        if let index = int("KeaserOpenAccount") {
            return database.accounts.indices.contains(index) ? .account(database.accounts[index].id) : nil
        }
        if let text = string("KeaserOpenSearch") {
            return .search(text)
        }
        return nil
    }
}
