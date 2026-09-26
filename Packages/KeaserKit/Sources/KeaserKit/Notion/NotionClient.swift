import Foundation

/// Sends one HTTP request. Injectable so tests never touch the network.
public protocol NotionTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionNotionTransport: NotionTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// The Notion REST API, authenticated with an internal connection's
/// installation access token (or a personal access token; both are sent as
/// a bearer token).
///
/// Pinned to Notion-Version `2026-03-11`, the newest version as of September
/// 2026, on purpose:
/// - 2025-09-03 split databases into a container plus data sources. Schemas,
///   queries and new rows now go through `/v1/data_sources/{id}`, search
///   filters on `"data_source"`, and a new page's parent is a
///   `data_source_id`. Keaser is built on that model, so nothing older fits.
/// - 2026-03-11 keeps that model and removes the deprecated `archived` flag
///   in favour of `in_trash`, which is how Keaser trashes pages. Its other
///   changes (block positions, meeting notes) do not touch Keaser.
/// Bump this only after reading the next upgrade guide.
public struct NotionClient: NotionAPI {
    public static let version = "2026-03-11"
    public static let baseURL = URL(string: "https://api.notion.com/v1/")!
    /// One try plus three retries for rate limits and transient failures.
    public static let maxAttempts = 4

    private let token: String
    private let transport: any NotionTransport
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        token: String,
        transport: any NotionTransport = URLSessionNotionTransport(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.sleep = sleep
    }

    // MARK: NotionAPI

    public func currentUser() async throws -> NotionUser {
        try await send("GET", "users/me", retryable: true)
    }

    public func searchDataSources() async throws -> [NotionDataSource] {
        let sources: [NotionDataSource] = try await paginate(maxPages: 10) { cursor in
            try await send("POST", "search", body: Self.searchBody(object: "data_source", cursor: cursor), retryable: true)
        }
        return sources.filter { !$0.inTrash }
    }

    public func searchPages() async throws -> [NotionPage] {
        let pages: [NotionPage] = try await paginate(maxPages: 3) { cursor in
            try await send("POST", "search", body: Self.searchBody(object: "page", cursor: cursor), retryable: true)
        }
        // Rows of a table make poor homes for a new database.
        return pages.filter { page in
            !page.isRemoved && page.parent.type != "data_source_id" && page.parent.type != "database_id"
        }
    }

    public func retrieveDatabase(id: String) async throws -> NotionDatabase {
        try await send("GET", "databases/\(id)", retryable: true)
    }

    public func retrieveDataSource(id: String) async throws -> NotionDataSource {
        try await send("GET", "data_sources/\(id)", retryable: true)
    }

    /// Follows `next_cursor` to the end. A single query stops at 10,000 rows
    /// and reports `request_status: incomplete`; when that happens the next
    /// query starts at the last row's `created_time` (rows sorted by it), and
    /// rows on the boundary are de-duplicated by ID.
    public func queryPages(dataSourceID: String) async throws -> [NotionPage] {
        var order: [String] = []
        var rows: [String: NotionPage] = [:]
        var windowStart: Date?
        while true {
            var cursor: String?
            var limitReached = false
            var lastCreated: Date?
            repeat {
                let list: NotionList<NotionPage> = try await send(
                    "POST", "data_sources/\(dataSourceID)/query",
                    body: Self.queryBody(cursor: cursor, createdOnOrAfter: windowStart),
                    retryable: true
                )
                for page in list.results {
                    if rows.updateValue(page, forKey: page.id) == nil { order.append(page.id) }
                    lastCreated = page.createdTime
                }
                if list.isIncomplete { limitReached = true }
                cursor = list.hasMore ? list.nextCursor : nil
            } while cursor != nil
            guard limitReached else { break }
            // Notion stores created_time to the minute; if one minute holds
            // more than the cap the window cannot move, so stop there.
            guard let lastCreated, lastCreated != windowStart else { break }
            windowStart = lastCreated
        }
        return order.compactMap { rows[$0] }
    }

    public func retrievePage(id: String) async throws -> NotionPage {
        try await send("GET", "pages/\(id)", retryable: true)
    }

