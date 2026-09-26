import Foundation

// Response objects from the Notion API, reduced to what Keaser reads. Every
// decoder is tolerant: unknown property types, icon kinds and parents decode
// to "other" instead of failing the whole response.

public enum NotionID {
    /// Notion returns IDs with hyphens but accepts them either way, and links
    /// omit them. Compare IDs only through this.
    public static func normalize(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return normalize(a) == normalize(b)
    }
}

/// A property's type in a data source schema or a page, e.g. "title".
public struct NotionPropertyType: RawRepresentable, Hashable, Sendable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let title = NotionPropertyType(rawValue: "title")
    public static let richText = NotionPropertyType(rawValue: "rich_text")
    public static let number = NotionPropertyType(rawValue: "number")
    public static let select = NotionPropertyType(rawValue: "select")
    public static let multiSelect = NotionPropertyType(rawValue: "multi_select")
    public static let status = NotionPropertyType(rawValue: "status")
    public static let date = NotionPropertyType(rawValue: "date")
    public static let formula = NotionPropertyType(rawValue: "formula")

    /// How the type reads in the property pickers.
    public var displayName: String {
        switch self {
        case .title: "Title"
        case .richText: "Text"
        case .number: "Number"
        case .select: "Select"
        case .multiSelect: "Multi-select"
        case .status: "Status"
        case .date: "Date"
        case .formula: "Formula"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// One column of a data source schema.
public struct NotionPropertySchema: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: NotionPropertyType
    /// Number columns only: "dollar", "euro", "number"...
    public var numberFormat: String?
    /// Select, multi-select and status columns: the option names.
    public var options: [String]

    public init(id: String, name: String, type: NotionPropertyType, numberFormat: String? = nil, options: [String] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.numberFormat = numberFormat
        self.options = options
    }
}

/// Where an object lives.
public struct NotionParent: Hashable, Sendable, Decodable {
    public var type: String
    public var pageID: String?
    public var databaseID: String?
    public var dataSourceID: String?
    public var blockID: String?

    public init(type: String, pageID: String? = nil, databaseID: String? = nil, dataSourceID: String? = nil, blockID: String? = nil) {
        self.type = type
        self.pageID = pageID
        self.databaseID = databaseID
        self.dataSourceID = dataSourceID
        self.blockID = blockID
    }

    public static let workspace = NotionParent(type: "workspace")

    enum CodingKeys: String, CodingKey {
        case type
        case pageID = "page_id"
        case databaseID = "database_id"
        case dataSourceID = "data_source_id"
        case blockID = "block_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        pageID = try c.decodeIfPresent(String.self, forKey: .pageID)
        databaseID = try c.decodeIfPresent(String.self, forKey: .databaseID)
        dataSourceID = try c.decodeIfPresent(String.self, forKey: .dataSourceID)
        blockID = try c.decodeIfPresent(String.self, forKey: .blockID)
    }
}

/// The token's user: the connection's bot for an internal connection, or
/// the person for a personal access token.
public struct NotionUser: Hashable, Sendable, Decodable {
    public var id: String
    public var name: String?
    public var workspaceName: String?

    public init(id: String, name: String?, workspaceName: String?) {
        self.id = id
        self.name = name
        self.workspaceName = workspaceName
    }

    enum CodingKeys: String, CodingKey { case id, name, bot }
    enum BotKeys: String, CodingKey { case workspaceName = "workspace_name" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        if c.contains(.bot), let bot = try? c.nestedContainer(keyedBy: BotKeys.self, forKey: .bot) {
            workspaceName = try bot.decodeIfPresent(String.self, forKey: .workspaceName)
        } else {
            workspaceName = nil
        }
    }
}

/// A table of rows: what Keaser links an account to.
public struct NotionDataSource: Hashable, Sendable, Identifiable, Decodable {
    public var id: String
    public var title: String
    public var iconEmoji: String?
    /// The database that contains this data source.
    public var databaseID: String?
    /// Title property first, then the rest by name.
    public var properties: [NotionPropertySchema]
    public var inTrash: Bool
    public var url: URL?

    public init(
        id: String,
        title: String,
        iconEmoji: String? = nil,
        databaseID: String? = nil,
        properties: [NotionPropertySchema],
        inTrash: Bool = false,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.iconEmoji = iconEmoji
        self.databaseID = databaseID
        self.properties = NotionDataSource.ordered(properties)
        self.inTrash = inTrash
        self.url = url
    }

    /// "Untitled" when the table has no name, as Notion shows it.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    public func property(named name: String?) -> NotionPropertySchema? {
        guard let name else { return nil }
        return properties.first { $0.name == name }
    }

    static func ordered(_ properties: [NotionPropertySchema]) -> [NotionPropertySchema] {
        properties.sorted { a, b in
            if (a.type == .title) != (b.type == .title) { return a.type == .title }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, icon, parent, properties, url
        case inTrash = "in_trash"
        case archived
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent([NotionRichText].self, forKey: .title))?.plainText ?? ""
        iconEmoji = (try? c.decodeIfPresent(NotionIcon.self, forKey: .icon))?.emoji
        let parent = try? c.decodeIfPresent(NotionParent.self, forKey: .parent)
        databaseID = parent?.databaseID
        let schema = (try? c.decodeIfPresent([String: SchemaEntry].self, forKey: .properties)) ?? [:]
        properties = NotionDataSource.ordered(schema.map { name, entry in
            NotionPropertySchema(id: entry.id ?? name, name: entry.name ?? name, type: entry.type, numberFormat: entry.numberFormat, options: entry.options)
        })
        inTrash = try c.decodeIfPresent(Bool.self, forKey: .inTrash) ?? c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        url = try? c.decodeIfPresent(URL.self, forKey: .url)
    }

    private struct SchemaEntry: Decodable {
        var id: String?
        var name: String?
        var type: NotionPropertyType
        var numberFormat: String?
        var options: [String]

        enum CodingKeys: String, CodingKey {
            case id, name, type, number, select, status
            case multiSelect = "multi_select"
        }
        struct NumberConfig: Decodable { var format: String? }
        struct OptionsConfig: Decodable { var options: [Option]? }
        struct Option: Decodable { var name: String }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            type = NotionPropertyType(rawValue: try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown")
            numberFormat = (try? c.decodeIfPresent(NumberConfig.self, forKey: .number))?.format
            let config: OptionsConfig?
            switch type {
            case .select: config = try? c.decodeIfPresent(OptionsConfig.self, forKey: .select)
            case .status: config = try? c.decodeIfPresent(OptionsConfig.self, forKey: .status)
            case .multiSelect: config = try? c.decodeIfPresent(OptionsConfig.self, forKey: .multiSelect)
            default: config = nil
            }
            options = config?.options?.map(\.name) ?? []
        }
    }
}

