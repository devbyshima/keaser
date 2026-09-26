import Foundation

/// What one sync of one account did, ready to be written back into the
/// store. Produced even when the sync failed part way, so pages created
/// before the failure are still linked to their expenses (otherwise the next
/// sync would create them twice).
public struct NotionSyncOutcome: Sendable {
    /// The account as it was when the sync began.
    public var snapshot: Account
    /// The connection with the data source ID, title and property names
    /// refreshed from Notion.
    public var connection: NotionConnection?
    public var plan = NotionSyncPlan()
    /// Remote rows the plan refers to, by normalized page ID.
    public var pages: [String: NotionPage] = [:]
    /// Pages created for local expenses.
    public var createdPages: [UUID: String] = [:]
    /// Tombstones that are done (trashed now, or already gone).
    public var clearedTombstones: [String] = []
    public var mapper: ExpenseMapper?
    public var startedAt: Date
    public var error: NotionError?

    public var succeeded: Bool { error == nil }

    /// Writes the result into `account`, which may have changed while the
    /// sync ran. An expense edited or deleted in the meantime keeps the
    /// user's version; the next sync takes it from there.
    public func apply(to account: inout Account) {
        guard var current = account.notion,
              NotionID.same(current.databaseID, snapshot.notion?.databaseID)
        else { return } // Disconnected or relinked meanwhile.

        if let connection {
            current.dataSourceID = connection.dataSourceID
            current.databaseTitle = connection.databaseTitle
            current.iconEmoji = connection.iconEmoji ?? current.iconEmoji
            current.url = connection.url ?? current.url
            if current.properties.titleID == nil || current.properties == snapshot.notion?.properties {
                current.properties = connection.properties
            }
        }
        if succeeded { current.lastSyncedAt = startedAt }
        account.notion = current

        let unchanged: (Expense) -> Bool = { expense in
            snapshot.expenses.first { $0.id == expense.id }?.updatedAt == expense.updatedAt
        }

        var links = createdPages
        for case .linkLocal(let expenseID, let pageID) in plan.operations {
            links[expenseID] = pageID
        }
        for (expenseID, pageID) in links {
            if let index = account.expenses.firstIndex(where: { $0.id == expenseID }) {
                account.expenses[index].notionPageID = pageID
            } else {
                // Deleted while its page was being created or linked: trash
                // it next time.
                account.deletedNotionPageIDs.append(pageID)
            }
        }

        let cleared = Set(clearedTombstones.map(NotionID.normalize))
        account.deletedNotionPageIDs.removeAll { cleared.contains(NotionID.normalize($0)) }

        guard let mapper else { return }
        for operation in plan.operations {
            switch operation {
            case .updateLocal(let expenseID, let pageID):
                guard let page = pages[NotionID.normalize(pageID)],
                      let index = account.expenses.firstIndex(where: { $0.id == expenseID }),
                      unchanged(account.expenses[index])
                else { continue }
                var expense = account.expenses[index]
                if mapper.apply(mapper.remoteExpense(from: page), to: &expense, in: &account) {
                    expense.updatedAt = min(page.lastEditedTime, startedAt)
                    account.expenses[index] = expense
                }
            case .insertLocal(let pageID):
                guard let page = pages[NotionID.normalize(pageID)],
                      !account.expenses.contains(where: { NotionID.same($0.notionPageID, pageID) }),
                      !account.deletedNotionPageIDs.contains(where: { NotionID.same($0, pageID) })
                else { continue }
                var expense = mapper.makeExpense(from: page, in: &account)
                expense.updatedAt = min(page.lastEditedTime, startedAt)
                account.expenses.append(expense)
            case .deleteLocal(let expenseID, _):
                guard let index = account.expenses.firstIndex(where: { $0.id == expenseID }),
                      unchanged(account.expenses[index])
                else { continue }
                account.expenses.remove(at: index)
            case .createRemote, .updateRemote, .archiveRemote, .linkLocal:
                continue
            }
        }
    }
}

/// Runs one full sync of one account against Notion: pull, plan, push.
/// Nothing here touches the store; the caller applies the outcome.
public enum NotionSync {
    public static func run(
        account: Account,
        api: any NotionAPI,
        calendar: Calendar,
        startedAt: Date = .now
    ) async -> NotionSyncOutcome {
        var outcome = NotionSyncOutcome(snapshot: account, connection: account.notion, startedAt: startedAt)
        do {
            try await pullAndPush(account: account, api: api, calendar: calendar, outcome: &outcome)
        } catch let error as NotionError {
            outcome.error = error
        } catch is CancellationError {
            outcome.error = .network("Cancelled")
        } catch {
            outcome.error = .network(error.localizedDescription)
        }
        return outcome
    }

