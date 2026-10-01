import AppIntents
import Foundation
import KeaserKit

// Opening an expense or an account. Spotlight runs these when one of its
// results is tapped, and Siri and Shortcuts offer them as "Open Expense" and
// "Open Account". Each only leaves a route for Home to follow
// (`AppRouter.Route.expense` and `.account`), which brings the Home tab
// forward; the app comes to the front on its own, as it does for every
// OpenIntent.
//
// There is no iOS 27 `.system.open` schema version: the schema is iOS 27
// only, so it cannot go on these iOS 18 intents, and a second OpenIntent for
// the same entity fails the build ("OpenIntent targets should be unique").

/// "Open Expense": selects the expense's account and shows the expense's
/// details.
struct OpenExpenseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Expense"
    static var description: IntentDescription {
        IntentDescription("Opens an expense in Keaser, ready to edit.")
    }
    /// Expenses are only shown on this iPhone, unlocked. (Siri's search
    /// schema demands at least this, so every open and search intent has it.)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Expense")
    var target: ExpenseEntity

    init() {}

    init(target: ExpenseEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRoutes.open(.expense(target.id))
        return .result()
    }
}

/// "Open Account": selects the account and shows Home.
struct OpenAccountIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Account"
    static var description: IntentDescription {
        IntentDescription("Switches Keaser to an account and shows its spending.")
    }
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Account")
    var target: AccountEntity

    init() {}

    init(target: AccountEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRoutes.open(.account(target.id))
        return .result()
    }
}

/// What the open and search intents do inside the app.
@MainActor
enum AppIntentRoutes {
    /// Leaves `route` for Home (selecting the Home tab), after catching up
    /// with anything written while the app was in the background.
    static func open(_ route: AppRouter.Route) {
        AppEnvironment.store.reloadFromDisk()
        AppEnvironment.router.open(route)
    }
}
