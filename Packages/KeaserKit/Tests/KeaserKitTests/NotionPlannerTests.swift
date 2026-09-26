import Foundation
import Testing
@testable import KeaserKit

struct NotionPlannerTests {
    private let lastSync = Date(timeIntervalSince1970: 1_789_000_000)

    private func at(_ minutes: Double) -> Date { lastSync.addingTimeInterval(minutes * 60) }

    private func expense(_ title: String, page: String? = nil, updated: Date) -> Expense {
        Expense(title: title, amount: 10, date: lastSync, createdAt: at(-600), updatedAt: updated, notionPageID: page)
    }

    private func page(_ id: String, _ title: String, edited: Date, removed: Bool = false) -> NotionPage {
        NotionTestData.page(id: id, ["Name": .title(title)], edited: edited, removed: removed)
    }

    /// Content compares titles only, to keep each case readable. `ids` are
    /// the Keaser IDs the pages carry, by page ID.
    private func plan(
        _ local: [Expense],
        _ remote: [NotionPage],
        tombstones: [String] = [],
        lastSyncedAt: Date? = nil,
        ids: [String: UUID] = [:]
    ) -> NotionSyncPlan {
        SyncPlanner.plan(
            local: local,
            remote: remote,
            tombstones: tombstones,
            lastSyncedAt: lastSyncedAt ?? lastSync,
            isSameContent: { $0.title == $1.title },
            isBlank: { $0.title.isEmpty },
            keaserID: { ids[$0.id] }
        )
    }

    @Test func newLocalExpenseIsCreatedRemotely() {
        let new = expense("Coffee", updated: at(5))
        #expect(plan([new], []).operations == [.createRemote(expenseID: new.id)])
    }

    @Test func newRemotePageIsInsertedLocallyButBlankRowsAreNot() {
        let result = plan([], [page("p1", "Lunch", edited: at(3)), page("p2", "", edited: at(3))])
        #expect(result.operations == [.insertLocal(pageID: "p1")])
    }

    @Test func identicalContentNeedsNothingWhateverTheTimestamps() {
        let local = expense("Same", page: "p1", updated: at(10))
        #expect(plan([local], [page("p1", "Same", edited: at(20))]).operations.isEmpty)
    }

    @Test func onlyRemoteEditedPullsAndOnlyLocalEditedPushes() {
        let stale = expense("Old", page: "p1", updated: at(-30))
        #expect(plan([stale], [page("p1", "Edited in Notion", edited: at(12))]).operations == [.updateLocal(expenseID: stale.id, pageID: "p1")])

        let fresh = expense("Edited in Keaser", page: "p2", updated: at(12))
        #expect(plan([fresh], [page("p2", "Old", edited: at(-30))]).operations == [.updateRemote(expenseID: fresh.id, pageID: "p2")])
    }

    @Test func bothEditedLastWriterWins() {
        let localLater = expense("Keaser later", page: "p1", updated: at(30))
        #expect(plan([localLater], [page("p1", "Notion earlier", edited: at(10))]).operations
            == [.updateRemote(expenseID: localLater.id, pageID: "p1")])

