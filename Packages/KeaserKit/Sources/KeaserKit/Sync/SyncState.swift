import Foundation

/// What iCloud holds of one record, as far as this device knows: enough to
/// tell whether the local copy changed since (`fingerprint`), which edit is
/// later (`modifiedAt`), and to save it again without a conflict
/// (`systemFields`).
public struct KnownRecord: Codable, Hashable, Sendable {
    public var type: SyncRecordType
    /// Of the record as this build writes it (`SyncKind.canonical`), so it
    /// compares directly with the local copy.
    public var fingerprint: UInt64
    public var modifiedAt: Date
    public var parent: UUID?
    /// Fields of the record this build does not know (written by a later
    /// version), as JSON, sent back untouched with every local edit.
    public var extras: Data?
    /// For order records: the IDs iCloud lists.
    public var orderIDs: [UUID]?
    /// `CKRecord.encodeSystemFields` of the last copy seen, so a save
    /// carries the right change tag. Opaque here.
    public var systemFields: Data?

    public init(type: SyncRecordType, fingerprint: UInt64, modifiedAt: Date, parent: UUID? = nil, extras: Data? = nil, orderIDs: [UUID]? = nil, systemFields: Data? = nil) {
        self.type = type
        self.fingerprint = fingerprint
        self.modifiedAt = modifiedAt
        self.parent = parent
        self.extras = extras
        self.orderIDs = orderIDs
        self.systemFields = systemFields
    }

    // Stored as its bit pattern: property lists hold signed integers.
    private enum CodingKeys: String, CodingKey {
        case type, fingerprint, modifiedAt, parent, extras, orderIDs, systemFields
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(SyncRecordType.self, forKey: .type)
        fingerprint = UInt64(bitPattern: try c.decode(Int64.self, forKey: .fingerprint))
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        parent = try c.decodeIfPresent(UUID.self, forKey: .parent)
        extras = try c.decodeIfPresent(Data.self, forKey: .extras)
        orderIDs = try c.decodeIfPresent([UUID].self, forKey: .orderIDs)
        systemFields = try c.decodeIfPresent(Data.self, forKey: .systemFields)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(Int64(bitPattern: fingerprint), forKey: .fingerprint)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(parent, forKey: .parent)
        try c.encodeIfPresent(extras, forKey: .extras)
        try c.encodeIfPresent(orderIDs, forKey: .orderIDs)
        try c.encodeIfPresent(systemFields, forKey: .systemFields)
    }

    /// The unknown fields, decoded.
    var extraFields: [String: JSONValue] {
        guard let extras, let fields = try? SyncCoding.decoder().decode([String: JSONValue].self, from: extras) else { return [:] }
        return fields
    }
}

/// A local deletion iCloud has not confirmed yet. Kept, with the moment it
/// was noticed, until the sync engine reports the record deleted, so an
/// edit made elsewhere later than the deletion can still bring it back.
public struct Tombstone: Codable, Hashable, Sendable {
    public var type: SyncRecordType
    public var deletedAt: Date

    public init(type: SyncRecordType, deletedAt: Date) {
        self.type = type
        self.deletedAt = deletedAt
    }
}

/// A change iCloud sent that is not applied yet.
public enum InboxItem: Codable, Hashable, Sendable {
    case saved(FetchedRecord)
    case deleted(SyncRecordType)
}

