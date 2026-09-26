import Foundation

/// One step of a sync.
public enum NotionSyncOperation: Hashable, Sendable {
    /// A local expense with no page yet: create its page.
    case createRemote(expenseID: UUID)
    /// A page already carries this unlinked expense's Keaser ID (an earlier
    /// create reached Notion but its response did not reach Keaser): link
    /// the two instead of creating another page.
    case linkLocal(expenseID: UUID, pageID: String)
    /// Local is newer: write the expense over the page.
    case updateRemote(expenseID: UUID, pageID: String)
    /// Notion is newer: write the page over the expense.
    case updateLocal(expenseID: UUID, pageID: String)
    /// A row only Notion has: add it as an expense.
    case insertLocal(pageID: String)
    /// The page was trashed, archived or deleted in Notion.
    case deleteLocal(expenseID: UUID, pageID: String)
    /// The expense was deleted in Keaser: trash its page.
    case archiveRemote(pageID: String)
}

public struct NotionSyncPlan: Hashable, Sendable {
    public var operations: [NotionSyncOperation]
    /// Tombstones whose page is already gone; they can be dropped without a
    /// request.
    public var settledTombstones: [String]

    public init(operations: [NotionSyncOperation] = [], settledTombstones: [String] = []) {
        self.operations = operations
        self.settledTombstones = settledTombstones
    }
}

/// Decides what a sync does, without doing it. Pure, so every case is
/// testable without Notion.
///
/// Rules:
/// - A page that says the same as its expense (mapped fields only) needs
///   nothing, whatever the timestamps say.
/// - Otherwise the side that changed since `lastSyncedAt` wins. When both
///   changed, the later of `Expense.updatedAt` and the page's
///   `last_edited_time` wins; a tie goes to Keaser.
/// - Notion stores `last_edited_time` to the minute (rounded down), so a
///   page counts as unchanged only when its minute ended before the last
///   sync began.
/// - A page gone from Notion deletes its expense, unless the expense was
///   edited since the last sync: then the edit wins and the page is created
///   again, so no local change is ever lost.
/// - A tombstone (expense deleted in Keaser) trashes its page and keeps the
///   page from being pulled back in.
/// - Before a page is created for an expense, a live page no expense links
///   to that carries the expense's Keaser ID is linked instead, and then
///   compared like any linked page. So a create whose response was lost
///   leaves neither a second page nor a second expense.
/// - A page carrying the Keaser ID of an expense deleted before it was
///   linked is trashed, not pulled back in.
public enum SyncPlanner {
    public static func plan(
        local: [Expense],
        remote: [NotionPage],
        tombstones: [String],
        lastSyncedAt: Date?,
        isSameContent: (Expense, NotionPage) -> Bool,
        isBlank: (NotionPage) -> Bool = { _ in false },
        keaserID: (NotionPage) -> UUID? = { _ in nil },
        deletedExpenseIDs: Set<UUID> = []
    ) -> NotionSyncPlan {
        var remoteByID: [String: NotionPage] = [:]
        for page in remote { remoteByID[NotionID.normalize(page.id)] = page }
        let tombstoneKeys = Set(tombstones.map(NotionID.normalize))
        var linked: Set<String> = []
        var plan = NotionSyncPlan()

        // Live pages no expense links to, by the Keaser ID they carry. The
        // oldest wins if a row was duplicated in Notion; the copy is pulled
        // in as a new expense.
        let claimed = Set(local.compactMap(\.notionPageID).map(NotionID.normalize))
        var unclaimed: [UUID: NotionPage] = [:]
        var discarded: Set<String> = []
        for page in remote where !page.isRemoved {
            let key = NotionID.normalize(page.id)
            guard !claimed.contains(key), !tombstoneKeys.contains(key),
                  let id = keaserID(page)
            else { continue }
            if deletedExpenseIDs.contains(id) {
                // Created for an expense deleted before the link came back.
                plan.operations.append(.archiveRemote(pageID: page.id))
                discarded.insert(key)
                continue
            }
            guard unclaimed[id] == nil else { continue }
            unclaimed[id] = page
        }

        var seenTombstones: Set<String> = []
        for tombstone in tombstones {
            let key = NotionID.normalize(tombstone)
            guard seenTombstones.insert(key).inserted else { continue }
            if let page = remoteByID[key], !page.isRemoved {
                plan.operations.append(.archiveRemote(pageID: page.id))
            } else {
                plan.settledTombstones.append(tombstone)
            }
        }

        for expense in local {
            let changedLocally = lastSyncedAt.map { expense.updatedAt > $0 } ?? true
            var linkedPage: NotionPage?
            if let pageID = expense.notionPageID {
                let key = NotionID.normalize(pageID)
                linked.insert(key)
                if let page = remoteByID[key], !page.isRemoved {
                    linkedPage = page
                } else if !changedLocally {
                    plan.operations.append(.deleteLocal(expenseID: expense.id, pageID: pageID))
                    continue
                }
            }
            if linkedPage == nil {
                // Needs a page. One may already exist from a create whose
                // response never arrived.
                guard let orphan = unclaimed.removeValue(forKey: expense.id) else {
                    plan.operations.append(.createRemote(expenseID: expense.id))
                    continue
                }
                linked.insert(NotionID.normalize(orphan.id))
                plan.operations.append(.linkLocal(expenseID: expense.id, pageID: orphan.id))
                linkedPage = orphan
            }
            guard let page = linkedPage else { continue }
            if isSameContent(expense, page) { continue }

            let changedRemotely = lastSyncedAt.map { page.lastEditedTime.addingTimeInterval(60) > $0 } ?? true
            let localWins: Bool
            if !changedLocally {
                localWins = false
            } else if !changedRemotely {
                localWins = true
            } else {
                localWins = expense.updatedAt >= page.lastEditedTime
            }
            plan.operations.append(localWins
                ? .updateRemote(expenseID: expense.id, pageID: page.id)
                : .updateLocal(expenseID: expense.id, pageID: page.id))
        }

        for page in remote where !page.isRemoved {
            let key = NotionID.normalize(page.id)
            guard !linked.contains(key), !tombstoneKeys.contains(key), !discarded.contains(key), !isBlank(page) else { continue }
            linked.insert(key)
            plan.operations.append(.insertLocal(pageID: page.id))
        }
        return plan
    }

    /// The same, comparing content through the account's mapper.
    public static func plan(
        account: Account,
        remote: [NotionPage],
        mapper: ExpenseMapper
    ) -> NotionSyncPlan {
        plan(
            local: account.expenses,
            remote: remote,
            tombstones: account.deletedNotionPageIDs,
            lastSyncedAt: account.notion?.lastSyncedAt,
            isSameContent: { mapper.matches($0, $1, in: account) },
            isBlank: { mapper.remoteExpense(from: $0).isBlank },
            keaserID: { mapper.keaserID(of: $0) },
            deletedExpenseIDs: Set(account.unlinkedDeletions.map(\.expenseID))
        )
    }
}
