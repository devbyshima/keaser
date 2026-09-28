import AppIntents
import CoreSpotlight
import Foundation
import KeaserKit

// `AccountEntity` is declared in KeaserWidgets/Shared for the widget's
// account option. Only the app writes to Spotlight, so only the app's copy
// of the type is indexed; the widget extension's stays as it was.

/// Accounts are in Spotlight too, so "Business" finds the account and opens
/// it on Home.
extension AccountEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = "Keaser account"
        return attributes
    }
}

@available(iOS 27.0, *)
extension AccountEntityQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindex(.accounts(identifiers), protectionClass: indexDescription.protectionClass)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindex(.accounts(nil), protectionClass: indexDescription.protectionClass)
    }
}
