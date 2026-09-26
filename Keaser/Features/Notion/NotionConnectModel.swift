import KeaserKit
import Observation
import SwiftUI

/// State of the Connect to Notion flow: token, table choice, property map.
@MainActor
@Observable
final class NotionConnectModel {
    enum Step: Hashable {
        case databases
        /// Choose a page to hold a new Keaser database.
        case newDatabase
        case review
    }

    /// The title of the database Keaser creates.
    static let newDatabaseTitle = "Keaser Expenses"
    static let newDatabaseEmoji = "💸"

    var path: [Step] = []

    // Intro
    var token = ""
    private(set) var isValidating = false
    private(set) var tokenError: String?
    private(set) var user: NotionUser?

    // Databases
    private(set) var dataSources: [NotionDataSource] = []
    private(set) var isLoadingSources = false
    private(set) var sourcesError: String?
    private(set) var hasLoadedSources = false

    // New database
    private(set) var pages: [NotionPage] = []
    private(set) var isLoadingPages = false
    private(set) var pagesError: String?
    private(set) var creatingInPageID: String?

    // Review
    private(set) var selected: NotionDataSource?
    var map: NotionPropertyMap?
    var accountName = ""
    private(set) var isConnecting = false
    private(set) var connectError: String?
    /// Set when the account exists but its first sync failed.
    private(set) var connectedAccountID: UUID?

    private let engine: NotionSyncEngine

    init(engine: NotionSyncEngine = .shared) {
        self.engine = engine
    }

    var isBusy: Bool { isValidating || isConnecting || creatingInPageID != nil }

    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var client: any NotionAPI { engine.client(token: trimmedToken) }

    // MARK: Intro

    func validateToken() async {
        guard !trimmedToken.isEmpty, !isValidating else { return }
        isValidating = true
        tokenError = nil
        defer { isValidating = false }
        do {
            user = try await client.currentUser()
            // A different token may see a different workspace.
            dataSources = []
            pages = []
            hasLoadedSources = false
            path = [.databases]
        } catch {
            tokenError = Self.message(for: error)
        }
    }

    // MARK: Databases

    func loadDataSources() async {
        guard !isLoadingSources else { return }
        isLoadingSources = true
        sourcesError = nil
        defer { isLoadingSources = false }
        do {
            dataSources = try await client.searchDataSources()
            hasLoadedSources = true
        } catch is CancellationError {
            // The step went away mid-load; it loads again when it returns.
            return
        } catch {
            sourcesError = Self.message(for: error)
            hasLoadedSources = true
        }
    }

    func choose(_ source: NotionDataSource) {
        selected = source
        map = NotionPropertyMatcher.autoMap(source)
        accountName = source.displayTitle
        connectError = nil
        connectedAccountID = nil
        path.append(.review)
    }

    /// What the table's properties were matched to, for the row subtitle.
    func matchSummary(for source: NotionDataSource) -> String {
        guard let map = NotionPropertyMatcher.autoMap(source) else { return "No title property" }
        let found = [NotionExpenseField.amount, .category, .paymentMethod, .date].compactMap { map.name(for: $0) }
        return found.isEmpty ? "Only a title property" : found.joined(separator: " · ")
    }

    // MARK: New database

    func loadPages() async {
        guard !isLoadingPages else { return }
        isLoadingPages = true
        pagesError = nil
        defer { isLoadingPages = false }
        do {
            pages = try await client.searchPages()
        } catch is CancellationError {
            return
        } catch {
            pagesError = Self.message(for: error)
        }
    }

    func createDatabase(in page: NotionPage, currencyCode: String) async {
        guard creatingInPageID == nil else { return }
        creatingInPageID = page.id
        pagesError = nil
        defer { creatingInPageID = nil }
        do {
            let database = try await client.createDatabase(
                parentPageID: page.id,
                title: Self.newDatabaseTitle,
                iconEmoji: Self.newDatabaseEmoji,
                properties: NotionKeaserSchema.properties(
                    currencyCode: currencyCode,
                    categories: ExpenseCategory.defaults().map(\.name),
                    paymentMethods: PaymentMethod.defaults().map(\.name)
                )
            )
            guard let reference = database.dataSources.first else { throw NotionError.noDataSource }
            var source = try await client.retrieveDataSource(id: reference.id)
            if source.databaseID == nil { source.databaseID = database.id }
            dataSources.insert(source, at: 0)
            // Back from review should lead to the list (now showing the new
            // database), not to a page picker that would create another.
            path = [.databases]
            choose(source)
        } catch {
            pagesError = Self.message(for: error)
        }
    }

    // MARK: Review

    func candidates(for field: NotionExpenseField) -> [NotionPropertySchema] {
        guard let selected else { return [] }
        return NotionPropertyMatcher.candidates(for: field, in: selected)
    }

    func property(for field: NotionExpenseField) -> NotionPropertySchema? {
        guard let selected, let map else { return nil }
        let id = map.propertyID(for: field)
        return selected.properties.first { $0.id == id } ?? selected.property(named: map.name(for: field))
    }

    func setProperty(_ property: NotionPropertySchema?, for field: NotionExpenseField) {
        // A property holds one field: taking it from another field unmaps
        // that one.
        if let property {
            for other in NotionExpenseField.allCases where other != field && other != .title {
                if self.property(for: other)?.id == property.id { map?.set(other, to: nil) }
            }
        }
        map?.set(field, to: property)
    }

    var canConnect: Bool {
        selected != nil && map != nil && !isConnecting
            && !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Creates the account, stores the token and runs the first sync.
    /// Returns the new account's ID when the flow should close.
    func connect() async -> UUID? {
        if let connectedAccountID { return connectedAccountID }
        guard let selected, let map, canConnect else { return nil }
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        let connection = NotionConnection(
            databaseID: selected.databaseID ?? selected.id,
            databaseTitle: selected.displayTitle,
            workspaceName: user?.workspaceName,
            properties: map,
            dataSourceID: selected.id,
            iconEmoji: selected.iconEmoji,
            url: selected.url
        )
        do {
            let (accountID, syncError) = try await engine.connect(
                name: accountName,
                connection: connection,
                token: trimmedToken
            )
            guard let syncError else { return accountID }
            // Linked, but the first sync failed: say so once, then let the
            // person continue. Keaser retries on the next edit or launch.
            connectedAccountID = accountID
            connectError = "Connected, but the first sync failed. \(syncError.errorDescription ?? "")"
            return nil
        } catch {
            connectError = Self.message(for: error)
            return nil
        }
    }

    // MARK: Debug

    #if DEBUG
    /// `-KeaserNotionStep databases|newDatabase|review` opens that step with
    /// the demo workspace already loaded; `tokenError` shows the intro after
    /// a refused token; `created` creates a Keaser database in the first
    /// shared page and opens its review.
    func openDebugStep(_ step: String, currencyCode: String) async {
        if step == "tokenError" {
            token = "bad-demo-token"
            await validateToken()
            return
        }
        guard ["databases", "newDatabase", "review", "created"].contains(step) else { return }
        token = "demo-token"
        user = try? await client.currentUser()
        path = [.databases]
        await loadDataSources()
        switch step {
        case "newDatabase":
            path.append(.newDatabase)
            await loadPages()
        case "review":
            if let first = dataSources.first { choose(first) }
        case "created":
            await loadPages()
            if let page = pages.first { await createDatabase(in: page, currencyCode: currencyCode) }
        default:
            break
        }
    }
    #endif

    static func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
