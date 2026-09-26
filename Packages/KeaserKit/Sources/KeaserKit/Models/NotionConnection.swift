import Foundation

/// Links an account to one Notion database. The integration token is not
/// stored here; it lives in the Keychain, keyed by the account ID.
///
/// Since Notion API 2025-09-03 a database is a container of one or more data
/// sources, and rows belong to a data source. `databaseID` names the
/// container (what the user shared); `dataSourceID` names the table Keaser
/// reads and writes. Older files have no `dataSourceID`; the sync engine
/// resolves it from the database on the next sync.
public struct NotionConnection: Codable, Hashable, Sendable {
    public var databaseID: String
    public var databaseTitle: String
    public var workspaceName: String?
    public var properties: NotionPropertyMap
    public var lastSyncedAt: Date?
    public var dataSourceID: String?
    /// The database's emoji icon, if it has one.
    public var iconEmoji: String?
    /// Link to open the database in Notion.
    public var url: URL?

    public init(
        databaseID: String,
        databaseTitle: String,
        workspaceName: String? = nil,
        properties: NotionPropertyMap,
        lastSyncedAt: Date? = nil,
        dataSourceID: String? = nil,
        iconEmoji: String? = nil,
        url: URL? = nil
    ) {
        self.databaseID = databaseID
        self.databaseTitle = databaseTitle
        self.workspaceName = workspaceName
        self.properties = properties
        self.lastSyncedAt = lastSyncedAt
        self.dataSourceID = dataSourceID
        self.iconEmoji = iconEmoji
        self.url = url
    }

    // Tolerant decoding: fields added later must not make a file unreadable.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        databaseID = try c.decode(String.self, forKey: .databaseID)
        databaseTitle = try c.decodeIfPresent(String.self, forKey: .databaseTitle) ?? "Notion"
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        properties = try c.decodeIfPresent(NotionPropertyMap.self, forKey: .properties) ?? NotionPropertyMap(title: "Name")
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        dataSourceID = try c.decodeIfPresent(String.self, forKey: .dataSourceID)
        iconEmoji = try c.decodeIfPresent(String.self, forKey: .iconEmoji)
        url = try? c.decodeIfPresent(URL.self, forKey: .url)
    }
}

/// Which Notion database property holds each expense field. Only `title` is
/// required, because every Notion database has exactly one title property.
///
/// Names are what Keaser writes with. The optional IDs are Notion's stable
/// property IDs, so a property renamed in Notion is still found; the sync
/// engine refreshes the names from the schema on every sync.
public struct NotionPropertyMap: Codable, Hashable, Sendable {
    public var title: String
    public var amount: String?
    public var category: String?
    public var paymentMethod: String?
    public var date: String?

    public var titleID: String?
    public var amountID: String?
    public var categoryID: String?
    public var paymentMethodID: String?
    public var dateID: String?

    public init(
        title: String,
        amount: String? = nil,
        category: String? = nil,
        paymentMethod: String? = nil,
        date: String? = nil,
        titleID: String? = nil,
        amountID: String? = nil,
        categoryID: String? = nil,
        paymentMethodID: String? = nil,
        dateID: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.category = category
        self.paymentMethod = paymentMethod
        self.date = date
        self.titleID = titleID
        self.amountID = amountID
        self.categoryID = categoryID
        self.paymentMethodID = paymentMethodID
        self.dateID = dateID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Name"
        amount = try c.decodeIfPresent(String.self, forKey: .amount)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        titleID = try c.decodeIfPresent(String.self, forKey: .titleID)
        amountID = try c.decodeIfPresent(String.self, forKey: .amountID)
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        paymentMethodID = try c.decodeIfPresent(String.self, forKey: .paymentMethodID)
        dateID = try c.decodeIfPresent(String.self, forKey: .dateID)
    }
}
