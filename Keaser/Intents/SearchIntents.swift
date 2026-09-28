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
    /// Expenses are only shown on this iPhone, unlocked. (Siri's search
    /// schema demands at least this, so every open and search intent has it.)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Search Term", requestValueDialog: "What would you like to search for?")
    var criteria: StringSearchCriteria

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRoutes.open(.search(criteria.term))
        return .result()
    }
}
