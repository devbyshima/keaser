import Foundation

/// Links an account to one Notion database. The integration token is not
/// stored here; it lives in the Keychain, keyed by the account ID.
public struct NotionConnection: Codable, Hashable, Sendable {
    public var databaseID: String
    public var databaseTitle: String
    public var workspaceName: String?
    public var properties: NotionPropertyMap
    public var lastSyncedAt: Date?

    public init(
        databaseID: String,
        databaseTitle: String,
        workspaceName: String? = nil,
        properties: NotionPropertyMap,
        lastSyncedAt: Date? = nil
    ) {
        self.databaseID = databaseID
        self.databaseTitle = databaseTitle
        self.workspaceName = workspaceName
        self.properties = properties
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Which Notion database property holds each expense field. Only `title` is
/// required, because every Notion database has exactly one title property.
public struct NotionPropertyMap: Codable, Hashable, Sendable {
    public var title: String
    public var amount: String?
    public var category: String?
    public var paymentMethod: String?
    public var date: String?

    public init(
        title: String,
        amount: String? = nil,
        category: String? = nil,
        paymentMethod: String? = nil,
        date: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.category = category
        self.paymentMethod = paymentMethod
        self.date = date
    }
}
