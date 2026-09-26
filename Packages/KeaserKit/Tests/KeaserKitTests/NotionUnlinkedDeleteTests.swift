import Foundation
import Testing
@testable import KeaserKit

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
    @Test func deletingAnUnlinkedExpenseInANotionAccountRemembersItsID() {
        let store = KeaserStore(file: nil)
        let connection = NotionConnection(databaseID: "db", databaseTitle: "Expenses", properties: NotionPropertyMap(title: "Name"))
        let account = store.createAccount(name: "Notion", notion: connection)
        let expense = Expense(title: "Lunch", amount: 12)
        store.saveExpense(expense, in: account.id)
        store.deleteExpense(expense.id, in: account.id)
        #expect(store.account(id: account.id)?.deletedUnlinkedExpenseIDs == [expense.id])
        #expect(store.account(id: account.id)?.deletedNotionPageIDs.isEmpty == true)
    }

    @MainActor
    @Test func localAccountsKeepNoTombstones() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let expense = Expense(title: "Lunch", amount: 12)
        store.saveExpense(expense, in: account.id)
        store.deleteExpense(expense.id, in: account.id)
        #expect(store.account(id: account.id)?.deletedUnlinkedExpenseIDs.isEmpty == true)
    }
}
