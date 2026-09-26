import Foundation

/// An in-memory Notion workspace with a few shared tables and pages. Stands
/// in for the network in demo launches (screenshots) and sync tests, and
/// behaves like the API where Keaser relies on it: trashed rows leave
/// queries, writes create select options, timestamps are kept to the minute,
/// new databases get one data source.
public actor NotionDemoService: NotionAPI {
    public static let workspaceName = "Home Workspace"

    private var workspace: Workspace
    /// Fixed by tests; nil follows real time.
    private var fixedNow: Date?
    private let latency: Duration
    /// Makes calls fail, to exercise error paths.
    private var failure: NotionError?

    /// `now` fixes the clock (tests); nil follows real time (demo launches).
    public init(now: Date? = nil, latency: Duration = .zero, calendar: Calendar = .current, seeded: Bool = true) {
        fixedNow = now
        self.latency = latency
        workspace = seeded ? Workspace.seeded(now: now ?? .now, calendar: calendar) : Workspace()
    }

    // MARK: Test hooks

    public func fail(with error: NotionError?) {
        failure = error
    }

    /// Moves a fixed clock: the time stamped on the next write.
    public func setNow(_ date: Date) {
        fixedNow = date
    }

    public var firstDataSourceID: String? { workspace.dataSources.first?.id }

    /// Every live row of a data source, as a query would return them.
    public func liveRows(dataSourceID: String) -> [NotionPage] {
        workspace.rows(dataSourceID).filter { !$0.isRemoved }
    }

    public func allRows(dataSourceID: String) -> [NotionPage] {
        workspace.rows(dataSourceID)
    }

    /// Edits a row as if someone changed it in Notion at `time`.
    public func editRow(id: String, at time: Date, properties: [String: NotionPropertyWrite] = [:], trash: Bool = false) throws {
        try workspace.update(id: id, properties: properties, trash: trash, at: time)
    }

    /// Adds a row as if someone created it in Notion at `time`.
    @discardableResult
    public func addRow(dataSourceID: String, at time: Date, properties: [String: NotionPropertyWrite]) throws -> NotionPage {
        try workspace.insert(dataSourceID: dataSourceID, properties: properties, at: time)
    }

    // MARK: NotionAPI

    public func currentUser() async throws -> NotionUser {
        try await pause()
        return NotionUser(id: "demo-bot", name: "Keaser", workspaceName: Self.workspaceName)
    }

    public func searchDataSources() async throws -> [NotionDataSource] {
        try await pause()
        return workspace.dataSources.filter { !$0.inTrash }
    }

    public func searchPages() async throws -> [NotionPage] {
        try await pause()
        return workspace.plainPages
    }

    public func retrieveDatabase(id: String) async throws -> NotionDatabase {
        try await pause()
        guard let database = workspace.databases.first(where: { NotionID.same($0.id, id) }) else { throw NotionError.notShared }
        return database
    }

    public func retrieveDataSource(id: String) async throws -> NotionDataSource {
        try await pause()
        return try workspace.dataSource(id)
    }

    public func queryPages(dataSourceID: String) async throws -> [NotionPage] {
        try await pause()
        _ = try workspace.dataSource(dataSourceID)
        return liveRows(dataSourceID: dataSourceID).sorted { $0.createdTime < $1.createdTime }
    }

    public func retrievePage(id: String) async throws -> NotionPage {
        try await pause()
        if let page = workspace.row(id) ?? workspace.plainPages.first(where: { NotionID.same($0.id, id) }) { return page }
        throw NotionError.notShared
    }

    public func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try await pause()
        return try workspace.insert(dataSourceID: dataSourceID, properties: properties, at: fixedNow ?? .now)
    }

    public func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try await pause()
        guard let page = workspace.row(id) else { throw NotionError.notShared }
        guard !page.isRemoved else { throw NotionError.rejected("Can't edit a page that is in the trash.") }
        return try workspace.update(id: id, properties: properties, trash: false, at: fixedNow ?? .now)
    }

    public func trashPage(id: String) async throws {
        try await pause()
        try workspace.update(id: id, properties: [:], trash: true, at: fixedNow ?? .now)
    }

    public func createDatabase(
        parentPageID: String,
        title: String,
        iconEmoji: String?,
        properties: [String: NotionNewProperty]
    ) async throws -> NotionDatabase {
        try await pause()
        guard workspace.plainPages.contains(where: { NotionID.same($0.id, parentPageID) }) else { throw NotionError.notShared }
        let schema = properties.map { name, property in
            var column = NotionPropertySchema(id: property == .title ? "title" : String(UUID().uuidString.prefix(4)), name: name, type: property.type)
            if case .number(let format) = property { column.numberFormat = format }
            if case .select(let options) = property { column.options = options }
            return column
        }
        return workspace.addTable(title: title, emoji: iconEmoji, schema: schema)
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let failure { throw failure }
    }
}

