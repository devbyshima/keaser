import AppIntents
import Foundation
import KeaserKit

/// A category, for the "Add Expense" shortcut.
struct CategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var defaultQuery: CategoryEntityQuery { CategoryEntityQuery() }

    let id: UUID
    let name: String
    let symbol: String

    init(_ category: ExpenseCategory) {
        id = category.id
        name = category.name
        symbol = category.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

/// Looks categories up in every account, since a saved shortcut keeps
/// working after another account is selected; the picker lists only the
/// selected account's.
struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let store = try IntentSupport.freshStore()
        return QuickLog.categories(withIDs: identifiers, in: store.database).map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        (try? IntentSupport.freshStore())?.selectedAccount?.categories.map(CategoryEntity.init) ?? []
    }
}

/// A payment method, for the "Add Expense" shortcut.
struct PaymentMethodEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Payment Method" }
    static var defaultQuery: PaymentMethodEntityQuery { PaymentMethodEntityQuery() }

    let id: UUID
    let name: String
    let symbol: String

    init(_ method: PaymentMethod) {
        id = method.id
        name = method.name
        symbol = method.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

/// Looks payment methods up in every account, like `CategoryEntityQuery`.
struct PaymentMethodEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PaymentMethodEntity] {
        let store = try IntentSupport.freshStore()
        return QuickLog.paymentMethods(withIDs: identifiers, in: store.database).map(PaymentMethodEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PaymentMethodEntity] {
        (try? IntentSupport.freshStore())?.selectedAccount?.paymentMethods.map(PaymentMethodEntity.init) ?? []
    }
}