    public func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        let body: NotionJSON = [
            "parent": ["type": "data_source_id", "data_source_id": .string(dataSourceID)],
            "properties": .object(properties.mapValues(\.json)),
        ]
        // Not retried on 5xx: the page may have been created before the
        // failure, and a retry would duplicate it.
        return try await send("POST", "pages", body: body, retryable: false)
    }

    public func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try await send("PATCH", "pages/\(id)", body: ["properties": .object(properties.mapValues(\.json))], retryable: true)
    }

    public func trashPage(id: String) async throws {
        let _: NotionPage = try await send("PATCH", "pages/\(id)", body: ["in_trash": true], retryable: true)
    }

    public func createDatabase(
        parentPageID: String,
        title: String,
        iconEmoji: String?,
        properties: [String: NotionNewProperty]
    ) async throws -> NotionDatabase {
        var body: [String: NotionJSON] = [
            "parent": ["type": "page_id", "page_id": .string(parentPageID)],
            "title": .richText(title),
            "initial_data_source": ["properties": .object(properties.mapValues(\.json))],
        ]
        if let iconEmoji { body["icon"] = ["type": "emoji", "emoji": .string(iconEmoji)] }
        return try await send("POST", "databases", body: .object(body), retryable: false)
    }

    // MARK: Request construction

    static func searchBody(object: String, cursor: String?) -> NotionJSON {
        var body: [String: NotionJSON] = [
            "filter": ["property": "object", "value": .string(object)],
            "sort": ["timestamp": "last_edited_time", "direction": "descending"],
            "page_size": 100,
        ]
        if let cursor { body["start_cursor"] = .string(cursor) }
        return .object(body)
    }

    static func queryBody(cursor: String?, createdOnOrAfter: Date?) -> NotionJSON {
        var body: [String: NotionJSON] = [
            "sorts": [["timestamp": "created_time", "direction": "ascending"]],
            "page_size": 100,
            "result_type": "page",
        ]
        if let cursor { body["start_cursor"] = .string(cursor) }
        if let createdOnOrAfter {
            body["filter"] = [
                "timestamp": "created_time",
                "created_time": ["on_or_after": .string(NotionTimestamp.string(createdOnOrAfter))],
            ]
        }
        return .object(body)
    }

    func makeRequest(_ method: String, _ path: String, body: NotionJSON?) throws -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    // MARK: Sending

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: NotionJSON? = nil,
        retryable: Bool
    ) async throws -> Response {
        let data = try await sendRaw(method, path, body: body, retryable: retryable)
        do {
            return try NotionTimestamp.decoder().decode(Response.self, from: data)
        } catch {
            throw NotionError.unreadableResponse
        }
    }

    private func sendRaw(_ method: String, _ path: String, body: NotionJSON?, retryable: Bool) async throws -> Data {
        let request = try makeRequest(method, path, body: body)
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport.data(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if retryable, attempt < Self.maxAttempts {
                    try await sleep(Self.backoff(attempt: attempt))
                    continue
                }
                throw NotionError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw NotionError.unreadableResponse }
            if (200..<300).contains(http.statusCode) { return data }

            let status = http.statusCode
            let message = (try? JSONDecoder().decode(NotionErrorBody.self, from: data))?.message
            switch status {
            case 429:
                // Nothing was processed, so even a create is safe to repeat.
                guard attempt < Self.maxAttempts else { throw NotionError.rateLimited }
                try await sleep(Self.retryAfter(http) ?? Self.backoff(attempt: attempt))
                continue
            case 409, 500, 502, 503, 504, 529:
                if retryable, attempt < Self.maxAttempts {
                    try await sleep(Self.backoff(attempt: attempt))
                    continue
                }
                throw status == 409 ? NotionError.conflict : NotionError.unavailable(status: status)
            case 401:
                throw NotionError.invalidToken
            case 403, 404:
                throw NotionError.notShared
            case 500...:
                throw NotionError.unavailable(status: status)
            default:
                throw NotionError.rejected(message ?? "HTTP \(status)")
            }
        }
    }

    /// Notion sends whole seconds. Clamped so a bad header cannot stall a
    /// sync for long.
    static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(value.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return .seconds(min(max(seconds, 0.5), 60))
    }

    /// 1 s, 2 s, 4 s.
    static func backoff(attempt: Int) -> Duration {
        .seconds(1 << min(max(attempt - 1, 0), 5))
    }

    private func paginate<Element: Decodable>(
        maxPages: Int,
        _ fetch: (String?) async throws -> NotionList<Element>
    ) async throws -> [Element] {
        var results: [Element] = []
        var cursor: String?
        var pages = 0
        repeat {
            let list = try await fetch(cursor)
            results += list.results
            pages += 1
            cursor = list.hasMore ? list.nextCursor : nil
        } while cursor != nil && pages < maxPages
        return results
    }
}
