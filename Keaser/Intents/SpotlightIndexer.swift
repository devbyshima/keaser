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
/// once. Which items the index holds is kept in a small file in the app's
/// caches, not in the shared database: a backup restores neither the index
/// nor that file, so a restored iPhone rebuilds the index.
///
/// Every write, including the ones Spotlight asks for on iOS 27, goes
/// through one serial queue of syncs, so two never write at once and the
/// manifest always says what the index holds.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private weak var store: KeaserStore?
    /// What the index holds, as of the last successful write in this
    /// process. Nil until the first sync has read it from disk.
    private var indexed: SpotlightManifest?
    private var pending: Task<Void, Never>?
    private let work = SerialWork()

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
        await work.run(within: .seconds(3)) { [weak self] in await self?.syncChanges() }
    }

    private func schedule(after delay: Duration = .milliseconds(500)) {
        guard store != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            // After any sync that is already running, so the later one
            // always sees the earlier one's result.
            self.work.start { [weak self] in await self?.syncChanges() }
        }
    }

    /// Writes the difference between the index and the store. With a
    /// `request` from Spotlight, the items it names are written again too
    /// (or removed, when they are gone). Throws only for a request, so
    /// Spotlight asks again later.
    private func performSync(_ request: SpotlightReindex?, protectionClass: FileProtectionType?) async throws {
        // Before the first unlock after a restart the store holds an empty
        // stand-in for a file it cannot read, which must not empty the index.
        guard let store, store.loadError == nil else {
            if request != nil { throw CocoaError(.fileReadNoPermission) }
            return
        }
        do {
            let outcome = try await Self.bringUpToDate(
                store.database, from: indexed, marker: Self.currentMarker,
                forgetting: request, protectionClass: protectionClass
            )
            indexed = outcome.manifest
            // Siri's "Open <account> in Keaser" phrases name the accounts.
            if outcome.touchesAccounts { KeaserShortcuts.updateAppShortcutParameters() }
        } catch {
            // `indexed` still describes the index as it was, so the next
            // change writes this difference again.
            Self.log.error("Spotlight sync failed: \(error.localizedDescription, privacy: .public)")
            if request != nil { throw error }
        }
    }

    /// `performSync(_:protectionClass:)` for store changes, which retry on
    /// the next change rather than throw.
    private func syncChanges() async {
        try? await performSync(nil, protectionClass: nil)
    }

    private struct Outcome: Sendable {
        let manifest: SpotlightManifest
        let touchesAccounts: Bool
    }

    /// Works out and writes the difference between the index and
    /// `database`, away from the main actor (a rebuild can be thousands of
    /// items).
    @concurrent
    private nonisolated static func bringUpToDate(
        _ database: Database,
        from known: SpotlightManifest?,
        marker: String,
        forgetting request: SpotlightReindex? = nil,
        protectionClass: FileProtectionType? = nil
    ) async throws -> Outcome {
        let stored = known ?? readManifest() ?? SpotlightManifest()
        let baseline = request.map { SpotlightPlan.forgetting($0, in: stored) } ?? stored
        let rebuild = SpotlightPlan.needsFullReindex(indexedMarker: baseline.marker, currentMarker: marker)
        let wanted = SpotlightPlan.manifest(for: database, marker: marker)
        let changes = SpotlightPlan.changes(from: rebuild ? SpotlightManifest() : baseline, to: wanted)
        guard rebuild || !changes.isEmpty else {
            return Outcome(manifest: stored, touchesAccounts: false)
        }

        let index = makeIndex(protectionClass: protectionClass)
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

    // MARK: Spotlight asking for items again (iOS 27)

    /// Writes the items Spotlight asks for again, from the store as it is
    /// now, in turn with every other sync: an expense deleted meanwhile is
    /// removed rather than brought back, and one put back is indexed rather
    /// than dropped. Throws while the data cannot be read (before the first
    /// unlock), so Spotlight asks again later.
    nonisolated static func reindex(_ request: SpotlightReindex, protectionClass: FileProtectionType?) async throws {
        try await shared.reindex(request, protectionClass: protectionClass)
    }

    private func reindex(_ request: SpotlightReindex, protectionClass: FileProtectionType?) async throws {
        let store = AppEnvironment.store
        // An intent query may run before anything else in this process.
        attach(to: store)
        // Seeded launches never index (see `attach`).
        guard self.store != nil else { return }
        store.reloadFromDisk()
        try await work.perform { [weak self] in
            try await self?.performSync(request, protectionClass: protectionClass)
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

    /// In the app's own caches: only the app writes to Spotlight. Caches are
    /// never backed up, and neither is the index, so after a restore (or
    /// when the system clears caches) there is no manifest and the index is
    /// rebuilt. In backed-up storage the manifest would come back without
    /// the index and claim everything was still indexed.
    private nonisolated static var manifestURL: URL {
        URL.cachesDirectory.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "spotlight-index.json")
    }

    /// Where earlier builds kept it, in backed-up storage.
    private nonisolated static var legacyManifestURL: URL {
        URL.applicationSupportDirectory.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "spotlight-index.json")
    }

    /// Nil when there is none yet or it cannot be read, which rebuilds the
    /// index.
    private nonisolated static func readManifest() -> SpotlightManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else {
            // The rebuild this causes replaces whatever the old copy said.
            try? FileManager.default.removeItem(at: legacyManifestURL)
            return nil
        }
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
