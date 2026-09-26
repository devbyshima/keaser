import Foundation
import Testing
@testable import KeaserKit

/// Returns the query results without the given pages, like a query that has
/// not caught up with a fresh write yet. Everything else goes to the demo
/// workspace, so a page hidden here can still be read by its ID.
final class LaggingQueryAPI: NotionAPI {
    let base: NotionDemoService
    let hidden: Set<String>

    init(base: NotionDemoService, hiding hidden: Set<String>) {
        self.base = base
        self.hidden = Set(hidden.map(NotionID.normalize))
    }

    func currentUser() async throws -> NotionUser { try await base.currentUser() }
    func searchDataSources() async throws -> [NotionDataSource] { try await base.searchDataSources() }
    func searchPages() async throws -> [NotionPage] { try await base.searchPages() }
    func retrieveDatabase(id: String) async throws -> NotionDatabase { try await base.retrieveDatabase(id: id) }
    func retrieveDataSource(id: String) async throws -> NotionDataSource { try await base.retrieveDataSource(id: id) }
    func updateDataSource(id: String, properties: [String: NotionNewProperty]) async throws -> NotionDataSource {
        try await base.updateDataSource(id: id, properties: properties)
    }
    func queryPages(dataSourceID: String) async throws -> [NotionPage] {
        try await base.queryPages(dataSourceID: dataSourceID).filter { !hidden.contains(NotionID.normalize($0.id)) }
    }
    func retrievePage(id: String) async throws -> NotionPage { try await base.retrievePage(id: id) }
    func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try await base.updatePage(id: id, properties: properties)
    }
    func trashPage(id: String) async throws { try await base.trashPage(id: id) }
    func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        try await base.createPage(dataSourceID: dataSourceID, properties: properties)
    }
    func createDatabase(parentPageID: String, title: String, iconEmoji: String?, properties: [String: NotionNewProperty]) async throws -> NotionDatabase {
        try await base.createDatabase(parentPageID: parentPageID, title: title, iconEmoji: iconEmoji, properties: properties)
    }
}

/// A create reaches Notion but its response is lost, and the expense is then
/// deleted in Keaser before the next sync. The orphan page must be trashed,
/// not pulled back in as a new expense.
struct NotionUnlinkedDeleteTests {
    private let lastSync = Date(timeIntervalSince1970: 1_789_000_000)

    @Test func anOrphanPageOfADeletedExpenseIsTrashedNotInserted() {
        let deletedID = UUID()
        let orphan = NotionTestData.page(id: "p1", ["Name": .title("Lunch")], edited: lastSync.addingTimeInterval(60))
        let other = NotionTestData.page(id: "p2", ["Name": .title("Dinner")], edited: lastSync.addingTimeInterval(60))
        let plan = SyncPlanner.plan(
            local: [],
            remote: [orphan, other],
            tombstones: [],
            lastSyncedAt: lastSync,
            isSameContent: { $0.title == $1.title },
            keaserID: { $0.id == "p1" ? deletedID : nil },
            deletedExpenseIDs: [deletedID]
        )
        #expect(plan.operations == [.archiveRemote(pageID: "p1"), .insertLocal(pageID: "p2")])
    }

    @MainActor
    @Test func deletingAnUnlinkedExpenseInANotionAccountRemembersItsIDAndTime() {
        let store = KeaserStore(file: nil)
        let connection = NotionConnection(databaseID: "db", databaseTitle: "Expenses", properties: NotionPropertyMap(title: "Name"))
        let account = store.createAccount(name: "Notion", notion: connection)
        let expense = Expense(title: "Lunch", amount: 12)
        store.saveExpense(expense, in: account.id)
        store.deleteExpense(expense.id, in: account.id, now: lastSync)
        #expect(store.account(id: account.id)?.unlinkedDeletions == [UnlinkedDeletion(expenseID: expense.id, deletedAt: lastSync)])
        #expect(store.account(id: account.id)?.deletedNotionPageIDs.isEmpty == true)
    }

    @MainActor
    @Test func localAccountsKeepNoTombstones() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let expense = Expense(title: "Lunch", amount: 12)
        store.saveExpense(expense, in: account.id)
        store.deleteExpense(expense.id, in: account.id)
        #expect(store.account(id: account.id)?.unlinkedDeletions.isEmpty == true)
    }

    @Test func olderFilesKeepTheirDeletedIDs() throws {
        let id = UUID()
        let json = #"{"id":"\#(UUID().uuidString)","name":"Notion","deletedUnlinkedExpenseIDs":["\#(id.uuidString)"]}"#
        let before = Date.now
        let account = try DatabaseFile.makeDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.unlinkedDeletions.map(\.expenseID) == [id])
        // The time was not kept: counted from now, so it waits a full window.
        #expect(account.unlinkedDeletions.allSatisfy { $0.deletedAt >= before })
    }

    @Test func deletionTimesSurviveASave() throws {
        var account = Account(name: "Notion")
        account.unlinkedDeletions = [UnlinkedDeletion(expenseID: UUID(), deletedAt: lastSync.addingTimeInterval(0.25))]
        let data = try DatabaseFile.makeEncoder().encode(account)
        let decoded = try DatabaseFile.makeDecoder().decode(Account.self, from: data)
        #expect(decoded.unlinkedDeletions == account.unlinkedDeletions)
    }
}

