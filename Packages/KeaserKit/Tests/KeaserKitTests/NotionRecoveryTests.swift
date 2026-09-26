import Foundation
import Synchronization
import Testing
@testable import KeaserKit

/// Forwards to the demo workspace, with the failures a real connection
/// meets: creates that reach Notion but whose response is lost (connection
/// dropped, app suspended or killed mid-request, timeout), and a connection
/// that may not change the database's schema.
final class FlakyNotionAPI: NotionAPI {
    let base: NotionDemoService
    let refusesSchemaChanges: Bool
    private let createsToLose: Mutex<Int>
    private let schemaChanges = Mutex(0)

    init(base: NotionDemoService, losingCreates: Int = 0, refusesSchemaChanges: Bool = false) {
        self.base = base
        self.refusesSchemaChanges = refusesSchemaChanges
        createsToLose = Mutex(losingCreates)
    }

    var schemaChangeCount: Int { schemaChanges.withLock { $0 } }

    func currentUser() async throws -> NotionUser { try await base.currentUser() }
    func searchDataSources() async throws -> [NotionDataSource] { try await base.searchDataSources() }
    func searchPages() async throws -> [NotionPage] { try await base.searchPages() }
    func retrieveDatabase(id: String) async throws -> NotionDatabase { try await base.retrieveDatabase(id: id) }
    func retrieveDataSource(id: String) async throws -> NotionDataSource { try await base.retrieveDataSource(id: id) }
    func queryPages(dataSourceID: String) async throws -> [NotionPage] { try await base.queryPages(dataSourceID: dataSourceID) }
    func retrievePage(id: String) async throws -> NotionPage { try await base.retrievePage(id: id) }
    func updatePage(id: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage { try await base.updatePage(id: id, properties: properties) }
    func trashPage(id: String) async throws { try await base.trashPage(id: id) }

    func updateDataSource(id: String, properties: [String: NotionNewProperty]) async throws -> NotionDataSource {
        schemaChanges.withLock { $0 += 1 }
        if refusesSchemaChanges { throw NotionError.notShared }
        return try await base.updateDataSource(id: id, properties: properties)
    }

    func createPage(dataSourceID: String, properties: [String: NotionPropertyWrite]) async throws -> NotionPage {
        let page = try await base.createPage(dataSourceID: dataSourceID, properties: properties)
        let lose = createsToLose.withLock { left in
            defer { left = max(0, left - 1) }
            return left > 0
        }
        if lose { throw NotionError.network("The network connection was lost.") }
        return page
    }

    func createDatabase(parentPageID: String, title: String, iconEmoji: String?, properties: [String: NotionNewProperty]) async throws -> NotionDatabase {
        try await base.createDatabase(parentPageID: parentPageID, title: title, iconEmoji: iconEmoji, properties: properties)
    }
}

/// Syncs that fail part way must never leave a second page in Notion or a
/// second expense in Keaser.
struct NotionRecoveryTests {
    private let start = Date(timeIntervalSince1970: 1_789_000_000)
    private let calendar = NotionTestData.utc

    private func linkedAccount(to service: NotionDemoService) async throws -> Account {
        let source = try #require(try await service.searchDataSources().first { $0.title == "Expenses" })
        return Account(name: "Expenses", notion: NotionConnection(
            databaseID: try #require(source.databaseID),
            databaseTitle: source.title,
            properties: try #require(NotionPropertyMatcher.autoMap(source)),
            dataSourceID: source.id
        ))
    }

    private func sync(_ account: inout Account, _ api: any NotionAPI, at time: Date) async -> NotionSyncOutcome {
        let outcome = await NotionSync.run(account: account, api: api, calendar: calendar, startedAt: time)
        outcome.apply(to: &account)
        return outcome
    }

    private func expense(_ title: String, _ amount: Decimal, at time: Date) -> Expense {
        Expense(title: title, amount: amount, date: time, createdAt: time, updatedAt: time)
    }

    @Test func theFirstSyncAddsAKeaserIDPropertyAndEveryNewPageCarriesItsExpenseID() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        #expect(await sync(&account, service, at: start).succeeded)

        let schema = try await service.retrieveDataSource(id: sourceID)
        #expect(schema.property(named: "Keaser ID")?.type == .richText)
        #expect(account.notion?.properties.keaserID == "Keaser ID")
        #expect(account.notion?.properties.keaserIDPropertyID == schema.property(named: "Keaser ID")?.id)

        let later = start.addingTimeInterval(600)
        let tea = expense("Tea", 3, at: later)
        account.expenses.append(tea)
        await service.setNow(later.addingTimeInterval(60))
        #expect(await sync(&account, service, at: later.addingTimeInterval(60)).succeeded)
        let row = try #require(await service.liveRows(dataSourceID: sourceID).first { $0.title == "Tea" })
        #expect(row.properties["Keaser ID"]?.text == tea.id.uuidString)

        // Adding the property is not a change to sync back.
        let again = await sync(&account, service, at: later.addingTimeInterval(180))
        #expect(again.plan.operations.isEmpty)
    }