/// The container the user shares and creates. Rows live in its data sources.
public struct NotionDatabase: Hashable, Sendable, Identifiable, Decodable {
    public struct DataSourceReference: Hashable, Sendable, Decodable {
        public var id: String
        public var name: String?
        public init(id: String, name: String?) {
            self.id = id
            self.name = name
        }
    }

    public var id: String
    public var title: String
    public var iconEmoji: String?
    public var dataSources: [DataSourceReference]
    public var url: URL?

    public init(id: String, title: String, iconEmoji: String? = nil, dataSources: [DataSourceReference], url: URL? = nil) {
        self.id = id
        self.title = title
        self.iconEmoji = iconEmoji
        self.dataSources = dataSources
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case id, title, icon, url
        case dataSources = "data_sources"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent([NotionRichText].self, forKey: .title))?.plainText ?? ""
        iconEmoji = (try? c.decodeIfPresent(NotionIcon.self, forKey: .icon))?.emoji
        dataSources = try c.decodeIfPresent([DataSourceReference].self, forKey: .dataSources) ?? []
        url = try? c.decodeIfPresent(URL.self, forKey: .url)
    }
}

/// A row of a data source, or a plain page (the parent of a new database).
public struct NotionPage: Hashable, Sendable, Identifiable, Decodable {
    public var id: String
    public var createdTime: Date
    /// Notion stores this to the minute, so it is only good for ordering
    /// edits that are at least a minute apart.
    public var lastEditedTime: Date
    public var inTrash: Bool
    /// Archived pages (separate from trash) drop out of queries too.
    public var isArchived: Bool
    public var parent: NotionParent
    /// Keyed by property name.
    public var properties: [String: NotionPropertyValue]
    public var iconEmoji: String?
    public var url: URL?

    public init(
        id: String,
        createdTime: Date,
        lastEditedTime: Date,
        inTrash: Bool = false,
        isArchived: Bool = false,
        parent: NotionParent,
        properties: [String: NotionPropertyValue],
        iconEmoji: String? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.createdTime = createdTime
        self.lastEditedTime = lastEditedTime
        self.inTrash = inTrash
        self.isArchived = isArchived
        self.parent = parent
        self.properties = properties
        self.iconEmoji = iconEmoji
        self.url = url
    }