/// The demo workspace's state, as a value so the actor can build it in its
/// initializer.
private struct Workspace {
    var dataSources: [NotionDataSource] = []
    var databases: [NotionDatabase] = []
    /// Rows by normalized data source ID.
    var rowsBySource: [String: [NotionPage]] = [:]
    var plainPages: [NotionPage] = []

    func rows(_ dataSourceID: String) -> [NotionPage] {
        rowsBySource[NotionID.normalize(dataSourceID)] ?? []
    }

    func row(_ id: String) -> NotionPage? {
        for list in rowsBySource.values {
            if let page = list.first(where: { NotionID.same($0.id, id) }) { return page }
        }
        return nil
    }

    func dataSource(_ id: String) throws -> NotionDataSource {
        guard let source = dataSources.first(where: { NotionID.same($0.id, id) }) else { throw NotionError.notShared }
        return source
    }

    @discardableResult
    mutating func addTable(title: String, emoji: String?, schema: [NotionPropertySchema]) -> NotionDatabase {
        let sourceID = UUID().uuidString.lowercased()
        let databaseID = UUID().uuidString.lowercased()
        dataSources.insert(NotionDataSource(id: sourceID, title: title, iconEmoji: emoji, databaseID: databaseID, properties: schema, url: Self.url(databaseID)), at: 0)
        let database = NotionDatabase(id: databaseID, title: title, iconEmoji: emoji, dataSources: [.init(id: sourceID, name: title)], url: Self.url(databaseID))
        databases.append(database)
        rowsBySource[NotionID.normalize(sourceID)] = []
        return database
    }

    mutating func insert(dataSourceID: String, properties: [String: NotionPropertyWrite], at time: Date) throws -> NotionPage {
        let source = try dataSource(dataSourceID)
        var values: [String: NotionPropertyValue] = [:]
        for property in source.properties {
            let isText = property.type == .title || property.type == .richText
            values[property.name] = NotionPropertyValue(id: property.id, type: property.type, text: isText ? "" : nil)
        }
        for (name, write) in properties {
            values[name] = try value(for: write, named: name, in: source)
        }
        let id = UUID().uuidString.lowercased()
        let page = NotionPage(
            id: id,
            createdTime: Self.minute(time),
            lastEditedTime: Self.minute(time),
            parent: NotionParent(type: "data_source_id", databaseID: source.databaseID, dataSourceID: source.id),
            properties: values,
            url: Self.url(id)
        )
        rowsBySource[NotionID.normalize(source.id), default: []].append(page)
        return page
    }

    @discardableResult
    mutating func update(id: String, properties: [String: NotionPropertyWrite], trash: Bool, at time: Date) throws -> NotionPage {
        for (key, list) in rowsBySource {
            guard let index = list.firstIndex(where: { NotionID.same($0.id, id) }) else { continue }
            let source = try dataSource(key)
            var page = list[index]
            for (name, write) in properties {
                page.properties[name] = try value(for: write, named: name, in: source)
            }
            if trash { page.inTrash = true }
            page.lastEditedTime = Self.minute(time)
            rowsBySource[key]![index] = page
            return page
        }
        throw NotionError.notShared
    }