/// Everything iCloud sync remembers between launches, besides the database
/// itself. Kept in one file, written whole, so it never disagrees with
/// itself.
public struct SyncState: Codable, Hashable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    /// The iCloud user (`CKRecord.ID.recordName` of the user record) this
    /// device's data syncs with. Set by the first sync; a different Apple
    /// Account later stops sync instead of mixing two people's data.
    public var userRecordName: String?
    /// Whether the zone was created in iCloud.
    public var zoneSaved: Bool
    /// Whether this device has fetched everything iCloud held once. Until
    /// then nothing local is sent, so a device that already has data merges
    /// with iCloud first (accounts of the same name become one) instead of
    /// uploading duplicates.
    public var hasCompletedInitialSync: Bool
    /// The last time a fetch or send finished without a problem.
    public var lastSyncedAt: Date?
    /// `CKSyncEngine.State.Serialization`, encoded by the app. Opaque here.
    public var engineState: Data?
    /// What iCloud holds, by record name.
    public var known: [String: KnownRecord]
    /// Local deletions not confirmed yet, by record name.
    public var tombstones: [String: Tombstone]
    /// Records from iCloud this build cannot apply yet: a type it does not
    /// know, a `readerVersion` above its own, or an account that has not
    /// arrived. Kept untouched (never overwritten or deleted from here) and
    /// tried again with every merge, so an update or a later batch picks
    /// them up.
    public var parked: [String: FetchedRecord]
    /// Changes iCloud sent that are not applied yet, by record name. Saved
    /// before they are applied, so a change survives the app being stopped
    /// between hearing about it and writing it.
    public var inbox: [String: InboxItem]

    public init() {
        format = Self.currentFormat
        userRecordName = nil
        zoneSaved = false
        hasCompletedInitialSync = false
        lastSyncedAt = nil
        engineState = nil
        known = [:]
        tombstones = [:]
        parked = [:]
        inbox = [:]
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        userRecordName = try c.decodeIfPresent(String.self, forKey: .userRecordName)
        zoneSaved = try c.decodeIfPresent(Bool.self, forKey: .zoneSaved) ?? false
        hasCompletedInitialSync = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialSync) ?? false
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        engineState = try c.decodeIfPresent(Data.self, forKey: .engineState)
        known = try c.decodeIfPresent([String: KnownRecord].self, forKey: .known) ?? [:]
        tombstones = try c.decodeIfPresent([String: Tombstone].self, forKey: .tombstones) ?? [:]
        parked = try c.decodeIfPresent([String: FetchedRecord].self, forKey: .parked) ?? [:]
        inbox = try c.decodeIfPresent([String: InboxItem].self, forKey: .inbox) ?? [:]
    }

    // MARK: Hearing from iCloud

    /// A record iCloud sent (fetched, or returned with a conflict). The
    /// latest word on a record replaces an earlier one still waiting.
    public mutating func receive(_ record: FetchedRecord) {
        inbox[record.name] = .saved(record)
    }

    /// A deletion iCloud sent, or a save that found the record gone.
    public mutating func receiveDeletion(of name: String, type: SyncRecordType) {
        inbox[name] = .deleted(type)
    }

    /// iCloud confirmed saving `record` as sent: it now holds this version.
    /// What was sent was written by this build, unknown fields included,
    /// exactly as the diff writes it, so its fingerprint is the payload's.
    public mutating func confirmSaved(_ record: FetchedRecord) {
        guard let sent = record.record else { return }
        var entry = KnownRecord(
            type: sent.type, fingerprint: SyncFingerprint.of(record.payload), modifiedAt: sent.modifiedAt,
            parent: sent.parent, extras: known[record.name]?.extras, systemFields: record.systemFields
        )
        if sent.type == .order { entry.orderIDs = OrderSyncKind.ids(in: sent) }
        known[record.name] = entry
    }

    /// iCloud confirmed deleting `name` (or found it already gone).
    public mutating func confirmDeleted(_ name: String) {
        known[name] = nil
        tombstones[name] = nil
    }

    /// The zone is gone from iCloud (deleted from another device, or the
    /// person deleted Keaser's iCloud data, or reset their encrypted data).
    /// Local data stays; everything is uploaded again, merging with
    /// whatever other devices put back first, as on a first sync.
    public mutating func forgetZone() {
        zoneSaved = false
        hasCompletedInitialSync = false
        known = [:]
        tombstones = [:]
        parked = [:]
        inbox = [:]
    }

    // MARK: Storage

    /// A binary property list: compact for the CloudKit system fields it
    /// holds for every record.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// Nil for data that is not a sync state; the caller starts over, as a
    /// first sync (which merges rather than overwrites).
    public static func decoded(from data: Data) -> SyncState? {
        try? PropertyListDecoder().decode(SyncState.self, from: data)
    }
}
