import Foundation

/// The Notion operations Keaser uses. `NotionClient` talks to
/// api.notion.com; `NotionDemoService` is an in-memory stand-in for
/// screenshots and tests.
public protocol NotionAPI: Sendable {
    /// Validates the token and names the workspace.
    func currentUser() async throws -> NotionUser
    /// Every data source (table) shared with the token, most recently edited
    /// first.
    func searchDataSources() async throws -> [NotionDataSource]
    /// Pages shared with the token that can hold a new database. Rows of
    /// data sources are left out.
    func searchPages() async throws -> [NotionPage]
    func retrieveDatabase(id: String) async throws -> NotionDatabase
    func retrieveDataSource(id: String) async throws -> NotionDataSource
    /// Adds these properties to the data source's schema (a property with
    /// the same name is reconfigured). Returns the updated data source.
    func updateDataSource(id: String, properties: [String: NotionNewProperty]) async throws -> NotionDataSource
    /// Every non-trashed, non-archived row, across all result pages.
    func queryPages(dataSourceID: String) async throws -> [NotionPage]
    func retrievePage(id: String) async throws -> NotionPage
    func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage
    func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage
    /// Moves the page to Notion's trash (restorable for 30 days there).
    func trashPage(id: String) async throws
    func createDatabase(parentPageID: String, title: String, iconEmoji: String?, properties: [String: NotionNewProperty]) async throws -> NotionDatabase
}

/// A value to write to one page property.
public enum NotionPropertyWrite: Hashable, Sendable {
    case title(String)
    case richText(String)
    case number(Decimal?)
    case select(String?)
    case multiSelect([String])
    /// "yyyy-MM-dd", or nil to clear.
    case date(String?)

    /// The request JSON, per Notion's page property value reference.
    public var json: NotionJSON {
        switch self {
        case .title(let text): ["title": .richText(text)]
        case .richText(let text): ["rich_text": .richText(text)]
        case .number(let value): ["number": value.map(NotionJSON.number) ?? .null]
        case .select(let name): ["select": name.map { ["name": .string($0)] } ?? .null]
        case .multiSelect(let names): ["multi_select": .array(names.map { ["name": .string($0)] })]
        case .date(let day): ["date": day.map { ["start": .string($0)] } ?? .null]
        }
    }
}

/// A column in a database Keaser creates.
public enum NotionNewProperty: Hashable, Sendable {
    case title
    case number(format: String)
    case select(options: [String])
    case date
    case richText

    public var json: NotionJSON {
        switch self {
        case .title: ["type": "title", "title": [:]]
        case .number(let format): ["type": "number", "number": ["format": .string(format)]]
        case .select(let options):
            ["type": "select", "select": ["options": .array(options.enumerated().map { index, name in
                ["name": .string(name), "color": .string(Self.colors[index % Self.colors.count])]
            })]]
        case .date: ["type": "date", "date": [:]]
        case .richText: ["type": "rich_text", "rich_text": [:]]
        }
    }

    /// Notion's select colours, so options are told apart at a glance there.
    static let colors = ["blue", "green", "orange", "purple", "pink", "yellow", "red", "brown", "gray"]

    public var type: NotionPropertyType {
        switch self {
        case .title: .title
        case .number: .number
        case .select: .select
        case .date: .date
        case .richText: .richText
        }
    }
}
