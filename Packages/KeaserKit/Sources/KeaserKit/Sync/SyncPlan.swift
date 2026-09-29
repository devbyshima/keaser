import Foundation

/// What this device has to send to iCloud, by record name: saves in rank
/// order (an account before what it holds), then deletions.
public struct SyncUpload: Equatable, Sendable {
    public var saves: [String]
    public var deletes: [String]

    public init(saves: [String] = [], deletes: [String] = []) {
        self.saves = saves
        self.deletes = deletes
    }

    public var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
}

/// The local half of sync: comparing the database with what iCloud holds
/// (`SyncState.known`) to find what changed here, the way `SpotlightPlan`
/// compares it with the Spotlight index.
public enum SyncPlan {
    /// What to send. A record is sent when it is new here or changed since
    /// iCloud last had it (`SyncKind.isPending`); a record iCloud has that
    /// the database no longer holds becomes a tombstone, and every
    /// tombstone is sent as a deletion until iCloud confirms it.
    ///
    /// Sends nothing before the first full fetch (`hasCompletedInitialSync`)
    /// or while changes from iCloud wait to be merged: both would send what
    /// the merge is about to change. Never sends over a record iCloud holds
    /// in a form this build cannot read (`SyncState.parked`).
    public static func upload(for database: Database, state: inout SyncState, now: Date) -> SyncUpload {
        guard state.hasCompletedInitialSync, state.inbox.isEmpty else { return SyncUpload() }
        var saves: [String] = []
        var present = Set<String>()
        for kind in SyncKinds.all {
            for record in kind.records(in: database) {
                present.insert(record.name)
                guard state.parked[record.name] == nil else { continue }
                // Back after a deletion that has not gone out yet (undo).
                state.tombstones[record.name] = nil
                let known = state.known[record.name]
                if let known, !kind.isPending(outgoing(record, extras: known.extras), known: known) { continue }
                saves.append(record.name)
            }
        }
        for (name, known) in state.known where !present.contains(name) && state.parked[name] == nil {
            guard SyncKinds.kind(for: known.type) != nil, state.tombstones[name] == nil else { continue }
            state.tombstones[name] = Tombstone(type: known.type, deletedAt: now)
        }
        return SyncUpload(saves: saves, deletes: state.tombstones.keys.sorted())
    }

    /// The record named `name` as this device sends it now, or nil when the
    /// database no longer holds it.
    public static func outgoingRecord(named name: String, in database: Database, state: SyncState) -> SyncRecord? {
        guard let kind = SyncKinds.kind(forName: name), let record = kind.record(named: name, in: database) else { return nil }
        return outgoing(record, extras: state.known[name]?.extras)
    }

    /// The records of these names as this device sends them now, found in
    /// one pass over the database (a batch of hundreds of expenses would
    /// otherwise search it once each). Names it no longer holds are missing.
    public static func outgoingRecords(named names: [String], in database: Database, state: SyncState) -> [String: SyncRecord] {
        var byKind: [SyncRecordType: Set<String>] = [:]
        for name in names {
            guard let kind = SyncKinds.kind(forName: name) else { continue }
            byKind[kind.type, default: []].insert(name)
        }
        var records: [String: SyncRecord] = [:]
        for (type, names) in byKind {
            guard let kind = SyncKinds.kind(for: type) else { continue }
            for record in kind.records(named: names, in: database) where names.contains(record.name) {
                records[record.name] = outgoing(record, extras: state.known[record.name]?.extras)
            }
        }
        return records
    }

    /// Whether the record named `name` still has to go: false when iCloud
    /// already holds it as it is here, so a queued save can be dropped.
    public static func needsSending(_ record: SyncRecord, state: SyncState) -> Bool {
        guard let kind = SyncKinds.kind(for: record.type), let known = state.known[record.name] else { return true }
        return kind.isPending(record, known: known)
    }

    /// `record` with the fields a later version of Keaser added, which this
    /// build does not know, put back as iCloud last had them.
    static func outgoing(_ record: SyncRecord, extras: Data?) -> SyncRecord {
        guard let extras, let fields = try? SyncCoding.decoder().decode([String: JSONValue].self, from: extras), !fields.isEmpty else { return record }
        var record = record
        for (key, value) in fields where record.body[key] == nil {
            record.body[key] = value
        }
        return record
    }

    /// The fields of `record` its canonical form lacks: the ones this build
    /// does not know. Nil when there are none.
    static func extras(of record: SyncRecord, canonical: SyncRecord) -> Data? {
        let unknown = record.body.filter { canonical.body[$0.key] == nil }
        guard !unknown.isEmpty else { return nil }
        return try? SyncCoding.encoder().encode(unknown)
    }
}
