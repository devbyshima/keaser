import AppIntents
import Foundation
import KeaserKit

// Compiled into both the widget extension (the Spending widget's account
// option) and the app (the "Add Expense" shortcut's account parameter).

/// A Keaser account as Shortcuts and widget configuration see it.
struct AccountEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account", synonyms: ["Ledger"])
    }
    static var defaultQuery: AccountEntityQuery { AccountEntityQuery() }

    /// The Go Back row at the end of the Add Expense shortcut's account list.
    static let goBack = AccountEntity(id: ShortcutFlow.goBackID, name: "Go Back")

    let id: UUID
    @Property(title: "Name") var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ account: Account) {
        self.init(id: account.id, name: account.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Reads the shared database file. The app saves it on every change, so it is
/// current in both processes.
///
/// There is deliberately no default result: an empty account parameter means
/// "the account selected in Keaser", which then follows the user's choice
/// instead of freezing the one selected when the widget was added. Typed
/// names ("Open Business") match accounts only, never Go Back.
struct AccountEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        let found = DatabaseFile.shared.load().accounts
            .filter { identifiers.contains($0.id) }
            .map(AccountEntity.init)
        return found + (identifiers.contains(ShortcutFlow.goBackID) ? [.goBack] : [])
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        DatabaseFile.shared.load().accounts.map(AccountEntity.init)
    }

    func entities(matching string: String) async throws -> [AccountEntity] {
        EntityCatalog.accounts(matching: string, in: DatabaseFile.shared.load()).map(AccountEntity.init)
    }
}