    /// The plain text of the page's title property.
    public var title: String {
        properties.values.first { $0.type == .title }?.text ?? ""
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// True when the page no longer belongs in its data source's rows.
    public var isRemoved: Bool { inTrash || isArchived }

    enum CodingKeys: String, CodingKey {
        case id, parent, properties, icon, url, archived
        case createdTime = "created_time"
        case lastEditedTime = "last_edited_time"
        case inTrash = "in_trash"
        case isArchived = "is_archived"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdTime = try c.decode(Date.self, forKey: .createdTime)
        lastEditedTime = try c.decodeIfPresent(Date.self, forKey: .lastEditedTime) ?? createdTime
        inTrash = try c.decodeIfPresent(Bool.self, forKey: .inTrash) ?? c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        parent = try c.decodeIfPresent(NotionParent.self, forKey: .parent) ?? NotionParent(type: "unknown")
        let values = try c.decodeIfPresent([String: NotionPropertyValue].self, forKey: .properties) ?? [:]
        properties = values
        iconEmoji = (try? c.decodeIfPresent(NotionIcon.self, forKey: .icon))?.emoji
        url = try? c.decodeIfPresent(URL.self, forKey: .url)
    }
}

/// A page's value for one property, flattened to what Keaser can use.
public struct NotionPropertyValue: Hashable, Sendable, Decodable {
    public var id: String
    public var type: NotionPropertyType
    /// Title, rich text, and string formulas: the joined plain text.
    public var text: String?
    public var number: Decimal?
    /// Select and status (zero or one) and multi-select option names.
    public var names: [String]
    /// A date property's start: "2026-09-15" or a full ISO 8601 date-time.
    public var dateStart: String?

    public init(id: String, type: NotionPropertyType, text: String? = nil, number: Decimal? = nil, names: [String] = [], dateStart: String? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.number = number
        self.names = names
        self.dateStart = dateStart
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, number, select, status, date, formula
        case richText = "rich_text"
        case multiSelect = "multi_select"
    }

    private struct Option: Decodable { var name: String }
    private struct DateValue: Decodable { var start: String? }
    private struct Formula: Decodable {
        var type: String?
        var string: String?
        var number: Decimal?
        var date: DateValue?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        type = NotionPropertyType(rawValue: try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown")
        text = nil
        number = nil
        names = []
        dateStart = nil
        switch type {
        case .title:
            text = (try? c.decodeIfPresent([NotionRichText].self, forKey: .title))?.plainText ?? ""
        case .richText:
            text = (try? c.decodeIfPresent([NotionRichText].self, forKey: .richText))?.plainText ?? ""
        case .number:
            number = try? c.decodeIfPresent(Decimal.self, forKey: .number)
        case .select:
            names = ((try? c.decodeIfPresent(Option.self, forKey: .select)) ?? nil).map { [$0.name] } ?? []
        case .status:
            names = ((try? c.decodeIfPresent(Option.self, forKey: .status)) ?? nil).map { [$0.name] } ?? []
        case .multiSelect:
            names = ((try? c.decodeIfPresent([Option].self, forKey: .multiSelect)) ?? nil)?.map(\.name) ?? []
        case .date:
            dateStart = ((try? c.decodeIfPresent(DateValue.self, forKey: .date)) ?? nil)?.start
        case .formula:
            if let formula = (try? c.decodeIfPresent(Formula.self, forKey: .formula)) ?? nil {
                text = formula.string
                number = formula.number
                dateStart = formula.date?.start
            }
        default:
            break
        }
    }
}

/// A run of rich text. Only the plain text matters to Keaser.
struct NotionRichText: Decodable, Hashable, Sendable {
    var plainText: String

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
        case text
    }

    struct Text: Decodable { var content: String? }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plainText = try c.decodeIfPresent(String.self, forKey: .plainText)
            ?? (try? c.decodeIfPresent(Text.self, forKey: .text))??.content
            ?? ""
    }
}

extension [NotionRichText] {
    var plainText: String { map(\.plainText).joined() }
}

/// Only emoji icons are shown; file and custom icons read as nil.
struct NotionIcon: Decodable {
    var emoji: String?

    enum CodingKeys: String, CodingKey { case type, emoji }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type)
        emoji = type == "emoji" ? try c.decodeIfPresent(String.self, forKey: .emoji) : nil
    }
}

/// One page of a paginated list. Results that fail to decode (partial
/// objects the token cannot fully read) are skipped, not fatal.
struct NotionList<Element: Decodable>: Decodable {
    var results: [Element]
    var nextCursor: String?
    var hasMore: Bool
    /// The query hit Notion's per-query result cap (10,000 rows).
    var isIncomplete: Bool

    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case requestStatus = "request_status"
    }

    struct RequestStatus: Decodable { var type: String? }

    private struct Lossy: Decodable {
        var value: Element?
        init(from decoder: any Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try c.decodeIfPresent([Lossy].self, forKey: .results) ?? []).compactMap(\.value)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        isIncomplete = (try? c.decodeIfPresent(RequestStatus.self, forKey: .requestStatus))??.type == "incomplete"
    }
}

/// Notion timestamps: ISO 8601, usually with milliseconds.
enum NotionTimestamp {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
        return try? Date.ISO8601FormatStyle().parse(string)
    }

    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let string = try c.decode(String.self)
            guard let date = parse(string) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unreadable date \(string)")
            }
            return date
        }
        return decoder
    }
}
