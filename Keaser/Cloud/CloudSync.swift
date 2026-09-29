import Foundation
import KeaserKit
import Observation
import UIKit
import os

/// iCloud sync: keeps this device's data and the person's private iCloud
/// database in step, so every device signed in to the same Apple Account
/// shows the same accounts, expenses, labels and shared settings.
///
/// Compiled into every build but inert unless `CloudSyncSwitch.isEnabled`:
/// then nothing is created, no CloudKit call is made and nothing is shown.
/// When on, it watches the store's changes (a second after the last one, so
/// a burst of edits is planned once) and hands them to `CloudSyncEngine`,
/// which does the CloudKit work off the main actor.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    /// Where sync stands; nil while it is off.
    private(set) var status: CloudSyncStatus?

    @ObservationIgnored private weak var store: KeaserStore?
    @ObservationIgnored private var engine: CloudSyncEngine?
    @ObservationIgnored private var pendingPlan: Task<Void, Never>?

    /// What the Settings line shows: the live status, or in DEBUG the one
    /// `-KeaserCloudStatus <state>` asks for, to screenshot the line in a
    /// build without sync. Nil shows nothing.
    var displayedStatus: CloudSyncStatus? {
        #if DEBUG
        if let name = DebugLaunch.string("KeaserCloudStatus"), let preview = CloudSyncStatus.preview(named: name) {
            return preview
        }
        #endif
        return status
    }

    /// Whether the bundled documents speak of iCloud sync (the privacy
    /// policy's `<!-- if icloud -->` sections): in builds that sync, and in
    /// DEBUG previews of the status line.
    var documentFlags: Set<String> {
        CloudSyncSwitch.isEnabled || displayedStatus != nil ? ["icloud"] : []
    }

    /// Starts syncing `store`. Safe to call more than once (App Intents call
    /// it when they run without the app's UI); does nothing while sync is
    /// off.
    func attach(to store: KeaserStore) {
        guard CloudSyncSwitch.isEnabled, self.store !== store else { return }
        self.store = store
        status = .syncing
        let engine = CloudSyncEngine(bridge: CloudStoreBridge(store: store), attachments: FolderAttachmentFiles.receipts) { status in
            Task { @MainActor in CloudSync.shared.status = status }
        }
        self.engine = engine
        store.addObserver { [weak self] change in
            // A merge from iCloud plans what it changed itself.
            guard change != .mergedFromCloud else { return }
            self?.schedulePlan()
        }
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            Task { await engine.accountChanged() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await engine.becameActive() }
        }
        // Silent pushes wake the engine when another device changes data.
        UIApplication.shared.registerForRemoteNotifications()
        Task { await engine.start() }
    }

    /// Hands what changed here to the engine now, waiting two seconds at
    /// most, for App Intents that change data and may be suspended as soon
    /// as they return. The engine sends it whenever it can, in this launch
    /// or the next.
    func flush() async {
        guard let engine else { return }
        pendingPlan?.cancel()
        pendingPlan = nil
        _ = await Deadline.value(within: .seconds(2)) { () -> Bool? in
            await engine.planUpload()
            return true
        }
    }

    #if DEBUG
    /// The App Intents tests replace the whole database with their fixture:
    /// sync stops for good on this install, before that could reach iCloud.
    func stopForTestData() async {
        UserDefaults.standard.set(true, forKey: CloudSyncSwitch.testDataKey)
        pendingPlan?.cancel()
        await engine?.shutDown()
        engine = nil
        store = nil
        status = nil
    }
    #endif

    private func schedulePlan() {
        pendingPlan?.cancel()
        pendingPlan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let engine = self?.engine else { return }
            await engine.planUpload()
        }
    }
}

/// The engine's way into the store, which lives on the main actor.
@MainActor
final class CloudStoreBridge {
    private weak var store: KeaserStore?

    init(store: KeaserStore) {
        self.store = store
    }

    struct Snapshot: Sendable {
        let database: Database
        let revision: Int
    }

    /// The database to diff or merge into, or nil while it must not be
    /// touched: unreadable (before the first unlock, when the store holds an
    /// empty stand-in that would read as everything deleted), or holding a
    /// change that could not be saved (sent, it could outlive a file that
    /// never gets it).
    func snapshot() -> Snapshot? {
        guard let store, store.loadError == nil, store.lastSaveError == nil else { return nil }
        return Snapshot(database: store.database, revision: store.revision)
    }

    func apply(_ merged: Database, ifRevision revision: Int) -> CloudMergeOutcome {
        store?.applyCloudChanges(merged, ifRevision: revision) ?? .notSaved
    }
}

/// The sync state on disk: `Application Support/Keaser/cloud-sync.plist` in
/// the app's own container (only the app syncs). Backed up with the
/// database, so a restored iPhone carries on where the backup left off.
struct CloudSyncStateFile: Sendable {
    let url: URL

    static var shared: CloudSyncStateFile {
        CloudSyncStateFile(url: URL.applicationSupportDirectory.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "cloud-sync.plist"))
    }

    private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "CloudSync")

    /// Nil when there is none yet, or it does not read: sync then starts as
    /// a first sync, which merges with iCloud instead of overwriting it.
    func read() -> SyncState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let state = SyncState.decoded(from: data) else {
            Self.log.error("Sync state unreadable; starting over with a merge")
            return nil
        }
        return state
    }

    func write(_ state: SyncState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try state.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
