import AppIntents
import Foundation

/// "Search Expenses": opens Keaser's Search on the selected account with the
/// term typed in, as if it had been entered there. Spotlight also uses it to
/// continue a search in the app.
struct SearchExpensesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Expenses"
    static var description: IntentDescription {
        IntentDescription("Opens Keaser's search with a term, showing the expenses whose title matches.")
    }

    static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Search Term", requestValueDialog: "What would you like to search for?")
    var criteria: StringSearchCriteria

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRoutes.open(.search(criteria.term))
        return .result()
    }
}

// Siri's in-app search from iOS 27, through the `.system.searchInApp`
// schema; assistant-only, so Shortcuts lists the intent above once.
@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchInKeaserIntent: ShowInAppSearchResultsIntent {
    static let isAssistantOnly = true
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRoutes.open(.search(criteria.term))
        return .result()
    }
}