    private static func pullAndPush(
        account: Account,
        api: any NotionAPI,
        calendar: Calendar,
        outcome: inout NotionSyncOutcome
    ) async throws {
        guard var connection = account.notion else { throw NotionError.noDataSource }

        // 1. The data source and its current schema.
        let dataSourceID: String
        if let known = connection.dataSourceID {
            dataSourceID = known
        } else {
            let database = try await api.retrieveDatabase(id: connection.databaseID)
            guard let first = database.dataSources.first else { throw NotionError.noDataSource }
            dataSourceID = first.id
        }
        let dataSource = try await api.retrieveDataSource(id: dataSourceID)
        guard !dataSource.inTrash else { throw NotionError.notShared }
        guard var resolved = connection.properties.resolved(in: dataSource) else { throw NotionError.noTitleProperty }
        if resolved.keaserID == nil {
            resolved.keaserID = try await addKeaserIDProperty(to: dataSource, api: api)
        }
        connection.dataSourceID = dataSourceID
        connection.databaseTitle = dataSource.displayTitle
        connection.iconEmoji = dataSource.iconEmoji
        connection.url = dataSource.url ?? connection.url
        connection.properties = resolved.map
        outcome.connection = connection

        // 2. Every live row, plus a direct look at any linked page the query
        // did not return. Queries can lag a fresh write, and a page only
        // counts as gone when Notion says so.
        var pages = try await api.queryPages(dataSourceID: dataSourceID)
        let returned = Set(pages.map { NotionID.normalize($0.id) })
        let wanted = account.expenses.compactMap(\.notionPageID) + account.deletedNotionPageIDs
        var checked: Set<String> = []
        for pageID in wanted {
            let key = NotionID.normalize(pageID)
            guard !returned.contains(key), checked.insert(key).inserted else { continue }
            do {
                var page = try await api.retrievePage(id: pageID)
                // Moved to another database counts as gone from this one.
                if !NotionID.same(page.parent.dataSourceID, dataSourceID) { page.inTrash = true }
                pages.append(page)
            } catch NotionError.notShared {
                continue // Deleted for good, or no longer visible: gone.
            }
        }
        for page in pages { outcome.pages[NotionID.normalize(page.id)] = page }

        // 3. Plan.
        let mapper = ExpenseMapper(map: resolved, calendar: calendar)
        var planned = account
        planned.notion = connection
        let plan = SyncPlanner.plan(account: planned, remote: pages, mapper: mapper)
        outcome.mapper = mapper
        outcome.plan = plan
        outcome.clearedTombstones = plan.settledTombstones

        // 4. Push. Local operations are applied by the caller.
        for operation in plan.operations {
            try Task.checkCancellation()
            switch operation {
            case .archiveRemote(let pageID):
                do {
                    try await api.trashPage(id: pageID)
                } catch NotionError.notShared {
                    // Already gone.
                }
                outcome.clearedTombstones.append(pageID)
            case .createRemote(let expenseID):
                guard let expense = account.expenses.first(where: { $0.id == expenseID }) else { continue }
                let page = try await api.createPage(dataSourceID: dataSourceID, properties: mapper.properties(for: expense, in: account))
                outcome.createdPages[expenseID] = page.id
            case .updateRemote(let expenseID, let pageID):
                guard let expense = account.expenses.first(where: { $0.id == expenseID }) else { continue }
                do {
                    _ = try await api.updatePage(id: pageID, properties: mapper.properties(for: expense, in: account))
                } catch NotionError.notShared {
                    // Deleted in Notion since the query; the next sync sees it gone.
                }
            case .updateLocal, .insertLocal, .deleteLocal, .linkLocal:
                continue
            }
        }
    }

    /// Adds the Keaser ID property, so every page Keaser creates can be
    /// matched to its expense even when the create's response is lost. Nil
    /// when that is not possible, and the sync goes on without it: the name
    /// is taken by a property of another type (converting it would change
    /// the person's data), or the connection may not edit the schema.
    static func addKeaserIDProperty(to dataSource: NotionDataSource, api: any NotionAPI) async throws -> NotionPropertySchema? {
        let name = NotionKeaserSchema.keaserID
        guard dataSource.property(named: name) == nil else { return nil }
        do {
            var updated = try await api.updateDataSource(id: dataSource.id, properties: [name: .richText])
            if updated.property(named: name) == nil {
                // A partial response: read the schema back.
                updated = try await api.retrieveDataSource(id: dataSource.id)
            }
            guard let property = updated.property(named: name), property.type == .richText else { return nil }
            return property
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}
