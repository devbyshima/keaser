import Foundation
import Testing
@testable import KeaserKit

private func database() -> Database {
    var personal = Account(name: "Personal")
    personal.expenses = [
        Expense(title: "Coffee", amount: Decimal(string: "4.50")!, categoryID: personal.categories[0].id),
        Expense(title: "Taxi", amount: 18),
    ]
    var business = Account(name: "Business")
    business.expenses = [Expense(title: "Lunch", amount: 30)]
    return Database(accounts: [personal, business], preferences: Preferences(currencyCode: "USD", selectedAccountID: personal.id))
}

struct SpotlightMarkerTests {
    @Test func markerNamesFormatVersionAndBuild() {
        #expect(SpotlightPlan.marker(appVersion: "1.2.0", build: "7", format: 3) == "3/1.2.0/7")
        #expect(SpotlightPlan.marker(appVersion: "1.0.0", build: "1") == "\(SpotlightPlan.formatVersion)/1.0.0/1")
    }

    @Test func rebuildsAfterInstallAndEveryUpgrade() {
        let current = SpotlightPlan.marker(appVersion: "1.1.0", build: "4")
        // Fresh install: nothing written yet.
        #expect(SpotlightPlan.needsFullReindex(indexedMarker: nil, currentMarker: current))
        // An update, or a new index format in the same build.
        #expect(SpotlightPlan.needsFullReindex(indexedMarker: SpotlightPlan.marker(appVersion: "1.0.0", build: "3"), currentMarker: current))
        #expect(SpotlightPlan.needsFullReindex(indexedMarker: SpotlightPlan.marker(appVersion: "1.1.0", build: "4", format: 0), currentMarker: current))
        // Same build: only the difference is written.
        #expect(!SpotlightPlan.needsFullReindex(indexedMarker: current, currentMarker: current))
    }
}

struct SpotlightDiffTests {
    @Test func manifestHoldsEveryExpenseAndAccount() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        #expect(manifest.marker == "m")
        #expect(Set(manifest.expenses.keys) == Set(db.accounts.flatMap(\.expenses).map(\.id)))
        #expect(Set(manifest.accounts.keys) == Set(db.accounts.map(\.id)))
    }

    @Test func anEmptyIndexGetsEverything() {
        let db = database()
        let changes = SpotlightPlan.changes(from: SpotlightManifest(), to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.expensesToIndex.count == 3)
        #expect(changes.accountsToIndex.count == 2)
        #expect(changes.expensesToDelete.isEmpty && changes.accountsToDelete.isEmpty)
        #expect(changes.touchesAccounts)
    }

    @Test func nothingChangedWritesNothing() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        let changes = SpotlightPlan.changes(from: manifest, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.isEmpty)
        #expect(!changes.touchesAccounts)
    }

    @Test func savedExpenseIsIndexedAgain() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        db.accounts[0].expenses[1].amount = 19
        let added = Expense(title: "Books", amount: 22)
        db.accounts[0].expenses.append(added)
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(Set(changes.expensesToIndex) == [db.accounts[0].expenses[1].id, added.id])
        #expect(changes.expensesToDelete.isEmpty)
        #expect(!changes.touchesAccounts)
    }

    @Test func deletedExpenseIsRemoved() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        let gone = db.accounts[0].expenses.removeFirst()
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.expensesToDelete == [gone.id])
        #expect(changes.expensesToIndex.isEmpty)
    }

    @Test func deletedAccountTakesItsExpensesOut() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        let gone = db.accounts.removeFirst()
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(Set(changes.expensesToDelete) == Set(gone.expenses.map(\.id)))
        #expect(changes.accountsToDelete == [gone.id])
        #expect(changes.expensesToIndex.isEmpty && changes.accountsToIndex.isEmpty)
    }

    @Test func renamingAnAccountReindexesItsExpenses() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        db.accounts[1].name = "Work"
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.accountsToIndex == [db.accounts[1].id])
        #expect(changes.expensesToIndex == [db.accounts[1].expenses[0].id])
    }

    @Test func renamingACategoryReindexesItsExpensesOnly() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        db.accounts[0].categories[0].name = "Eating Out"
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.expensesToIndex == [db.accounts[0].expenses[0].id])
        #expect(!changes.touchesAccounts)
    }

    @Test func currencyChangeReindexesEveryExpense() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        db.preferences.currencyCode = "EUR"
        let changes = SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m"))
        #expect(changes.expensesToIndex.count == 3)
        #expect(changes.accountsToIndex.isEmpty)
    }

    @Test func reorderingAccountsChangesNothing() {
        var db = database()
        let before = SpotlightPlan.manifest(for: db, marker: "m")
        db.accounts.reverse()
        db.preferences.selectedAccountID = db.accounts[0].id
        #expect(SpotlightPlan.changes(from: before, to: SpotlightPlan.manifest(for: db, marker: "m")).isEmpty)
    }

    @Test func changeListsAreSorted() {
        let db = database()
        let changes = SpotlightPlan.changes(from: SpotlightManifest(), to: SpotlightPlan.manifest(for: db, marker: nil))
        #expect(changes.expensesToIndex == changes.expensesToIndex.sorted { $0.uuidString < $1.uuidString })
    }
}

