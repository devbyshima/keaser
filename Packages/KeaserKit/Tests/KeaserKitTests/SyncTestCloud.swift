import Foundation
import Testing
@testable import KeaserKit

/// A stand-in for Keaser's iCloud zone with CloudKit's rules: every save
/// bumps a record's change tag; a save carrying a stale tag, or a create over
/// an existing record, is refused with the server's copy (a conflict); a save
/// carrying a tag for a record that is gone is refused as unknown; fetches
/// return what changed since a token. A device never hears back about its
/// own last change to a record, so nothing relies on seeing it echoed.
final class TestCloud {
    struct Stored {
        var type: SyncRecordType
        var payload: Data
        var tag: Int
    }

    enum SaveResult {
        case saved(FetchedRecord)
        case conflict(FetchedRecord)
        case unknownItem
    }

    private(set) var records: [String: Stored] = [:]
    private var log: [(sequence: Int, name: String)] = []
    /// Who changed each record last (nil: written straight into the zone).
    private var lastWriter: [String: UUID] = [:]
    private var sequence = 0
    private var nextTag = 1

    func save(_ record: SyncRecord, systemFields: Data?, by writer: UUID? = nil) -> SaveResult {
        let tag = systemFields.flatMap(Self.tag)
        if let stored = records[record.name] {
            guard tag == stored.tag else { return .conflict(fetched(record.name, stored)) }
        } else if tag != nil {
            return .unknownItem
        }
        let saved = put(name: record.name, type: record.type, payload: record.payload)
        lastWriter[record.name] = writer
        return .saved(saved)
    }

    /// Writes straight into the zone, as a later version of Keaser would.
    @discardableResult
    func put(name: String, type: SyncRecordType, payload: Data) -> FetchedRecord {
        let stored = Stored(type: type, payload: payload, tag: nextTag)
        nextTag += 1
        records[name] = stored
        lastWriter[name] = nil
        record(name)
        return fetched(name, stored)
    }

    func delete(_ name: String, by writer: UUID? = nil) {
        guard records.removeValue(forKey: name) != nil else { return }
        lastWriter[name] = writer
        record(name)
    }

    /// Everything, as after the person deleted Keaser's iCloud data.
    func wipe() {
        for name in records.keys { delete(name) }
    }

    func changes(since token: Int, for reader: UUID? = nil) -> (saved: [FetchedRecord], deleted: [(String, SyncRecordType)], token: Int) {
        let names = Set(log.filter { $0.sequence > token }.map(\.name)).filter { reader == nil || lastWriter[$0] != reader }
        var saved: [FetchedRecord] = []
        var deleted: [(String, SyncRecordType)] = []
        for name in names.sorted() {
            if let stored = records[name] {
                saved.append(fetched(name, stored))
            } else {
                deleted.append((name, SyncKinds.kind(forName: name)?.type ?? SyncRecordType("Unknown")))
            }
        }
        return (saved, deleted, sequence)
    }

    func body(of name: String) -> [String: JSONValue]? {
        guard let stored = records[name] else { return nil }
        return try? SyncRecord(name: name, type: stored.type, payload: stored.payload).body
    }

    func names(of type: SyncRecordType) -> [String] {
        records.filter { $0.value.type == type }.map(\.key).sorted()
    }

    private func record(_ name: String) {
        sequence += 1
        log.append((sequence, name))
    }

    private func fetched(_ name: String, _ stored: Stored) -> FetchedRecord {
        FetchedRecord(name: name, type: stored.type, payload: stored.payload, systemFields: Data("\(stored.tag)".utf8))
    }

    static func tag(_ systemFields: Data) -> Int? {
        Int(String(decoding: systemFields, as: UTF8.self))
    }
}

/// One device: a store in memory, its sync state, and the fetch token, run
/// through the same steps as the app's `CloudSyncEngine`.
@MainActor
final class TestDevice {
    let store: KeaserStore
    var state = SyncState()
    /// Names this device to the fake zone.
    let id = UUID()
    private var token = 0

    init(_ database: Database = Database()) {
        store = KeaserStore(database: database, file: nil)
    }

    var database: Database { store.database }

    /// Pulls, pushes, and repeats while there is anything left to do, as
    /// the sync engine does over a few rounds. A device that still has
    /// something to send after that would sync forever: an issue.
    func sync(_ cloud: TestCloud, now: Date = .now, sourceLocation: SourceLocation = #_sourceLocation) {
        for _ in 0 ..< 6 {
            pull(cloud, now: now)
            let upload = upload(now: now)
            if upload.isEmpty { return }
            push(upload, to: cloud, now: now)
        }
        Issue.record("Still sending after six rounds: \(upload(now: now))", sourceLocation: sourceLocation)
    }

    /// A full fetch; the first one completes the initial sync.
    func pull(_ cloud: TestCloud, now: Date = .now) {
        let changes = cloud.changes(since: token, for: id)
        for record in changes.saved { state.receive(record) }
        for (name, type) in changes.deleted { state.receiveDeletion(of: name, type: type) }
        merge(now: now)
        token = changes.token
        state.hasCompletedInitialSync = true
    }

    /// Only some of what changed: the first `count` saved records, as one
    /// batch of a fetch that is still going.
    func pullPartially(_ cloud: TestCloud, names: Set<String>, now: Date = .now) {
        let changes = cloud.changes(since: token, for: id)
        for record in changes.saved where names.contains(record.name) { state.receive(record) }
        merge(now: now)
    }

    func merge(now: Date = .now) {
        let result = SyncMerge.apply(to: store.database, state: state, now: now)
        let outcome = store.applyCloudChanges(result.database, ifRevision: store.revision)
        precondition(outcome == .saved)
        state = result.state
        lastRemovedAssets = result.removedAssets
    }

    private(set) var lastRemovedAssets: [SyncAsset] = []

    func upload(now: Date = .now) -> SyncUpload {
        SyncPlan.upload(for: store.database, state: &state, now: now)
    }

    func push(_ upload: SyncUpload, to cloud: TestCloud, now: Date = .now) {
        for name in upload.saves {
            guard let record = SyncPlan.outgoingRecord(named: name, in: store.database, state: state),
                  SyncPlan.needsSending(record, state: state)
            else { continue }
            switch cloud.save(record, systemFields: state.known[name]?.systemFields, by: id) {
            case .saved(let saved):
                state.confirmSaved(saved)
            case .conflict(let server):
                state.receive(server)
                merge(now: now)
            case .unknownItem:
                state.receiveDeletion(of: name, type: record.type)
                merge(now: now)
            }
        }
        for name in upload.deletes {
            cloud.delete(name, by: id)
            state.confirmDeleted(name)
        }
    }

    // MARK: Reading

    func account(_ name: String) -> Account? {
        database.accounts.first { $0.name == name }
    }

    func expense(_ title: String) -> Expense? {
        database.accounts.flatMap(\.expenses).first { $0.title == title }
    }
}

/// A moment after `date`, for edits that must be later than another.
func later(_ date: Date = .now, by seconds: TimeInterval = 1) -> Date {
    date.addingTimeInterval(seconds)
}
