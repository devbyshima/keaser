import AppIntents
import CoreSpotlight
import Foundation
import KeaserKit

// App only: nothing in the widget extension names an expense. If an intent
// the Add Expense control runs ever takes or returns one, move this file to
// KeaserWidgets/Shared, as was done for the account and label entities.

/// One expense, for Siri, Shortcuts and Spotlight. Its ID is the expense's
/// own, so it stays valid across launches and account switches.
struct ExpenseEntity: IndexedEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Expense",
            numericFormat: "\(placeholder: .int) expenses",
            synonyms: ["Purchase", "Spending", "Transaction"]
        )
    }
    static var defaultQuery: ExpenseEntityQuery { ExpenseEntityQuery() }

    let id: UUID
    /// The account it is filed in, for opening it there.
    let accountID: UUID
    /// Its category's SF Symbol.
    let symbol: String
    /// "$20.00 · Sep 27, 2026", worked out once in the process that found it.
    let subtitle: String
    /// Its category, payment method and account, for Spotlight.
    let keywords: [String]

    @Property(title: "Title") var title: String
    @Property(title: "Amount") var amount: IntentCurrencyAmount
    @Property(title: "Date") var date: Date
    @Property(title: "Category") var categoryName: String?
    @Property(title: "Payment Method") var paymentMethodName: String?
    @Property(title: "Account") var accountName: String

    init(_ summary: ExpenseSummary) {
        id = summary.id
        accountID = summary.accountID
        symbol = summary.symbol
        subtitle = summary.subtitle()
        keywords = summary.keywords
        // Property wrappers, so they are set once the plain properties are.
        title = summary.title
        amount = IntentCurrencyAmount(amount: summary.amount, currencyCode: summary.currencyCode)
        date = summary.date
        categoryName = summary.categoryName
        paymentMethodName = summary.paymentMethodName
        accountName = summary.accountName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: symbol)
        )
    }

    /// What Spotlight and Siri's on-device index keep: the title and
    /// subtitle from `displayRepresentation`, plus the day it was spent and
    /// the names it is filed under, so "coffee", "cash" or "business" all
    /// find it.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = subtitle
        attributes.keywords = keywords
        attributes.contentCreationDate = date
        return attributes
    }
}

/// Reads the shared database file, like the other entity queries, and
/// looks in every account.
struct ExpenseEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ExpenseEntity] {
        EntityCatalog.expenses(withIDs: identifiers, in: DatabaseFile.shared.load()).map(ExpenseEntity.init)
    }

    /// Titles containing the text, newest first.
    func entities(matching string: String) async throws -> [ExpenseEntity] {
        EntityCatalog.expenses(matching: string, in: DatabaseFile.shared.load()).map(ExpenseEntity.init)
    }

    /// The most recent expenses, from every account.
    func suggestedEntities() async throws -> [ExpenseEntity] {
        EntityCatalog.recentExpenses(in: DatabaseFile.shared.load()).map(ExpenseEntity.init)
    }
}

/// From iOS 27 Spotlight asks for entities again when its copy of the index
/// needs rebuilding.
@available(iOS 27.0, *)
extension ExpenseEntityQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindexExpenses(identifiers, protectionClass: indexDescription.protectionClass)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindexExpenses(nil, protectionClass: indexDescription.protectionClass)
    }
}
