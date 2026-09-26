import AppIntents
import Foundation
import KeaserKit

/// A category of the selected account, for the "Add Expense" shortcut.
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

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        IntentSupport.freshStore().selectedAccount?.categories.map(CategoryEntity.init) ?? []
    }
}

/// A payment method of the selected account, for the "Add Expense" shortcut.
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

struct PaymentMethodEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PaymentMethodEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PaymentMethodEntity] {
        IntentSupport.freshStore().selectedAccount?.paymentMethods.map(PaymentMethodEntity.init) ?? []
    }
}
