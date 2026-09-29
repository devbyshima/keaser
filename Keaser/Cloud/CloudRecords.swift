import CloudKit
import KeaserKit
import os

/// Turns KeaserKit's sync records into CloudKit records and back.
///
/// A CKRecord of Keaser's zone holds one encrypted field, `payload` (the
/// record's JSON envelope; see `SyncRecord`), plus a CKAsset field for each
/// file the record carries (a receipt photo's `file`). Encrypted fields are
/// encrypted with keys in the person's iCloud Keychain: Apple stores them,
/// and the makers of Keaser cannot read them.
enum CloudRecords {
    private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "CloudSync")

    /// The CKRecord to send for `record`: built on the copy iCloud last had
    /// (its system fields carry the change tag, so the save is not taken for
    /// a conflict), or new. Nil when a file the record carries is missing on
    /// this device, so a record is never sent without its file.
    static func ckRecord(for record: SyncRecord, zoneID: CKRecordZone.ID, known: KnownRecord?, attachments: any CloudAttachmentFiles) -> CKRecord? {
        let id = CKRecord.ID(recordName: record.name, zoneID: zoneID)
        let ckRecord: CKRecord
        if let fields = known?.systemFields, let previous = Self.record(fromSystemFields: fields),
           previous.recordID == id, previous.recordType == record.type.rawValue {
            ckRecord = previous
        } else {
            ckRecord = CKRecord(recordType: record.type.rawValue, recordID: id)
        }
        ckRecord.encryptedValues[SyncSchema.payloadField] = record.payload
        for asset in SyncKinds.kind(for: record.type)?.assets(named: record.name) ?? [] {
            guard let url = attachments.fileURL(for: asset) else { return nil }
            ckRecord[asset.field] = CKAsset(fileURL: url)
        }
        return ckRecord
    }

    /// A record from iCloud, raw. With `attachments`, the files it carries
    /// are stored first: CloudKit keeps a downloaded file only for a while.
    static func fetched(from record: CKRecord, attachments: (any CloudAttachmentFiles)?) -> FetchedRecord {
        let name = record.recordID.recordName
        if let attachments {
            for asset in SyncKinds.kind(forName: name)?.assets(named: name) ?? [] {
                guard let file = record[asset.field] as? CKAsset, let url = file.fileURL else { continue }
                do {
                    try attachments.store(url, for: asset)
                } catch {
                    log.error("A file from iCloud was not kept: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return FetchedRecord(
            name: name,
            type: SyncRecordType(record.recordType),
            payload: record.encryptedValues[SyncSchema.payloadField] as? Data ?? Data(),
            systemFields: systemFields(of: record)
        )
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// The status a CloudKit error stands for.
    static func status(for error: any Error) -> CloudSyncStatus {
        guard let error = error as? CKError else { return .failed }
        switch error.code {
        case .networkUnavailable, .networkFailure: return .waitingForNetwork
        case .notAuthenticated: return .iCloudOff
        case .quotaExceeded: return .storageFull
        case .managedAccountRestricted: return .restricted
        case .accountTemporarilyUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .unavailable
        default: return .failed
        }
    }
}

/// Where the files records carry are kept on this device.
///
/// Receipt photos: once expenses hold them (`ReceiptHolding`), each photo
/// syncs as a `ReceiptSyncKind` record whose CKAsset field `file` is the
/// JPEG. Sending, `fileURL(for:)` names the file to upload; receiving,
/// `store(_:for:)` copies CloudKit's download into place before the expense
/// that shows it is merged; when iCloud deletes the photo's record and no
/// expense here still shows it, `remove(_:)` deletes the file.
protocol CloudAttachmentFiles: Sendable {
    /// The file to upload, or nil when this device does not have it.
    func fileURL(for asset: SyncAsset) -> URL?
    /// Keeps a downloaded file under the asset's name.
    func store(_ downloaded: URL, for asset: SyncAsset) throws
    func remove(_ asset: SyncAsset)
}

/// Files kept by name in one folder. `receipts` is the app's
/// `ReceiptFolder` (`AppEnvironment.receipts`), whose photos
/// `ReceiptSyncKind.fileName(for:)` names as `ReceiptPhoto.fileName` does,
/// written with its protection.
struct FolderAttachmentFiles: CloudAttachmentFiles {
    let folder: URL
    var writingOptions: Data.WritingOptions = ReceiptFolder.writingOptions

    static var receipts: FolderAttachmentFiles {
        FolderAttachmentFiles(folder: AppEnvironment.receipts.url, writingOptions: ReceiptFolder.writingOptions)
    }

    func fileURL(for asset: SyncAsset) -> URL? {
        let url = folder.appending(path: asset.fileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// A photo never changes, so one already here is kept. Written with
    /// the folder's protection (`ReceiptFolder.writingOptions`), so it can
    /// be saved while the iPhone is locked (a sync woken by a push) after
    /// the first unlock.
    func store(_ downloaded: URL, for asset: SyncAsset) throws {
        let target = folder.appending(path: asset.fileName)
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try Data(contentsOf: downloaded)
        try data.write(to: target, options: writingOptions)
    }

    func remove(_ asset: SyncAsset) {
        try? FileManager.default.removeItem(at: folder.appending(path: asset.fileName))
    }
}
