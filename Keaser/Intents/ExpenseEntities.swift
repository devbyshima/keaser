import AppIntents
import Foundation
import KeaserKit

// The queries read the shared database file, which the app saves on every
// change.

/// A category, for the "Add Expense" shortcut. The Shortcuts editor shows its
/// symbol; the lists the shortcut asks from show names only, as in the
/// reference.
struct CategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Category", synonyms: ["Expense Category", "Spending Category"])
    }
    static var defaultQuery: CategoryEntityQuery { CategoryEntityQuery() }

    /// The Go Back row at the end of the shortcut's category list.
    static let goBack = CategoryEntity(id: ShortcutFlow.goBackID, name: "Go Back", symbol: nil)

    let id: UUID
    @Property(title: "Name") var name: String
    /// Nil in the shortcut's own lists.
    let symbol: String?

    init(_ category: ExpenseCategory, showsSymbol: Bool = true) {
        self.init(id: category.id, name: category.name, symbol: showsSymbol ? category.symbol : nil)
    }

    private init(id: UUID, name: String, symbol: String?) {
        self.id = id
        self.symbol = symbol
        // A property wrapper, so it is set once the plain properties are.
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        guard let symbol else { return DisplayRepresentation(title: "\(name)") }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

/// Looks categories up in every account, since a saved shortcut keeps
/// working after another account is selected; the picker lists only the
/// selected account's. A typed name matches the selected account's
/// categories first (see `EntityCatalog.categories(matching:in:)`).
struct CategoryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let found = QuickLog.categories(withIDs: identifiers, in: DatabaseFile.shared.load()).map { CategoryEntity($0) }
        return found + (identifiers.contains(ShortcutFlow.goBackID) ? [.goBack] : [])
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        DatabaseFile.shared.load().selectedAccount?.categories.map { CategoryEntity($0) } ?? []
    }

    func entities(matching string: String) async throws -> [CategoryEntity] {
        EntityCatalog.categories(matching: string, in: DatabaseFile.shared.load()).map { CategoryEntity($0) }
    }
}

/// A payment method, for the "Add Expense" shortcut. Like `CategoryEntity`,
/// with a symbol in the editor and names only in the shortcut's lists.
struct PaymentMethodEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Payment Method", synonyms: ["Card", "Payment Type"])
    }
    static var defaultQuery: PaymentMethodEntityQuery { PaymentMethodEntityQuery() }

    /// The Go Back row at the end of the shortcut's payment method list.
    static let goBack = PaymentMethodEntity(id: ShortcutFlow.goBackID, name: "Go Back", symbol: nil)

    let id: UUID
    @Property(title: "Name") var name: String
    /// Nil in the shortcut's own lists.
    let symbol: String?

    init(_ method: PaymentMethod, showsSymbol: Bool = true) {
        self.init(id: method.id, name: method.name, symbol: showsSymbol ? method.symbol : nil)
    }

    private init(id: UUID, name: String, symbol: String?) {
        self.id = id
        self.symbol = symbol
        // A property wrapper, so it is set once the plain properties are.
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        guard let symbol else { return DisplayRepresentation(title: "\(name)") }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

/// Looks payment methods up in every account, like `CategoryEntityQuery`.
struct PaymentMethodEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PaymentMethodEntity] {
        let found = QuickLog.paymentMethods(withIDs: identifiers, in: DatabaseFile.shared.load()).map { PaymentMethodEntity($0) }
        return found + (identifiers.contains(ShortcutFlow.goBackID) ? [.goBack] : [])
    }

    func suggestedEntities() async throws -> [PaymentMethodEntity] {
        DatabaseFile.shared.load().selectedAccount?.paymentMethods.map { PaymentMethodEntity($0) } ?? []
    }

    func entities(matching string: String) async throws -> [PaymentMethodEntity] {
        EntityCatalog.paymentMethods(matching: string, in: DatabaseFile.shared.load()).map { PaymentMethodEntity($0) }
    }
}