        let localEarlier = expense("Keaser earlier", page: "p2", updated: at(10))
        #expect(plan([localEarlier], [page("p2", "Notion later", edited: at(30))]).operations
            == [.updateLocal(expenseID: localEarlier.id, pageID: "p2")])
    }

    @Test func aRemoteEditInTheSameMinuteAsTheLastSyncIsStillPulled() {
        // Notion floors last_edited_time to the minute, so an edit made 20
        // seconds after the last sync can read as 40 seconds before it.
        let local = expense("Old", page: "p1", updated: at(-5))
        let remote = page("p1", "Edited", edited: at(-40.0 / 60))
        #expect(plan([local], [remote]).operations == [.updateLocal(expenseID: local.id, pageID: "p1")])
    }

    @Test func archivedOrDeletedRemotePageDeletesTheExpense() {
        let trashed = expense("Trashed", page: "p1", updated: at(-5))
        let missing = expense("Missing", page: "p2", updated: at(-5))
        let result = plan([trashed, missing], [page("p1", "Trashed", edited: at(3), removed: true)])
        #expect(result.operations == [
            .deleteLocal(expenseID: trashed.id, pageID: "p1"),
            .deleteLocal(expenseID: missing.id, pageID: "p2"),
        ])
    }

    @Test func aLocalEditOutlivesARemoteDelete() {
        let edited = expense("Edited after sync", page: "p1", updated: at(5))
        #expect(plan([edited], [page("p1", "Old", edited: at(3), removed: true)]).operations == [.createRemote(expenseID: edited.id)])
    }

    @Test func localDeleteWithTombstoneArchivesThePageAndNeverPullsItBack() {
        let result = plan([], [page("p1", "Deleted in Keaser", edited: at(8))], tombstones: ["p1"])
        #expect(result.operations == [.archiveRemote(pageID: "p1")])
        #expect(result.settledTombstones.isEmpty)
    }

    @Test func tombstonesForPagesAlreadyGoneSettleWithoutARequest() {
        let result = plan([], [page("p1", "Gone", edited: at(1), removed: true)], tombstones: ["p1", "p2", "p2"])
        #expect(result.operations.isEmpty)
        #expect(result.settledTombstones == ["p1", "p2"])
    }

    @Test func pageIDsCompareWithoutHyphens() {
        let local = expense("Same", page: "59833787-2cf9-4fdf-8782-e53db20768a5", updated: at(-1))
        let remote = page("598337872cf94fdf8782e53db20768a5", "Same", edited: at(-10))
        #expect(plan([local], [remote]).operations.isEmpty)
    }

    @Test func firstSyncTreatsEverythingAsChanged() {
        let local = expense("Local", updated: at(-100))
        let result = SyncPlanner.plan(
            local: [local], remote: [page("p1", "Remote", edited: at(-100))], tombstones: [], lastSyncedAt: nil,
            isSameContent: { $0.title == $1.title }
        )
        #expect(result.operations == [.createRemote(expenseID: local.id), .insertLocal(pageID: "p1")])
    }

    @Test func anUnlinkedExpenseLinksToThePageCarryingItsIDInsteadOfCreatingAnother() {
        let taxi = expense("Taxi", updated: at(5))
        let orphan = page("p1", "Taxi", edited: at(5))
        #expect(plan([taxi], [orphan], ids: ["p1": taxi.id]).operations == [.linkLocal(expenseID: taxi.id, pageID: "p1")])
        // Without the ID it would be both created and pulled in.
        #expect(plan([taxi], [orphan]).operations == [.createRemote(expenseID: taxi.id), .insertLocal(pageID: "p1")])
    }

    @Test func aLinkedOrphanIsThenComparedLikeAnyLinkedPage() {
        let editedSince = expense("Taxi home", updated: at(9))
        #expect(plan([editedSince], [page("p1", "Taxi", edited: at(5))], ids: ["p1": editedSince.id]).operations == [
            .linkLocal(expenseID: editedSince.id, pageID: "p1"),
            .updateRemote(expenseID: editedSince.id, pageID: "p1"),
        ])
        let editedInNotion = expense("Taxi", updated: at(5))
        #expect(plan([editedInNotion], [page("p1", "Taxi to airport", edited: at(8))], ids: ["p1": editedInNotion.id]).operations == [
            .linkLocal(expenseID: editedInNotion.id, pageID: "p1"),
            .updateLocal(expenseID: editedInNotion.id, pageID: "p1"),
        ])
    }

    @Test func anEditOutlivingARemoteDeleteRelinksToALiveCopyOfItsPage() {
        let edited = expense("Taxi", page: "p1", updated: at(5))
        let result = plan([edited], [page("p1", "Taxi", edited: at(1), removed: true), page("p2", "Taxi", edited: at(2))], ids: ["p1": edited.id, "p2": edited.id])
        #expect(result.operations == [.linkLocal(expenseID: edited.id, pageID: "p2")])
    }

    @Test func aCopyOfALinkedPageIsPulledInAsItsOwnExpense() {
        let linked = expense("Rent", page: "p1", updated: at(-5))
        let result = plan([linked], [page("p1", "Rent", edited: at(-9)), page("p2", "Rent", edited: at(3))], ids: ["p1": linked.id, "p2": linked.id])
        #expect(result.operations == [.insertLocal(pageID: "p2")])
    }

    @Test func aTombstonedPageIsNeverLinked() {
        let unlinked = expense("Taxi", updated: at(5))
        let result = plan([unlinked], [page("p1", "Taxi", edited: at(1))], tombstones: ["p1"], ids: ["p1": unlinked.id])
        #expect(result.operations == [.archiveRemote(pageID: "p1"), .createRemote(expenseID: unlinked.id)])
    }

    @Test func mapperBasedPlanComparesMappedFields() throws {
        let mapper = NotionTestData.standardMapper
        var account = Account(name: "Personal")
        let food = account.categories[0]
        let day = try #require(NotionTestData.utc.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let local = Expense(title: "Lunch", amount: 12, categoryID: food.id, date: day, updatedAt: at(-10), notionPageID: "p1")
        account.expenses = [local]
        account.notion = NotionConnection(databaseID: "db-1", databaseTitle: "Expenses", properties: mapper.map.map, lastSyncedAt: lastSync)
        let same = NotionTestData.page(id: "p1", mapper.properties(for: local, in: account), edited: at(5))
        #expect(SyncPlanner.plan(account: account, remote: [same], mapper: mapper).operations.isEmpty)

        var changed = mapper.properties(for: local, in: account)
        changed["Amount"] = .number(13)
        let edited = NotionTestData.page(id: "p1", changed, edited: at(5))
        #expect(SyncPlanner.plan(account: account, remote: [edited], mapper: mapper).operations == [.updateLocal(expenseID: local.id, pageID: "p1")])
    }
}
