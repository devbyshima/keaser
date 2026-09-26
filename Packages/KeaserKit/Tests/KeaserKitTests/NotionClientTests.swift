import Foundation
import Synchronization
import Testing
@testable import KeaserKit

/// Replays canned responses and records every request. No network.
final class StubTransport: NotionTransport {
    struct Reply: Sendable {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let state = Mutex<(replies: [Reply], requests: [URLRequest])>(([], []))

    init(_ replies: [Reply]) {
        state.withLock { $0.replies = replies }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reply = state.withLock { state -> Reply? in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

/// Records sleeps instead of sleeping.
final class SleepRecorder: Sendable {
    private let slept = Mutex<[Duration]>([])
    var durations: [Duration] { slept.withLock { $0 } }
    var sleep: @Sendable (Duration) async throws -> Void {
        { duration in self.record(duration) }
    }
    private func record(_ duration: Duration) {
        slept.withLock { $0.append(duration) }
    }
}

func body(of request: URLRequest) throws -> NotionJSON {
    try JSONDecoder().decode(NotionJSON.self, from: try #require(request.httpBody))
}

enum NotionFixtures {
    static let pageJSON = """
    {
      "object": "page",
      "id": "59833787-2cf9-4fdf-8782-e53db20768a5",
      "created_time": "2026-09-20T09:12:00.000Z",
      "last_edited_time": "2026-09-21T10:30:00.000Z",
      "in_trash": false,
      "is_archived": false,
      "is_locked": false,
      "icon": {"type": "emoji", "emoji": "☕️"},
      "parent": {"type": "data_source_id", "data_source_id": "ds-1", "database_id": "db-1"},
      "url": "https://www.notion.so/598337872cf94fdf8782e53db20768a5",
      "properties": {
        "Name": {"id": "title", "type": "title", "title": [
          {"type": "text", "text": {"content": "Coffee ", "link": null}, "plain_text": "Coffee ", "href": null},
          {"type": "text", "text": {"content": "beans", "link": null}, "plain_text": "beans", "href": null}
        ]},
        "Amount": {"id": "amt1", "type": "number", "number": 16.99},
        "Category": {"id": "cat1", "type": "select", "select": {"id": "x", "name": "Food & Drinks", "color": "red"}},
        "Payment": {"id": "pay1", "type": "rich_text", "rich_text": [{"type": "text", "text": {"content": "Cash"}, "plain_text": "Cash"}]},
        "Tags": {"id": "tag1", "type": "multi_select", "multi_select": [{"id": "a", "name": "Work", "color": "blue"}]},
        "Date": {"id": "dat1", "type": "date", "date": {"start": "2026-09-20", "end": null, "time_zone": null}},
        "Done": {"id": "chk1", "type": "checkbox", "checkbox": true}
      }
    }
    """

    static let dataSourceJSON = """
    {
      "object": "data_source",
      "id": "ds-1",
      "title": [{"type": "text", "text": {"content": "Expenses"}, "plain_text": "Expenses"}],
      "icon": {"type": "emoji", "emoji": "💸"},
      "parent": {"type": "database_id", "database_id": "db-1"},
      "database_parent": {"type": "page_id", "page_id": "p-1"},
      "in_trash": false,
      "url": "https://www.notion.so/db1",
      "properties": {
        "Name": {"id": "title", "name": "Name", "type": "title", "title": {}},
        "Amount": {"id": "amt1", "name": "Amount", "type": "number", "number": {"format": "dollar"}},
        "Category": {"id": "cat1", "name": "Category", "type": "select", "select": {"options": [{"id": "1", "name": "Food & Drinks", "color": "red"}]}},
        "Tags": {"id": "tag1", "name": "Tags", "type": "multi_select", "multi_select": {"options": [{"id": "2", "name": "Work", "color": "blue"}]}},
        "Date": {"id": "dat1", "name": "Date", "type": "date", "date": {}},
        "Link": {"id": "rel1", "name": "Link", "type": "relation", "relation": {"data_source_id": "x"}}
      }
    }
    """

    static func list(_ items: [String], next: String? = nil, incomplete: Bool = false) -> String {
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        let status = incomplete ? #", "request_status": {"type": "incomplete", "incomplete_reason": "query_result_limit_reached"}"# : ""
        return #"{"object": "list", "results": [\#(items.joined(separator: ","))], "next_cursor": \#(cursor), "has_more": \#(next != nil)\#(status)}"#
    }

    static func row(id: String, created: String, title: String = "Row") -> String {
        """
        {"object": "page", "id": "\(id)", "created_time": "\(created)", "last_edited_time": "\(created)",
         "in_trash": false, "parent": {"type": "data_source_id", "data_source_id": "ds-1", "database_id": "db-1"},
         "properties": {"Name": {"id": "title", "type": "title", "title": [{"plain_text": "\(title)"}]}}}
        """
    }

    static func error(_ status: Int, _ code: String, _ message: String) -> StubTransport.Reply {
        StubTransport.Reply(status: status, body: #"{"object": "error", "status": \#(status), "code": "\#(code)", "message": "\#(message)"}"#)
    }
}

struct NotionClientTests {
    private func client(_ replies: [StubTransport.Reply], sleeper: SleepRecorder = SleepRecorder()) -> (NotionClient, StubTransport) {
        let transport = StubTransport(replies)
        return (NotionClient(token: "  ntn_secret\n", transport: transport, sleep: sleeper.sleep), transport)
    }

    @Test func sendsAuthVersionAndJSONHeaders() async throws {
        let (client, transport) = client([.init(status: 200, body: NotionFixtures.pageJSON)])
        _ = try await client.createPage(dataSourceID: "ds-1", properties: ["Name": .title("Coffee")])
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.notion.com/v1/pages")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ntn_secret")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2026-03-11")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func createPageBodyUsesDataSourceParentAndExactValues() async throws {
        let (client, transport) = client([.init(status: 200, body: NotionFixtures.pageJSON)])
        _ = try await client.createPage(dataSourceID: "ds-1", properties: [
            "Name": .title("Coffee"),
            "Amount": .number(Decimal(string: "16.99")),
            "Category": .select("Food & Drinks"),
            "Payment": .richText("Cash"),
            "Tags": .multiSelect(["Work"]),
            "Date": .date("2026-09-20"),
            "Empty": .select(nil),
        ])
        let raw = String(decoding: try #require(transport.requests.first?.httpBody), as: UTF8.self)
        #expect(raw.contains(#""number":16.99"#))
        let json = try body(of: try #require(transport.requests.first))
        #expect(json["parent"] == ["type": "data_source_id", "data_source_id": "ds-1"])
        let properties = try #require(json["properties"])
        #expect(properties["Name"] == ["title": [["type": "text", "text": ["content": "Coffee"]]]])
        #expect(properties["Category"] == ["select": ["name": "Food & Drinks"]])
        #expect(properties["Payment"] == ["rich_text": [["type": "text", "text": ["content": "Cash"]]]])
        #expect(properties["Tags"] == ["multi_select": [["name": "Work"]]])
        #expect(properties["Date"] == ["date": ["start": "2026-09-20"]])
        #expect(properties["Empty"] == ["select": nil])
    }

    @Test func trashUsesInTrashNotArchived() async throws {
        let (client, transport) = client([.init(status: 200, body: NotionFixtures.pageJSON)])
        try await client.trashPage(id: "page-1")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path() == "/v1/pages/page-1")
        #expect(try body(of: request) == ["in_trash": true])
    }

    @Test func updateDataSourcePatchesTheSchema() async throws {
        let (client, transport) = client([.init(status: 200, body: NotionFixtures.dataSourceJSON)])
        let updated = try await client.updateDataSource(id: "ds-1", properties: ["Keaser ID": .richText])
        #expect(updated.id == "ds-1")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path() == "/v1/data_sources/ds-1")
        #expect(try body(of: request) == ["properties": ["Keaser ID": ["type": "rich_text", "rich_text": [:]]]])
    }

    @Test func createDatabaseNestsSchemaUnderInitialDataSource() async throws {
        let database = #"{"object": "database", "id": "db-9", "title": [{"plain_text": "Keaser"}], "data_sources": [{"id": "ds-9", "name": "Keaser"}]}"#
        let (client, transport) = client([.init(status: 200, body: database)])
        let created = try await client.createDatabase(
            parentPageID: "page-1",
            title: "Keaser Expenses",
            iconEmoji: "💸",
            properties: NotionKeaserSchema.properties(currencyCode: "EUR", categories: ["Food, Drinks"], paymentMethods: ["Cash"])
        )
        #expect(created.dataSources.map(\.id) == ["ds-9"])
        let json = try body(of: try #require(transport.requests.first))
        #expect(json["parent"] == ["type": "page_id", "page_id": "page-1"])
        #expect(json["icon"] == ["type": "emoji", "emoji": "💸"])
        let schema = try #require(json["initial_data_source"]?["properties"])
        #expect(schema["Name"] == ["type": "title", "title": [:]])
        #expect(schema["Amount"] == ["type": "number", "number": ["format": "euro"]])
        #expect(schema["Date"] == ["type": "date", "date": [:]])
        #expect(schema["Keaser ID"] == ["type": "rich_text", "rich_text": [:]])
        #expect(schema["Category"]?["select"]?["options"]?.arrayValue?.first?["name"] == "Food Drinks")
    }

    @Test func searchFiltersOnDataSourcesAndFollowsCursors() async throws {
        let first = NotionFixtures.list([NotionFixtures.dataSourceJSON], next: "cursor-2")
        let second = NotionFixtures.list([NotionFixtures.dataSourceJSON.replacingOccurrences(of: #""id": "ds-1""#, with: #""id": "ds-2""#)])
        let (client, transport) = client([.init(status: 200, body: first), .init(status: 200, body: second)])
        let sources = try await client.searchDataSources()
        #expect(sources.map(\.id) == ["ds-1", "ds-2"])
        let bodies = try transport.requests.map(body(of:))
        #expect(bodies[0]["filter"] == ["property": "object", "value": "data_source"])
        #expect(bodies[0]["start_cursor"] == nil)
        #expect(bodies[1]["start_cursor"] == "cursor-2")
        #expect(bodies[0]["page_size"] == 100)
    }

    @Test func queryPaginatesAndWindowsPastTheResultCap() async throws {
        let a = NotionFixtures.row(id: "a", created: "2026-01-01T10:00:00.000Z")
        let b = NotionFixtures.row(id: "b", created: "2026-01-02T10:00:00.000Z")
        let c = NotionFixtures.row(id: "c", created: "2026-01-03T10:00:00.000Z")
        let (client, transport) = client([
            .init(status: 200, body: NotionFixtures.list([a], next: "n2")),
            // The cap is reached: has_more is false but the result is incomplete.
            .init(status: 200, body: NotionFixtures.list([b], incomplete: true)),
            // The next window starts at b's created_time, so b comes back.
            .init(status: 200, body: NotionFixtures.list([b, c])),
        ])
        let pages = try await client.queryPages(dataSourceID: "ds-1")
        #expect(pages.map(\.id) == ["a", "b", "c"])
        let requests = transport.requests
        #expect(requests.count == 3)
        #expect(requests[0].url?.path() == "/v1/data_sources/ds-1/query")
        let bodies = try requests.map(body(of:))
        #expect(bodies[0]["sorts"] == [["timestamp": "created_time", "direction": "ascending"]])
        #expect(bodies[0]["result_type"] == "page")
        #expect(bodies[1]["start_cursor"] == "n2")
        #expect(bodies[2]["start_cursor"] == nil)
        #expect(bodies[2]["filter"] == ["timestamp": "created_time", "created_time": ["on_or_after": "2026-01-02T10:00:00.000Z"]])
    }

    @Test func retriesRateLimitsAfterRetryAfter() async throws {
        let sleeper = SleepRecorder()
        let (client, transport) = client([
            .init(status: 429, body: #"{"object":"error","status":429,"code":"rate_limited","message":"You have been rate limited."}"#, headers: ["Retry-After": "2"]),
            .init(status: 200, body: #"{"object":"user","id":"bot-1","type":"bot","bot":{"workspace_name":"Studio"}}"#),
        ], sleeper: sleeper)
        let user = try await client.currentUser()
        #expect(user.workspaceName == "Studio")
        #expect(transport.requests.count == 2)
        #expect(sleeper.durations == [.seconds(2)])
    }

    @Test func givesUpOnRateLimitsAfterMaxAttempts() async throws {
        let sleeper = SleepRecorder()
        let limited = NotionFixtures.error(429, "rate_limited", "Slow down")
        let (client, transport) = client(Array(repeating: limited, count: 6), sleeper: sleeper)
        await #expect(throws: NotionError.rateLimited) { try await client.currentUser() }
        #expect(transport.requests.count == NotionClient.maxAttempts)
        // No Retry-After header: exponential backoff.
        #expect(sleeper.durations == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test func createIsNotRetriedOnServerErrorsButUpdateIs() async throws {
        let unavailable = NotionFixtures.error(503, "service_unavailable", "Notion is unavailable")
        let (createClient, createTransport) = client([unavailable, .init(status: 200, body: NotionFixtures.pageJSON)])
        await #expect(throws: NotionError.unavailable(status: 503)) {
            try await createClient.createPage(dataSourceID: "ds-1", properties: [:])
        }
        #expect(createTransport.requests.count == 1)

        let (updateClient, updateTransport) = client([unavailable, .init(status: 200, body: NotionFixtures.pageJSON)])
        _ = try await updateClient.updatePage(id: "p", properties: [:])
        #expect(updateTransport.requests.count == 2)
    }

    @Test(arguments: [
        (NotionFixtures.error(401, "unauthorized", "API token is invalid."), NotionError.invalidToken),
        (NotionFixtures.error(404, "object_not_found", "Could not find database"), NotionError.notShared),
        (NotionFixtures.error(403, "restricted_resource", "No access"), NotionError.notShared),
        (NotionFixtures.error(400, "validation_error", "Amount is expected to be number."), NotionError.rejected("Amount is expected to be number.")),
    ])
    func mapsErrorResponses(reply: StubTransport.Reply, expected: NotionError) async throws {
        let (client, _) = client([reply])
        await #expect(throws: expected) { try await client.retrieveDataSource(id: "ds-1") }
        #expect(expected.errorDescription?.isEmpty == false)
    }

    @Test func networkFailuresBecomeReadableErrors() async throws {
        let sleeper = SleepRecorder()
        let (client, _) = client([], sleeper: sleeper)
        do {
            _ = try await client.currentUser()
            Issue.record("Expected a network error")
        } catch let error as NotionError {
            guard case .network = error else { Issue.record("Unexpected \(error)"); return }
            #expect(error.errorDescription == "Couldn't reach Notion. Check your internet connection and try again.")
        }
    }

    @Test func decodesPagesTolerantly() throws {
        let page = try NotionTimestamp.decoder().decode(NotionPage.self, from: Data(NotionFixtures.pageJSON.utf8))
        #expect(page.title == "Coffee beans")
        #expect(page.iconEmoji == "☕️")
        #expect(page.parent.dataSourceID == "ds-1")
        #expect(page.properties["Amount"]?.number == Decimal(string: "16.99"))
        #expect(page.properties["Category"]?.names == ["Food & Drinks"])
        #expect(page.properties["Payment"]?.text == "Cash")
        #expect(page.properties["Tags"]?.names == ["Work"])
        #expect(page.properties["Date"]?.dateStart == "2026-09-20")
        #expect(page.properties["Done"]?.type.rawValue == "checkbox")
        #expect(page.lastEditedTime == Date(timeIntervalSince1970: 1_789_986_600))
    }

    @Test func decodesDataSourceSchemas() throws {
        let source = try NotionTimestamp.decoder().decode(NotionDataSource.self, from: Data(NotionFixtures.dataSourceJSON.utf8))
        #expect(source.title == "Expenses")
        #expect(source.iconEmoji == "💸")
        #expect(source.databaseID == "db-1")
        #expect(source.properties.first?.type == .title)
        #expect(source.property(named: "Amount")?.numberFormat == "dollar")
        #expect(source.property(named: "Tags")?.options == ["Work"])
        #expect(source.property(named: "Link")?.type.rawValue == "relation")
    }

    @Test func skipsListResultsItCannotRead() throws {
        let list = NotionFixtures.list([#"{"object": "page", "id": "partial"}"#, NotionFixtures.row(id: "ok", created: "2026-01-01T00:00:00Z")])
        let decoded = try NotionTimestamp.decoder().decode(NotionList<NotionPage>.self, from: Data(list.utf8))
        #expect(decoded.results.map(\.id) == ["ok"])
    }
}