/// End to end against the demo workspace: an orphan page the query does not
/// return yet is still trashed by a later sync.
@MainActor
struct NotionUnlinkedDeleteSyncTests {
    private let start = Date(timeIntervalSince1970: 1_789_000_000)
    private let calendar = NotionTestData.utc

    private func linkedAccount(to service: NotionDemoService, deletions: [UnlinkedDeletion] = []) async throws -> Account {
        let source = try #require(try await service.searchDataSources().first { $0.title == "Expenses" })
        return Account(
            name: "Expenses",
            notion: NotionConnection(
                databaseID: try #require(source.databaseID),
                databaseTitle: source.title,
                properties: try #require(NotionPropertyMatcher.autoMap(source)),
                dataSourceID: source.id
            ),
            unlinkedDeletions: deletions
        )
    }

    @Test func aDeletedExpenseWhoseOrphanPageTheQueryMissedStaysDeleted() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        func sync(_ api: any NotionAPI, at time: Date) async -> NotionSyncOutcome {
            await service.setNow(time)
            let outcome = await NotionSync.run(account: account, api: api, calendar: calendar, startedAt: time)
            outcome.apply(to: &account)
            return outcome
        }
        #expect(await sync(service, at: start).succeeded)

        // 1. Taxi's create reaches Notion, its response is lost.
        let later = start.addingTimeInterval(600)
        let taxi = Expense(title: "Taxi", amount: 18, date: later, createdAt: later, updatedAt: later)
        account.expenses.append(taxi)
        #expect(!(await sync(FlakyNotionAPI(base: service, losingCreates: 1), at: later.addingTimeInterval(60))).succeeded)
        let orphan = try #require(await service.liveRows(dataSourceID: sourceID).first { $0.title == "Taxi" })

        // 2. Taxi is deleted in Keaser, exactly as the store does it.
        let deletedAt = later.addingTimeInterval(90)
        let store = KeaserStore(database: Database(accounts: [account]), file: nil)
        store.deleteExpense(taxi.id, in: account.id, now: deletedAt)
        account = try #require(store.account(id: account.id))

        // 3. The next sync's query has not caught up with the orphan yet. It
        // succeeds, but cannot settle the deletion.
        #expect(await sync(LaggingQueryAPI(base: service, hiding: [orphan.id]), at: later.addingTimeInterval(120)).succeeded)
        #expect(account.unlinkedDeletions.map(\.expenseID) == [taxi.id])

        // 4. A later sync sees the orphan and trashes it.
        #expect(await sync(service, at: later.addingTimeInterval(600)).succeeded)
        #expect(!account.expenses.contains { $0.title == "Taxi" }, "the deleted expense came back from Notion")
        #expect(await !service.liveRows(dataSourceID: sourceID).contains { $0.title == "Taxi" })

        // 5. A sync begun a full window after the deletion settles it.
        #expect(await sync(service, at: deletedAt.addingTimeInterval(NotionSync.orphanSettleTime)).succeeded)
        #expect(account.unlinkedDeletions.isEmpty)
        #expect(!account.expenses.contains { $0.title == "Taxi" })
    }

    @Test func onlyASuccessfulSyncBegunAFullWindowLaterSettlesADeletion() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        let deletion = UnlinkedDeletion(expenseID: UUID(), deletedAt: start)
        var account = try await linkedAccount(to: service, deletions: [deletion])
        func sync(at time: Date, failing: Bool = false) async {
            await service.setNow(time)
            var outcome = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: time)
            if failing { outcome.error = .network("The network connection was lost.") }
            outcome.apply(to: &account)
        }

        await sync(at: start.addingTimeInterval(NotionSync.orphanSettleTime - 1))
        #expect(account.unlinkedDeletions == [deletion])
        await sync(at: start.addingTimeInterval(NotionSync.orphanSettleTime), failing: true)
        #expect(account.unlinkedDeletions == [deletion])
        await sync(at: start.addingTimeInterval(NotionSync.orphanSettleTime))
        #expect(account.unlinkedDeletions.isEmpty)
    }
}