struct SpotlightSupportTests {
    @Test func fingerprintIsStableAndSensitive() {
        let a = SpotlightPlan.stableHash(["Coffee", "4.5"])
        #expect(a == SpotlightPlan.stableHash(["Coffee", "4.5"]))
        #expect(a != SpotlightPlan.stableHash(["Coffee4", ".5"]))
        #expect(a != SpotlightPlan.stableHash(["Coffee", "4.50"]))
        // FNV-1a's published value for "a", so the hash never drifts.
        #expect(SpotlightPlan.stableHash(["a"]) == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func batchesKeepOrderAndSize() {
        #expect(SpotlightPlan.batches([1, 2, 3, 4, 5], size: 2) == [[1, 2], [3, 4], [5]])
        #expect(SpotlightPlan.batches([Int](), size: 2).isEmpty)
        #expect(SpotlightPlan.batches([1, 2], size: 0) == [[1], [2]])
        #expect(SpotlightPlan.batches(Array(0 ..< 450)).map(\.count) == [200, 200, 50])
    }

    @Test func manifestSurvivesTheDisk() throws {
        let manifest = SpotlightManifest(marker: "1/1.0.0/1", expenses: [UUID(): .max, UUID(): 0], accounts: [UUID(): 42])
        let data = try manifest.encoded()
        #expect(SpotlightManifest.decoded(from: data) == manifest)
        #expect(SpotlightManifest.decoded(from: Data("nope".utf8)) == nil)
    }

    @Test func readsTheIDOutOfASpotlightIdentifier() {
        let id = UUID()
        #expect(SpotlightPlan.entityID(inItemIdentifier: id.uuidString) == id)
        #expect(SpotlightPlan.entityID(inItemIdentifier: "ExpenseEntity/\(id.uuidString)") == id)
        #expect(SpotlightPlan.entityID(inItemIdentifier: "\(UUID().uuidString)#\(id.uuidString)") == id)
        #expect(SpotlightPlan.entityID(inItemIdentifier: "Keaser") == nil)
        #expect(SpotlightPlan.entityID(inItemIdentifier: "") == nil)
    }
}

/// Spotlight asking for items again (iOS 27): written through the same diff
/// as every other change, so the manifest keeps saying what the index holds.
struct SpotlightReindexTests {
    @Test func askedExpensesAreWrittenAgainOrRemoved() {
        var db = database()
        let indexed = SpotlightPlan.manifest(for: db, marker: "m")
        let kept = db.accounts[0].expenses[0].id
        let gone = db.accounts[0].expenses.remove(at: 1).id
        let wanted = SpotlightPlan.manifest(for: db, marker: "m")
        let changes = SpotlightPlan.changes(from: SpotlightPlan.forgetting(.expenses([kept, gone]), in: indexed), to: wanted)
        #expect(changes.expensesToIndex == [kept])
        #expect(changes.expensesToDelete == [gone])
        #expect(!changes.touchesAccounts)
    }

    @Test func anExpenseTheManifestNeverListedIsStillRemovedWhenGone() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        let stray = UUID()
        let changes = SpotlightPlan.changes(from: SpotlightPlan.forgetting(.expenses([stray]), in: manifest), to: manifest)
        #expect(changes.expensesToDelete == [stray])
        #expect(changes.expensesToIndex.isEmpty)
    }

    @Test func askingForEveryExpenseWritesThemAllButNoAccount() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        let changes = SpotlightPlan.changes(from: SpotlightPlan.forgetting(.expenses(nil), in: manifest), to: manifest)
        #expect(changes.expensesToIndex.count == 3)
        #expect(changes.expensesToDelete.isEmpty)
        #expect(changes.accountsToIndex.isEmpty)
    }

    @Test func askingForAccountsLeavesTheExpensesAlone() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        let changes = SpotlightPlan.changes(from: SpotlightPlan.forgetting(.accounts(nil), in: manifest), to: manifest)
        #expect(Set(changes.accountsToIndex) == Set(db.accounts.map(\.id)))
        #expect(changes.expensesToIndex.isEmpty)
        #expect(changes.touchesAccounts)
        let one = SpotlightPlan.changes(from: SpotlightPlan.forgetting(.accounts([db.accounts[1].id]), in: manifest), to: manifest)
        #expect(one.accountsToIndex == [db.accounts[1].id])
    }

    @Test func theMarkerIsKeptSoNothingElseIsRebuilt() {
        let manifest = SpotlightPlan.manifest(for: database(), marker: "1/1.0.0/1")
        #expect(SpotlightPlan.forgetting(.expenses(nil), in: manifest).marker == "1/1.0.0/1")
    }

    @Test func noItemHasTheUnknownFingerprint() {
        let db = database()
        let manifest = SpotlightPlan.manifest(for: db, marker: "m")
        #expect(!manifest.expenses.values.contains(SpotlightPlan.unknownFingerprint))
        #expect(!manifest.accounts.values.contains(SpotlightPlan.unknownFingerprint))
        // FNV-1a of nothing at all is its offset basis, never zero.
        #expect(SpotlightPlan.stableHash([]) != SpotlightPlan.unknownFingerprint)
    }
}
