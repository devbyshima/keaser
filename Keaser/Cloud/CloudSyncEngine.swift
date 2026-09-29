import CloudKit
import KeaserKit
import os

/// Runs CKSyncEngine over the person's private database, in one custom zone
/// (`SyncSchema.zoneName`), away from the main actor.
///
/// The engine does the network work and the scheduling (push notifications,
/// retries after network and rate-limit errors); this delegate decides what
/// to send and what fetched changes mean, through KeaserKit's pure
/// `SyncPlan` and `SyncMerge`, and keeps `SyncState` on disk.
///
/// - Nothing local is sent before the first full fetch, so a device that
///   already has data merges with iCloud first.
/// - Fetched changes are saved to the state's inbox before they are merged,
///   and merged into a copy of the database off the main actor; the store
///   takes the result only if it did not change meanwhile (otherwise the
///   merge runs again), in one save announced as `.mergedFromCloud`.
/// - A conflict on save (another device saved first) and a save that finds
///   the record gone go through the same merge as fetched changes.
/// - Signed out, or signed in with another Apple Account: sync stops and
///   everything stays on the device. It never syncs one person's data into
///   another's iCloud.
/// - The zone gone (deleted from Settings or another device, or encrypted
///   data reset): local data stays and is uploaded again, merging as on a
///   first sync.
actor CloudSyncEngine: CKSyncEngineDelegate {
    private let bridge: CloudStoreBridge
    private let attachments: any CloudAttachmentFiles
    private let report: @Sendable (CloudSyncStatus) -> Void
    private let stateFile: CloudSyncStateFile
    private let zoneID = CKRecordZone.ID(zoneName: SyncSchema.zoneName)

    private var container: CKContainer?
    private var engine: CKSyncEngine?
    private var state: SyncState
    /// A problem that outlasts the sync that ran into it (full storage, no
    /// network), cleared by the next sync that finishes cleanly.
    private var problem: CloudSyncStatus?
    private var isStarting = false
    private var fetchFailed = false
    private var sendFailed = false
    private var lastFetch: Date?

    /// How many pending changes one batch is built from.
    private static let batchSize = 400
    private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "CloudSync")

    init(bridge: CloudStoreBridge, attachments: any CloudAttachmentFiles, stateFile: CloudSyncStateFile = .shared, report: @escaping @Sendable (CloudSyncStatus) -> Void) {
        self.bridge = bridge
        self.attachments = attachments
        self.stateFile = stateFile
        self.report = report
        state = stateFile.read() ?? SyncState()
    }

    // MARK: Starting and stopping

    /// Checks the iCloud account and starts the engine. Safe to call again:
    /// after a sign-in, or when the app comes back with sync stopped.
    func start() async {
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let container = container ?? CKContainer(identifier: SyncSchema.containerIdentifier)
        self.container = container
        guard await accountIsUsable(container) else { return }

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: engineSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !state.zoneSaved {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        problem = nil
        report(currentStatus)
        // Changes that arrived while the database could not be written, and
        // records an older build kept aside that this one may now apply.
        await exclusively { await mergeInbox(evenIfEmpty: !state.parked.isEmpty) }
        if state.hasCompletedInitialSync {
            await planUpload()
        } else {
            await initialFetch()
        }
    }

    /// The app became active: catch up with what a missed push would have
    /// brought, and queue again what a failure dropped (full storage).
    func becameActive() async {
        guard let engine else {
            await start()
            return
        }
        guard state.hasCompletedInitialSync else {
            await initialFetch()
            return
        }
        if lastFetch.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
            do {
                try await engine.fetchChanges()
            } catch {
                setProblem(CloudRecords.status(for: error))
            }
        }
        await planUpload()
    }

    /// iCloud's account changed (`CKAccountChanged`). A running engine hears
    /// of it itself; a stopped one starts again if the account now allows.
    func accountChanged() async {
        if engine == nil { await start() }
    }

    private func accountIsUsable(_ container: CKContainer) async -> Bool {
        do {
            switch try await container.accountStatus() {
            case .available: break
            case .noAccount:
                setProblem(.iCloudOff)
                return false
            case .restricted:
                setProblem(.restricted)
                return false
            case .couldNotDetermine, .temporarilyUnavailable:
                setProblem(.unavailable)
                return false
            @unknown default:
                setProblem(.unavailable)
                return false
            }
            let user = try await container.userRecordID().recordName
            if let synced = state.userRecordName, synced != user {
                setProblem(.otherAccount)
                return false
            }
            if state.userRecordName == nil {
                state.userRecordName = user
                save()
            }
            return true
        } catch {
            setProblem(CloudRecords.status(for: error))
            return false
        }
    }

    /// Stops for good in this launch (see `CloudSync.stopForTestData`).
    func shutDown() async {
        let stopped = engine
        engine = nil
        await stopped?.cancelOperations()
    }

    /// Stops syncing and keeps everything on the device. The state stays, so
    /// the same Apple Account signing back in carries on where it stopped.
    private func stop(_ reason: CloudSyncStatus) {
        setProblem(reason)
        let stopped = engine
        engine = nil
        // Not awaited here: this runs inside one of the engine's own events.
        Task { await stopped?.cancelOperations() }
    }

    // MARK: The first fetch

    /// Fetches everything iCloud holds and merges it before anything local
    /// goes out. Tried again when the app next becomes active if it fails.
    private func initialFetch() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            await completeInitialSync()
        } catch {
            Self.log.error("First fetch failed: \(error.localizedDescription, privacy: .public)")
            setProblem(CloudRecords.status(for: error))
        }
    }

    private func completeInitialSync() async {
        let completed = await exclusively { () -> Bool in
            guard !state.hasCompletedInitialSync else { return false }
            await mergeInbox()
            // Merged with nothing waiting: only then may local data go out.
            guard state.inbox.isEmpty else { return false }
            state.hasCompletedInitialSync = true
            save()
            return true
        }
        if completed { await planUpload() }
    }

    // MARK: Local changes

    /// Works out what changed here since iCloud last heard and queues it in
    /// the engine, which sends it when it can.
    func planUpload() async {
        await exclusively {
            guard let engine else { return }
            await mergeInbox()
            guard state.inbox.isEmpty, let snapshot = await bridge.snapshot() else { return }
            var planned = state
            let upload = SyncPlan.upload(for: snapshot.database, state: &planned, now: .now)
            state = planned
            save()
            guard !upload.isEmpty else { return }
            let saves = upload.saves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID($0)) }
            let deletes = upload.deletes.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID($0)) }
            engine.state.add(pendingRecordZoneChanges: saves + deletes)
        }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            await exclusively {
                state.engineState = try? JSONEncoder().encode(update.stateSerialization)
                save()
            }
        case .accountChange(let change):
            await accountChanged(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                await zoneWasLost()
            }
        case .fetchedRecordZoneChanges(let changes):
            await receive(changes)
        case .sentDatabaseChanges(let sent):
            await exclusively {
                if sent.savedZones.contains(where: { $0.zoneID == zoneID }) {
                    state.zoneSaved = true
                    save()
                }
            }
            for failure in sent.failedZoneSaves {
                Self.log.error("Zone not saved: \(failure.error.localizedDescription, privacy: .public)")
                sendFailed = true
                setProblem(CloudRecords.status(for: failure.error))
            }
        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)
        case .willFetchChanges:
            fetchFailed = false
            if problem == nil { report(.syncing) }
        case .didFetchRecordZoneChanges(let done):
            if done.zoneID == zoneID, let error = done.error, error.code != .zoneNotFound {
                fetchFailed = true
                setProblem(CloudRecords.status(for: error))
            }
        case .didFetchChanges:
            lastFetch = .now
            guard !fetchFailed else { return }
            if !state.hasCompletedInitialSync {
                await completeInitialSync()
            } else {
                // Changes the merge made itself (two labels become one...).
                await planUpload()
            }
            await synced()
        case .willSendChanges:
            sendFailed = false
            if problem == nil { report(.syncing) }
        case .didSendChanges:
            if !sendFailed { await synced() }
        case .willFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty, let snapshot = await bridge.snapshot() else { return nil }
        let state = self.state
        var ready: [CKRecord.ID: CKRecord] = [:]
        var batch: [CKSyncEngine.PendingRecordZoneChange] = []
        var dropped: [CKSyncEngine.PendingRecordZoneChange] = []
        // Built a slice at a time, looked up in one pass per slice.
        var start = 0
        while batch.isEmpty, start < pending.count {
            let slice = Array(pending[start ..< min(start + Self.batchSize, pending.count)])
            start += Self.batchSize
            let names = slice.compactMap { change -> String? in
                if case .saveRecord(let id) = change { return id.recordName }
                return nil
            }
            let records = SyncPlan.outgoingRecords(named: names, in: snapshot.database, state: state)
            for change in slice {
                switch change {
                case .saveRecord(let id):
                    // Gone since, already in iCloud as it is here, or its file
                    // is not on this device: nothing to send.
                    guard let record = records[id.recordName], SyncPlan.needsSending(record, state: state),
                          let ckRecord = CloudRecords.ckRecord(for: record, zoneID: zoneID, known: state.known[id.recordName], attachments: attachments)
                    else {
                        dropped.append(change)
                        continue
                    }
                    ready[id] = ckRecord
                    batch.append(change)
                case .deleteRecord:
                    batch.append(change)
                @unknown default:
                    dropped.append(change)
                }
            }
        }
        if !dropped.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: dropped) }
        guard !batch.isEmpty else { return nil }
        let prepared = ready
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { prepared[$0] }
    }

    // MARK: Events

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn(let user):
            if let synced = state.userRecordName, synced != user.recordName {
                stop(.otherAccount)
            } else {
                await exclusively {
                    state.userRecordName = user.recordName
                    save()
                }
                problem = nil
                Task { await self.planUpload() }
            }
        case .signOut:
            stop(.iCloudOff)
        case .switchAccounts(_, let user):
            if state.userRecordName != user.recordName { stop(.otherAccount) }
        @unknown default:
            break
        }
    }

    private func receive(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        await exclusively {
            for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
                state.receive(CloudRecords.fetched(from: modification.record, attachments: attachments))
            }
            for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                state.receiveDeletion(of: deletion.recordID.recordName, type: SyncRecordType(deletion.recordType))
            }
            // Kept before merging, so nothing is lost if the merge cannot
            // run now or the app stops.
            save()
            await mergeInbox()
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        var zoneLost = false
        let merged = await exclusively { () -> Bool in
            var needsMerge = false
            for record in sent.savedRecords where record.recordID.zoneID == zoneID {
                state.confirmSaved(CloudRecords.fetched(from: record, attachments: nil))
            }
            for id in sent.deletedRecordIDs where id.zoneID == zoneID {
                state.confirmDeleted(id.recordName)
            }
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Another device saved first: its copy goes through the
                    // merge, and the winner is sent again if it is ours.
                    if let server = failure.error.serverRecord {
                        state.receive(CloudRecords.fetched(from: server, attachments: attachments))
                        needsMerge = true
                    }
                case .unknownItem:
                    // Deleted in iCloud since: our edit outlives it and goes
                    // out again as a new record.
                    state.receiveDeletion(of: name, type: SyncRecordType(failure.record.recordType))
                    needsMerge = true
                case .zoneNotFound, .userDeletedZone:
                    zoneLost = true
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                     .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled:
                    // The engine tries these again itself.
                    sendFailed = true
                    setProblem(CloudRecords.status(for: failure.error))
                default:
                    // Full storage and the rest: queued again by the next
                    // plan (a change here, or the app becoming active), not
                    // straight away, so a lasting failure cannot spin.
                    sendFailed = true
                    setProblem(CloudRecords.status(for: failure.error))
                    Self.log.error("Save of \(name, privacy: .public) failed: \(failure.error.localizedDescription, privacy: .public)")
                }
            }
            for (id, error) in sent.failedRecordDeletes where id.zoneID == zoneID {
                if error.code == .unknownItem {
                    state.confirmDeleted(id.recordName)
                } else {
                    sendFailed = true
                    setProblem(CloudRecords.status(for: error))
                }
            }
            save()
            if needsMerge { await mergeInbox() }
            return needsMerge
        }
        if zoneLost { await zoneWasLost() }
        if merged { Task { await self.planUpload() } }
    }

    /// The zone is gone from iCloud. Everything here stays and goes up
    /// again once a fetch has shown what other devices put back first.
    private func zoneWasLost() async {
        await exclusively {
            state.forgetZone()
            save()
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        // Not awaited inside the event that reported it.
        Task { await self.initialFetch() }
    }

    // MARK: Merging

    /// Merges the inbox into the store: off the main actor, into a copy,
    /// taken by the store only if it did not change meanwhile. Must run
    /// inside `exclusively`.
    private func mergeInbox(evenIfEmpty: Bool = false) async {
        guard !state.inbox.isEmpty || evenIfEmpty else { return }
        for _ in 0 ..< 3 {
            // Unreadable before the first unlock, or holding an unsaved
            // change: the inbox waits for the next chance.
            guard let snapshot = await bridge.snapshot() else { return }
            let result = SyncMerge.apply(to: snapshot.database, state: state, now: .now)
            switch await bridge.apply(result.database, ifRevision: snapshot.revision) {
            case .saved:
                state = result.state
                save()
                for asset in result.removedAssets { attachments.remove(asset) }
                return
            case .stale:
                continue
            case .notSaved:
                return
            }
        }
    }

    // MARK: Status

    private var currentStatus: CloudSyncStatus {
        problem ?? state.lastSyncedAt.map(CloudSyncStatus.synced) ?? .syncing
    }

    private func setProblem(_ status: CloudSyncStatus) {
        problem = status
        report(status)
    }

    private func synced() async {
        guard engine != nil else { return }
        problem = nil
        let now = Date.now
        await exclusively {
            state.lastSyncedAt = now
            save()
        }
        report(.synced(now))
    }

    // MARK: Storage

    private var engineSerialization: CKSyncEngine.State.Serialization? {
        state.engineState.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    }

    private func save() {
        do {
            try stateFile.write(state)
        } catch {
            Self.log.error("Sync state not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    // MARK: One at a time

    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` alone: every change to `state` reads it, awaits the store
    /// or the disk, then writes it, and two of those interleaving at an
    /// await would lose one's write. Never nests; never awaits the engine
    /// (which may be waiting on the event that is running).
    private func exclusively<T>(_ body: () async -> T) async -> T {
        while isBusy {
            await withCheckedContinuation { waiting.append($0) }
        }
        isBusy = true
        defer {
            isBusy = false
            if !waiting.isEmpty { waiting.removeFirst().resume() }
        }
        return await body()
    }
}
