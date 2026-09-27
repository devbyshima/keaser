import AppIntents
import CoreSpotlight
import Foundation
import KeaserKit
import os

/// Keeps Keaser's named Spotlight index in step with the store: every
/// expense and account, on the iPhone only, so system search and Siri can
/// find them.
///
/// Attached once at launch. The first sync catches up with whatever changed
/// since the app last ran, or rebuilds the whole index when it was written
/// by another build (see `SpotlightPlan`); after that every store change
/// writes only the difference, a moment later so a burst of edits is written
/// once. Which items the index holds is kept in a small file beside the app's
/// data, not in the shared database.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private weak var store: KeaserStore?
    /// What the index holds, as of the last successful write in this
    /// process. Nil until the first sync has read it from disk.
    private var indexed: SpotlightManifest?
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?

    nonisolated private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "Spotlight")

    /// Starts keeping the index in step with `store`. Safe to call more than
    /// once (App Intents call it when they run without the app's UI).
    func attach(to store: KeaserStore) {
        guard self.store !== store else { return }
        #if DEBUG
        // Seeded launches keep made-up data in memory; indexed, it would
        // leave results in Spotlight that no later launch can open.
        // `-KeaserSpotlight index` indexes a seed anyway, to test indexing.
        if DebugLaunch.seed != nil, DebugLaunch.string("KeaserSpotlight") != "index" { return }
        #endif
        self.store = store
        store.addObserver { [weak self] _ in self?.schedule() }
        schedule(after: .zero)
    }

    /// Writes any pending change now and waits for it, for App Intents that
    /// change data and may be suspended as soon as they return. Waits a few
    /// seconds at most: a rebuild after an update carries on in the
    /// background, and the next launch finishes whatever is left.
    func flush() async {
        guard store != nil else { return }
        pending?.cancel()
        pending = nil
        let work = Task { await self.sync() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await work.value }
            group.addTask { try? await Task.sleep(for: .seconds(3)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func schedule(after delay: Duration = .milliseconds(500)) {
        guard store != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Runs one sync after any that is already running, so two never write
    /// at once and the later one always sees the earlier one's result.
    private func sync() async {
        let previous = running
        let task = Task { [weak self] in
            await previous?.value
            await self?.performSync()
        }
        running = task
        await task.value
    }

    private func performSync() async {
        // Before the first unlock after a restart the store holds an empty
        // stand-in for a file it cannot read, which must not empty the index.
        guard let store, store.loadError == nil else { return }
        do {
            let outcome = try await Self.bringUpToDate(store.database, from: indexed, marker: Self.currentMarker)
            indexed = outcome.manifest
            // Siri's "Open <account> in Keaser" phrases name the accounts.
            if outcome.touchesAccounts { KeaserShortcuts.updateAppShortcutParameters() }
        } catch {
            // `indexed` still describes the index as it was, so the next
            // change writes this difference again.
            Self.log.error("Spotlight sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct Outcome: Sendable {
        let manifest: SpotlightManifest
        let touchesAccounts: Bool
    }

    /// Works out and writes the difference between the index and
    /// `database`, away from the main actor (a rebuild can be thousands of
    /// items).
    @concurrent
    private nonisolated static func bringUpToDate(_ database: Database, from known: SpotlightManifest?, marker: String) async throws -> Outcome {
        let baseline = known ?? readManifest() ?? SpotlightManifest()
        let rebuild = SpotlightPlan.needsFullReindex(indexedMarker: baseline.marker, currentMarker: marker)
        let wanted = SpotlightPlan.manifest(for: database, marker: marker)
        let changes = SpotlightPlan.changes(from: rebuild ? SpotlightManifest() : baseline, to: wanted)
        guard rebuild || !changes.isEmpty else {
            return Outcome(manifest: baseline, touchesAccounts: false)
        }

        let index = makeIndex()
        if rebuild { try await index.deleteAllSearchableItems() }
        for batch in SpotlightPlan.batches(changes.expensesToDelete) {
            try await index.deleteAppEntities(identifiedBy: batch, ofType: ExpenseEntity.self)
        }
        for batch in SpotlightPlan.batches(changes.accountsToDelete) {
            try await index.deleteAppEntities(identifiedBy: batch, ofType: AccountEntity.self)
        }
        let expenses = EntityCatalog.expenses(withIDs: changes.expensesToIndex, in: database)
        for batch in SpotlightPlan.batches(expenses) {
            try await index.indexAppEntities(batch.map(ExpenseEntity.init))
        }
        let accountIDs = Set(changes.accountsToIndex)
        let accounts = database.accounts.filter { accountIDs.contains($0.id) }
        for batch in SpotlightPlan.batches(accounts) {
            try await index.indexAppEntities(batch.map(AccountEntity.init))
        }

        writeManifest(wanted)
        log.info("""
            Spotlight \(rebuild ? "rebuilt" : "updated", privacy: .public): \
            \(expenses.count) expenses and \(accounts.count) accounts indexed, \
            \(changes.expensesToDelete.count) expenses and \(changes.accountsToDelete.count) accounts removed
            """)
        return Outcome(manifest: wanted, touchesAccounts: rebuild || changes.touchesAccounts)
    }

    // MARK: Spotlight asking for a rebuild (iOS 27)

    /// Indexes these expenses again (all of them for nil) from the shared
    /// file, and removes any of the asked-for IDs that no longer exist.
    @concurrent
    nonisolated static func reindexExpenses(_ ids: [UUID]?, protectionClass: FileProtectionType?) async throws {
        // Throws while the file is locked, rather than taking an unreadable
        // file for an empty one.
        let database = try DatabaseFile.shared.read() ?? Database()
        let index = makeIndex(protectionClass: protectionClass)
        let found = ids.map { EntityCatalog.expenses(withIDs: $0, in: database) } ?? EntityCatalog.allExpenses(in: database)
        for batch in SpotlightPlan.batches(found) {
            try await index.indexAppEntities(batch.map(ExpenseEntity.init))
        }
        if let ids {
            let existing = Set(found.map(\.id))
            let gone = ids.filter { !existing.contains($0) }
            if !gone.isEmpty { try await index.deleteAppEntities(identifiedBy: gone, ofType: ExpenseEntity.self) }
        }
    }

    /// `reindexExpenses` for accounts.
    @concurrent
    nonisolated static func reindexAccounts(_ ids: [UUID]?, protectionClass: FileProtectionType?) async throws {
        let database = try DatabaseFile.shared.read() ?? Database()
        let index = makeIndex(protectionClass: protectionClass)
        let found = ids.map { wanted in database.accounts.filter { wanted.contains($0.id) } } ?? database.accounts
        if !found.isEmpty { try await index.indexAppEntities(found.map(AccountEntity.init)) }
        if let ids {
            let existing = Set(found.map(\.id))
            let gone = ids.filter { !existing.contains($0) }
            if !gone.isEmpty { try await index.deleteAppEntities(identifiedBy: gone, ofType: AccountEntity.self) }
        }
    }

    // MARK: Storage

    /// Readable after the first unlock, like the database file.
    private nonisolated static func makeIndex(protectionClass: FileProtectionType? = nil) -> CSSearchableIndex {
        CSSearchableIndex(name: SpotlightPlan.indexName, protectionClass: protectionClass ?? .completeUntilFirstUserAuthentication)
    }

    /// The build writing the index now.
    private nonisolated static var currentMarker: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return SpotlightPlan.marker(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            build: info["CFBundleVersion"] as? String ?? "0"
        )
    }

    /// In the app's own container: only the app writes to Spotlight.
    private nonisolated static var manifestURL: URL {
        URL.applicationSupportDirectory.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "spotlight-index.json")
    }

    /// Nil when there is none yet or it cannot be read, which rebuilds the
    /// index.
    private nonisolated static func readManifest() -> SpotlightManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return SpotlightManifest.decoded(from: data)
    }

    private nonisolated static func writeManifest(_ manifest: SpotlightManifest) {
        do {
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manifest.encoded().write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // The next launch then rebuilds the index, which is only slower.
            log.error("Spotlight manifest not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