    @Test func aCreateWhoseResponseIsLostIsLinkedNotDuplicated() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        _ = await sync(&account, service, at: start)
        let before = account.expenses.count

        let later = start.addingTimeInterval(600)
        let taxi = expense("Taxi", 18, at: later)
        account.expenses.append(taxi)
        await service.setNow(later.addingTimeInterval(60))
        let api = FlakyNotionAPI(base: service, losingCreates: 1)
        let failed = await sync(&account, api, at: later.addingTimeInterval(60))
        #expect(!failed.succeeded)
        #expect(account.expenses.first { $0.id == taxi.id }?.notionPageID == nil)

        await service.setNow(later.addingTimeInterval(300))
        let retry = await sync(&account, api, at: later.addingTimeInterval(300))
        #expect(retry.succeeded)
        #expect(!retry.plan.operations.contains(.createRemote(expenseID: taxi.id)))

        let rows = await service.liveRows(dataSourceID: sourceID).filter { $0.title == "Taxi" }
        #expect(rows.count == 1)
        #expect(account.expenses.filter { $0.title == "Taxi" }.count == 1)
        #expect(account.expenses.count == before + 1)
        #expect(NotionID.same(account.expenses.first { $0.id == taxi.id }?.notionPageID, rows.first?.id))
    }

    @Test func aSyncWhoseOutcomeIsNeverAppliedIsRecoveredByTheNextOne() async throws {
        // The app is killed mid-sync: pages were created, nothing was saved.
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        _ = await sync(&account, service, at: start)

        let later = start.addingTimeInterval(600)
        account.expenses += [expense("Taxi", 18, at: later), expense("Lunch", 12, at: later)]
        await service.setNow(later.addingTimeInterval(60))
        _ = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: later.addingTimeInterval(60))

        // Meanwhile Lunch was corrected in Keaser.
        let lunch = try #require(account.expenses.firstIndex { $0.title == "Lunch" })
        account.expenses[lunch].amount = 14
        account.expenses[lunch].updatedAt = later.addingTimeInterval(240)

        await service.setNow(later.addingTimeInterval(300))
        let next = await sync(&account, service, at: later.addingTimeInterval(300))
        #expect(next.succeeded)
        let rows = await service.liveRows(dataSourceID: sourceID)
        #expect(rows.filter { $0.title == "Taxi" }.count == 1)
        #expect(rows.filter { $0.title == "Lunch" }.count == 1)
        #expect(rows.first { $0.title == "Lunch" }?.properties["Amount"]?.number == 14)
        #expect(account.expenses.filter { $0.title == "Taxi" || $0.title == "Lunch" }.count == 2)
        #expect(account.expenses.allSatisfy { $0.notionPageID != nil })
    }

    @Test func aConnectionThatCannotChangeTheSchemaStillSyncs() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        let api = FlakyNotionAPI(base: service, refusesSchemaChanges: true)
        #expect(await sync(&account, api, at: start).succeeded)
        #expect(account.notion?.properties.keaserID == nil)

        let later = start.addingTimeInterval(600)
        account.expenses.append(expense("Tea", 3, at: later))
        await service.setNow(later.addingTimeInterval(60))
        #expect(await sync(&account, api, at: later.addingTimeInterval(60)).succeeded)
        let rows = await service.liveRows(dataSourceID: sourceID)
        #expect(rows.filter { $0.title == "Tea" }.count == 1)
        #expect(try await service.retrieveDataSource(id: sourceID).property(named: "Keaser ID") == nil)
    }

    @Test func aKeaserIDColumnOfAnotherTypeIsNeverConverted() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let sourceID = try #require(account.notion?.dataSourceID)
        _ = try await service.updateDataSource(id: sourceID, properties: ["Keaser ID": .number(format: "number")])
        let api = FlakyNotionAPI(base: service)
        #expect(await sync(&account, api, at: start).succeeded)
        #expect(api.schemaChangeCount == 0)
        #expect(account.notion?.properties.keaserID == nil)
        #expect(try await service.retrieveDataSource(id: sourceID).property(named: "Keaser ID")?.type == .number)
    }

    @Test func aDatabaseKeaserCreatedNeedsNoSchemaChange() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        let parent = try #require(try await service.searchPages().first)
        let database = try await service.createDatabase(
            parentPageID: parent.id,
            title: "Keaser Expenses",
            iconEmoji: nil,
            properties: NotionKeaserSchema.properties(currencyCode: "USD", categories: ["Food"], paymentMethods: ["Cash"])
        )
        let source = try await service.retrieveDataSource(id: try #require(database.dataSources.first?.id))
        var account = Account(name: "Keaser Expenses", notion: NotionConnection(
            databaseID: database.id,
            databaseTitle: source.title,
            properties: try #require(NotionPropertyMatcher.autoMap(source)),
            dataSourceID: source.id
        ))
        let api = FlakyNotionAPI(base: service)
        #expect(await sync(&account, api, at: start).succeeded)
        #expect(api.schemaChangeCount == 0)
        #expect(account.notion?.properties.keaserID == "Keaser ID")
    }
}
