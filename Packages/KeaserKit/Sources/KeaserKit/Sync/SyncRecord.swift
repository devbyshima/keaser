import Foundation

/// A record's type in CloudKit (`CKRecord.recordType`). An open set: a
/// type this build does not know, written by a later version, is kept
/// aside rather than rejected (see `SyncState.parked`).
public struct SyncRecordType: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// One account's own details: name and creation date. What it holds
    /// are records of their own.
    public static let account = SyncRecordType("Account")
    public static let category = SyncRecordType("Category")
    public static let paymentMethod = SyncRecordType("PaymentMethod")
    public static let expense = SyncRecordType("Expense")
    /// The settings shared between devices (`SyncedSettings`).
    public static let settings = SyncRecordType("Settings")
    /// The order of the accounts, or of one account's categories, payment
    /// methods or income categories.
    public static let order = SyncRecordType("Order")
    public static let incomeCategory = SyncRecordType("IncomeCategory")
    public static let income = SyncRecordType("Income")
    public static let transfer = SyncRecordType("Transfer")
    public static let balanceAdjustment = SyncRecordType("BalanceAdjustment")
    /// One account's split rule, named by the account's ID.
    public static let splitRule = SyncRecordType("SplitRule")
}

/// Record names (`CKRecord.ID.recordName`): the type, then the ID of what
/// the record stands for, so names never collide across types and a
/// deletion, which carries only the name, still says what it deletes.
public enum SyncRecordName {
    public static func make(_ type: SyncRecordType, _ id: UUID) -> String {
        "\(type.rawValue).\(id.uuidString)"
    }

    /// The one settings record.
    public static let settings = "Settings"
    public static let accountsOrder = "Order.Accounts"

    public static func categoriesOrder(_ accountID: UUID) -> String {
        "Order.Categories.\(accountID.uuidString)"
    }

    public static func paymentMethodsOrder(_ accountID: UUID) -> String {
        "Order.PaymentMethods.\(accountID.uuidString)"
    }

    public static func incomeCategoriesOrder(_ accountID: UUID) -> String {
        "Order.IncomeCategories.\(accountID.uuidString)"
    }

    /// The UUID a name ends with, if any.
    public static func id(in name: String) -> UUID? {
        guard name.count >= 36 else { return nil }
        return UUID(uuidString: String(name.suffix(36)))
    }
}

/// A file a record carries beside its payload (a `CKAsset` field), named
/// by the record's own content, such as an expense's receipt photo.
public struct SyncAsset: Hashable, Codable, Sendable {
    /// The CKRecord field that holds the file.
    public var field: String
    /// The file's name in its folder on the device.
    public var fileName: String

    public init(field: String, fileName: String) {
        self.field = field
        self.fileName = fileName
    }
}

/// One record as Keaser writes it to iCloud: a name, a type and a payload.
///
/// The payload is the JSON of an envelope:
///
///     {"body": {...}, "modifiedAt": 780000000.5, "parent": "UUID", "readerVersion": 1}
///
/// `body` is the model's own JSON (an `Expense`, an `ExpenseCategory`...),
/// so a field added to a model later travels without a schema change.
/// `modifiedAt` is the model's last-edit time, which decides between two
/// devices' edits. `parent` is the account the record belongs to.
/// `readerVersion` is the lowest `SyncSchema.readerVersion` that can apply
/// it.
public struct SyncRecord: Hashable, Sendable {
    public var name: String
    public var type: SyncRecordType
    public var modifiedAt: Date
    public var parent: UUID?
    public var readerVersion: Int
    public var body: [String: JSONValue]

    public init(
        name: String,
        type: SyncRecordType,
        modifiedAt: Date,
        parent: UUID? = nil,
        readerVersion: Int = SyncSchema.readerVersion,
        body: [String: JSONValue]
    ) {
        self.name = name
        self.type = type
        self.modifiedAt = modifiedAt
        self.parent = parent
        self.readerVersion = readerVersion
        self.body = body
    }

    /// Reads a record from its CKRecord name, type and payload. Throws for a
    /// payload that is not an envelope at all.
    public init(name: String, type: SyncRecordType, payload: Data) throws {
        let envelope = try SyncCoding.decoder().decode(Envelope.self, from: payload)
        self.init(
            name: name,
            type: type,
            modifiedAt: envelope.modifiedAt,
            parent: envelope.parent,
            readerVersion: envelope.readerVersion,
            body: envelope.body
        )
    }

    /// The payload, byte for byte the same for the same content.
    public var payload: Data {
        let envelope = Envelope(body: body, modifiedAt: modifiedAt, parent: parent, readerVersion: readerVersion)
        return (try? SyncCoding.encoder().encode(envelope)) ?? Data()
    }

    /// Stands for the whole payload: two records with the same fingerprint
    /// have the same content.
    public var fingerprint: UInt64 {
        SyncFingerprint.of(payload)
    }

    /// Whether this record wins over `other`, a different version of the
    /// same record: the later edit wins, and two edits made at the same
    /// instant are decided by their payloads, so every device decides the
    /// same way.
    public func wins(over other: SyncRecord) -> Bool {
        if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt }
        return other.payload.lexicographicallyPrecedes(payload)
    }

    private struct Envelope: Codable {
        var body: [String: JSONValue]
        var modifiedAt: Date
        var parent: UUID?
        var readerVersion: Int

        init(body: [String: JSONValue], modifiedAt: Date, parent: UUID?, readerVersion: Int) {
            self.body = body
            self.modifiedAt = modifiedAt
            self.parent = parent
            self.readerVersion = readerVersion
        }

        // Tolerant, like the models: whatever a later version adds or
        // leaves out, an envelope still reads.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            body = try c.decodeIfPresent([String: JSONValue].self, forKey: .body) ?? [:]
            modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
            parent = try c.decodeIfPresent(UUID.self, forKey: .parent)
            readerVersion = try c.decodeIfPresent(Int.self, forKey: .readerVersion) ?? 1
        }
    }
}

/// A record as it came from iCloud, before it is read: the raw payload and
/// CloudKit's own bookkeeping for it (`CKRecord.encodeSystemFields`, opaque
/// here), kept so the next save of the record carries the right change tag.
public struct FetchedRecord: Hashable, Codable, Sendable {
    public var name: String
    public var type: SyncRecordType
    public var payload: Data
    public var systemFields: Data?

    public init(name: String, type: SyncRecordType, payload: Data, systemFields: Data? = nil) {
        self.name = name
        self.type = type
        self.payload = payload
        self.systemFields = systemFields
    }

    public init(_ record: SyncRecord, systemFields: Data? = nil) {
        self.init(name: record.name, type: record.type, payload: record.payload, systemFields: systemFields)
    }

    /// The record, or nil for a payload that cannot be read at all.
    public var record: SyncRecord? {
        try? SyncRecord(name: name, type: type, payload: payload)
    }
}

/// FNV-1a over bytes: the same value in every launch and on every device,
/// unlike `Hasher`, so fingerprints can be kept on disk.
enum SyncFingerprint {
    static func of(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        // The length too, so two payloads differing only in trailing bytes
        // that happen to cancel out still differ.
        hash ^= UInt64(data.count)
        return hash &* 0x0000_0100_0000_01B3
    }
}