    private mutating func value(for write: NotionPropertyWrite, named name: String, in source: NotionDataSource) throws -> NotionPropertyValue {
        guard let property = source.property(named: name) else {
            throw NotionError.rejected("\(name) is not a property that exists.")
        }
        var value = NotionPropertyValue(id: property.id, type: property.type)
        switch (write, property.type) {
        case (.title(let text), .title), (.richText(let text), .richText): value.text = String(text.prefix(2000))
        case (.number(let number), .number): value.number = number
        case (.select(let option), .select): value.names = option.map { [$0] } ?? []
        case (.multiSelect(let options), .multiSelect): value.names = options
        case (.date(let day), .date): value.dateStart = day
        default: throw NotionError.rejected("\(name) is expected to be \(property.type.rawValue).")
        }
        // Writing an unknown option creates it, as Notion does.
        if let s = dataSources.firstIndex(where: { $0.id == source.id }),
           let p = dataSources[s].properties.firstIndex(where: { $0.id == property.id }) {
            for option in value.names where !dataSources[s].properties[p].options.contains(option) {
                dataSources[s].properties[p].options.append(option)
            }
        }
        return value
    }

    /// Notion keeps timestamps to the minute.
    static func minute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    static func url(_ id: String) -> URL? {
        URL(string: "https://www.notion.so/\(NotionID.normalize(id))")
    }

    static func seeded(now: Date, calendar: Calendar) -> Workspace {
        var workspace = Workspace()
        func day(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        }
        func table(_ title: String, _ emoji: String, hoursAgo: Int, _ schema: [NotionPropertySchema], _ entries: [[String: NotionPropertyWrite]]) {
            let database = workspace.addTable(title: title, emoji: emoji, schema: schema)
            guard let sourceID = database.dataSources.first?.id else { return }
            for (index, entry) in entries.enumerated() {
                let time = now.addingTimeInterval(Double(-(hoursAgo + entries.count - index) * 3_600))
                _ = try? workspace.insert(dataSourceID: sourceID, properties: entry, at: time)
            }
        }

        // Added oldest first; the newest table lists first, as search does.
        table("Household", "🏠", hoursAgo: 24 * 5, [
            NotionPropertySchema(id: "title", name: "Name", type: .title),
            NotionPropertySchema(id: "prc3", name: "Price", type: .number, numberFormat: "number"),
            NotionPropertySchema(id: "tag3", name: "Tags", type: .multiSelect, options: ["Cleaning", "Kitchen"]),
            NotionPropertySchema(id: "whn3", name: "When", type: .date),
        ], [
            ["Name": .title("Dish soap"), "Price": .number(Decimal(string: "3.20")), "Tags": .multiSelect(["Cleaning"]), "When": .date(day(9))],
        ])
        table("Travel Budget", "✈️", hoursAgo: 26, [
            NotionPropertySchema(id: "title", name: "Item", type: .title),
            NotionPropertySchema(id: "cst2", name: "Cost", type: .number, numberFormat: "euro"),
            NotionPropertySchema(id: "typ2", name: "Type", type: .select, options: ["Stay", "Transport", "Food"]),
            NotionPropertySchema(id: "pay2", name: "Paid With", type: .richText),
            NotionPropertySchema(id: "day2", name: "Day", type: .date),
            NotionPropertySchema(id: "trp2", name: "Trip", type: .select, options: ["Lisbon", "Kyoto"]),
        ], [
            ["Item": .title("Hotel"), "Cost": .number(240), "Type": .select("Stay"), "Paid With": .richText("Credit Card"), "Day": .date(day(30))],
            ["Item": .title("Tram pass"), "Cost": .number(Decimal(string: "6.40")), "Type": .select("Transport"), "Paid With": .richText("Cash"), "Day": .date(day(29))],
        ])
        table("Expenses", "💸", hoursAgo: 0, [
            NotionPropertySchema(id: "title", name: "Name", type: .title),
            NotionPropertySchema(id: "amt1", name: "Amount", type: .number, numberFormat: "dollar"),
            NotionPropertySchema(id: "cat1", name: "Category", type: .select, options: ["Food & Drinks", "Shopping", "Transportation", "Entertainment"]),
            NotionPropertySchema(id: "pay1", name: "Payment", type: .select, options: ["Credit Card", "Debit Card", "Cash", "E-Wallet"]),
            NotionPropertySchema(id: "dat1", name: "Date", type: .date),
            NotionPropertySchema(id: "not1", name: "Notes", type: .richText),
        ], [
            ["Name": .title("Dinner with friends"), "Amount": .number(Decimal(string: "48.20")), "Category": .select("Food & Drinks"), "Payment": .select("Cash"), "Date": .date(day(6))],
            ["Name": .title("Netflix"), "Amount": .number(Decimal(string: "15.49")), "Category": .select("Entertainment"), "Payment": .select("Credit Card"), "Date": .date(day(4))],
            ["Name": .title("Train ticket"), "Amount": .number(12), "Category": .select("Transportation"), "Payment": .select("E-Wallet"), "Date": .date(day(2))],
            ["Name": .title("Groceries"), "Amount": .number(Decimal(string: "62.18")), "Category": .select("Shopping"), "Payment": .select("Debit Card"), "Date": .date(day(1))],
            ["Name": .title("Coffee"), "Amount": .number(Decimal(string: "4.50")), "Category": .select("Food & Drinks"), "Payment": .select("Credit Card"), "Date": .date(day(0))],
            // Notion databases often carry an empty row; sync must skip it.
            [:],
        ])

        for (index, entry) in [("Home", "🏡"), ("Finances", "📒"), ("Projects", "🗂️")].enumerated() {
            let id = UUID().uuidString.lowercased()
            let time = minute(now.addingTimeInterval(Double(-(index + 1) * 86_400)))
            workspace.plainPages.append(NotionPage(
                id: id,
                createdTime: time,
                lastEditedTime: time,
                parent: .workspace,
                properties: ["title": NotionPropertyValue(id: "title", type: .title, text: entry.0)],
                iconEmoji: entry.1,
                url: url(id)
            ))
        }
        return workspace
    }
}

