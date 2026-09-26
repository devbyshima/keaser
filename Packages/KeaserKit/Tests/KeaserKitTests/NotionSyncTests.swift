import Foundation
import Testing
@testable import KeaserKit

/// Whole syncs against the in-memory workspace: pull, plan, push, apply.
struct NotionSyncTests {
    private let start = Date(timeIntervalSince1970: 1_789_000_000)
    private let calendar = NotionTestData.utc

    private func linkedAccount(to service: NotionDemoService) async throws -> Account {
        let sources = try await service.searchDataSources()
        let source = try #require(sources.first { $0.title == "Expenses" })
        let map = try #require(NotionPropertyMatcher.autoMap(source))
        return Account(name: "Expenses", notion: NotionConnection(
            databaseID: try #require(source.databaseID),
            databaseTitle: source.title,
            properties: map,
            dataSourceID: source.id
        ))
    }

    private func sync(_ account: inout Account, _ service: NotionDemoService, at time: Date) async -> NotionSyncOutcome {
        let outcome = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: time)
        outcome.apply(to: &account)
        return outcome
    }

    @Test func firstSyncPullsEveryRowAndSkipsBlankOnes() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let outcome = await sync(&account, service, at: start)
        #expect(outcome.succeeded)
        #expect(account.expenses.map(\.title).sorted() == ["Coffee", "Dinner with friends", "Groceries", "Netflix", "Train ticket"])
        #expect(account.expenses.allSatisfy { $0.notionPageID != nil })
        let coffee = try #require(account.expenses.first { $0.title == "Coffee" })
        #expect(coffee.amount == Decimal(string: "4.50"))
        #expect(account.category(id: coffee.categoryID)?.name == "Food & Drinks")
        #expect(account.paymentMethod(id: coffee.paymentMethodID)?.name == "Credit Card")
        #expect(account.notion?.lastSyncedAt == start)
        #expect(account.notion?.properties.amountID == "amt1")

        // A second sync with nothing changed does nothing.
        let again = await sync(&account, service, at: start.addingTimeInterval(120))
        #expect(again.plan.operations.isEmpty)
    }

    @Test func pushesNewAndEditedExpensesAndTrashesDeletedOnes() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        _ = await sync(&account, service, at: start)
        let sourceID = try #require(account.notion?.dataSourceID)

        // Keaser: add one, edit one, delete one.
        let later = start.addingTimeInterval(600)
        let tea = Expense(title: "Tea", amount: Decimal(string: "3.10")!, categoryID: account.categories[0].id, date: later, createdAt: later, updatedAt: later)
        account.expenses.append(tea)
        let netflix = try #require(account.expenses.firstIndex { $0.title == "Netflix" })
        account.expenses[netflix].amount = Decimal(string: "17.99")!
        account.expenses[netflix].updatedAt = later
        let train = try #require(account.expenses.firstIndex { $0.title == "Train ticket" })
        let trainPage = try #require(account.expenses[train].notionPageID)
        account.expenses.remove(at: train)
        account.deletedNotionPageIDs.append(trainPage)

        await service.setNow(later.addingTimeInterval(60))
        let outcome = await sync(&account, service, at: later.addingTimeInterval(60))
        #expect(outcome.succeeded)
        #expect(account.deletedNotionPageIDs.isEmpty)
        #expect(account.expenses.first { $0.id == tea.id }?.notionPageID != nil)

        let rows = await service.liveRows(dataSourceID: sourceID)
        #expect(rows.contains { $0.title == "Tea" && $0.properties["Amount"]?.number == Decimal(string: "3.10") })
        #expect(rows.first { $0.title == "Netflix" }?.properties["Amount"]?.number == Decimal(string: "17.99"))
        #expect(!rows.contains { $0.title == "Train ticket" })
    }

    @Test func pullsRemoteEditsAndDeletes() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        _ = await sync(&account, service, at: start)

        let coffee = try #require(account.expenses.first { $0.title == "Coffee" })
        let groceries = try #require(account.expenses.first { $0.title == "Groceries" })
        let edit = start.addingTimeInterval(300)
        try await service.editRow(id: coffee.notionPageID!, at: edit, properties: ["Name": .title("Flat white"), "Category": .select("Cafés")])
        try await service.editRow(id: groceries.notionPageID!, at: edit, trash: true)

        let outcome = await sync(&account, service, at: edit.addingTimeInterval(120))
        #expect(outcome.succeeded)
        let pulled = try #require(account.expenses.first { $0.id == coffee.id })
        #expect(pulled.title == "Flat white")
        #expect(account.category(id: pulled.categoryID)?.name == "Cafés")
        #expect(account.category(id: pulled.categoryID)?.symbol == "cup.and.saucer.fill")
        #expect(!account.expenses.contains { $0.id == groceries.id })
        #expect(account.deletedNotionPageIDs.isEmpty)
    }

    @Test func failuresKeepLocalDataAndDoNotAdvanceTheSyncTime() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        _ = await sync(&account, service, at: start)
        let before = account.expenses

        account.expenses.append(Expense(title: "Offline", amount: 1, updatedAt: start.addingTimeInterval(60)))
        await service.fail(with: .network("offline"))
        let outcome = await sync(&account, service, at: start.addingTimeInterval(120))
        #expect(outcome.error == .network("offline"))
        #expect(account.expenses.count == before.count + 1)
        #expect(account.notion?.lastSyncedAt == start)
    }

    @Test func editsMadeDuringASyncWin() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        _ = await sync(&account, service, at: start)
        let coffee = try #require(account.expenses.first { $0.title == "Coffee" })
        try await service.editRow(id: coffee.notionPageID!, at: start.addingTimeInterval(300), properties: ["Name": .title("Remote")])

        let outcome = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: start.addingTimeInterval(400))
        // The user edits the same expense while the sync is in flight.
        let index = try #require(account.expenses.firstIndex { $0.id == coffee.id })
        account.expenses[index].title = "Typed while syncing"
        account.expenses[index].updatedAt = start.addingTimeInterval(410)
        outcome.apply(to: &account)
        #expect(account.expenses[index].title == "Typed while syncing")
    }

    @Test func aPageCreatedForAnExpenseDeletedMeanwhileIsTrashedNextTime() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        _ = await sync(&account, service, at: start)
        let new = Expense(title: "Short-lived", amount: 2, updatedAt: start.addingTimeInterval(60))
        account.expenses.append(new)
        let outcome = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: start.addingTimeInterval(120))
        account.expenses.removeAll { $0.id == new.id }
        outcome.apply(to: &account)
        let created = try #require(outcome.createdPages[new.id])
        #expect(account.deletedNotionPageIDs == [created])
    }

    @Test func missingDataSourceIDIsResolvedFromTheDatabase() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let expected = account.notion?.dataSourceID
        account.notion?.dataSourceID = nil
        let outcome = await sync(&account, service, at: start)
        #expect(outcome.succeeded)
        #expect(account.notion?.dataSourceID == expected)
    }

    @Test func disconnectedMeanwhileAppliesNothing() async throws {
        let service = NotionDemoService(now: start, calendar: calendar)
        var account = try await linkedAccount(to: service)
        let outcome = await NotionSync.run(account: account, api: service, calendar: calendar, startedAt: start)
        account.notion = nil
        outcome.apply(to: &account)
        #expect(account.expenses.isEmpty)
    }
}
