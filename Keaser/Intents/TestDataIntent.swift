#if DEBUG
import AppIntents
import Foundation
import KeaserKit

/// Debug builds only, for the App Intents test suite (KeaserIntentTests):
/// replaces Keaser's data with `IntentTestFixture`, in the real database
/// file, so the intents and queries under test, which all read that file,
/// start from the same known data. Never offered in Shortcuts or to Siri.
struct ResetTestDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Test Data"
    static let isDiscoverable = false

    @Parameter(title: "Pro", default: true)
    var pro: Bool

    @Parameter(title: "Confirm Expense Details", default: false)
    var confirmsDetails: Bool

    /// Off leaves Keaser with no account yet.
    @Parameter(title: "Accounts", default: true)
    var accounts: Bool

    /// Settings > Smart Suggestions (New Expense's switch).
    @Parameter(title: "Smart Suggestions", default: true)
    var suggestions: Bool

    /// Settings > Shortcut > Smart Suggestions.
    @Parameter(title: "Shortcut Smart Suggestions", default: true)
    var shortcutSuggestions: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = AppEnvironment.store
        var database = IntentTestFixture.database(pro: pro, confirmsDetails: confirmsDetails, accounts: accounts)
        database.preferences.smartSuggestionsEnabled = suggestions
        database.preferences.shortcutSmartSuggestionsEnabled = shortcutSuggestions
        try DatabaseFile.shared.save(database)
        store.reloadFromDisk()
        if store.loadError != nil { throw KeaserIntentError.dataUnavailable }
        // Spotlight holds the new data, and nothing of the old, before the
        // first test searches it.
        SpotlightIndexer.shared.attach(to: store)
        await SpotlightIndexer.shared.flush()
        return .result()
    }
}
#endif