/// The demo workspace seen through one token. Tokens that start with "bad"
/// are refused the way Notion refuses a revoked token, so the error path of
/// the connect flow can be shown offline.
public struct NotionDemoClient: NotionAPI {
    public let service: NotionDemoService
    public let token: String

    public init(service: NotionDemoService, token: String) {
        self.service = service
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func check() throws {
        if token.isEmpty || token.lowercased().hasPrefix("bad") { throw NotionError.invalidToken }
    }

    public func currentUser() async throws -> NotionUser { try check(); return try await service.currentUser() }
    public func searchDataSources() async throws -> [NotionDataSource] { try check(); return try await service.searchDataSources() }
    public func searchPages() async throws -> [NotionPage] { try check(); return try await service.searchPages() }
    public func retrieveDatabase(id: String) async throws -> NotionDatabase { try check(); return try await service.retrieveDatabase(id: id) }
    public func retrieveDataSource(id: String) async throws -> NotionDataSource { try check(); return try await service.retrieveDataSource(id: id) }
    public func queryPages(dataSourceID: String) async throws -> [NotionPage] { try check(); return try await service.queryPages(dataSourceID: dataSourceID) }
    public func retrievePage(id: String) async throws -> NotionPage { try check(); return try await service.retrievePage(id: id) }

    public func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try check()
        return try await service.createPage(dataSourceID: dataSourceID, properties: properties)
    }

    public func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try check()
        return try await service.updatePage(id: id, properties: properties)
    }

    public func trashPage(id: String) async throws {
        try check()
        try await service.trashPage(id: id)
    }

    public func createDatabase(parentPageID: String, title: String, iconEmoji: String?, properties: [String: NotionNewProperty]) async throws -> NotionDatabase {
        try check()
        return try await service.createDatabase(parentPageID: parentPageID, title: title, iconEmoji: iconEmoji, properties: properties)
    }
}
