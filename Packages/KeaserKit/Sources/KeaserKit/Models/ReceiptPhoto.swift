import Foundation

/// The photo of a receipt kept with an expense. Only this reference is in
/// the database; the image is a JPEG in the Receipts folder
/// (`ReceiptFolder`), named from `id`. The ID is stable for the photo's
/// whole life, so anything that copies the files (a sync, a backup) can key
/// them by it.
///
/// A photo is written once and never changed: adding another one gives a
/// new ID and a new file, so an expense brought back by undo still finds the
/// photos it had.
public struct ReceiptPhoto: Codable, Hashable, Sendable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }

    static let fileNamePrefix = "receipt-"
    static let fileNameExtension = ".jpg"

    /// "receipt-<UUID>.jpg", the file in the Receipts folder.
    public var fileName: String {
        Self.fileNamePrefix + id.uuidString + Self.fileNameExtension
    }

    /// The photo a file in the Receipts folder holds, or nil for a file
    /// Keaser did not name (anything else is never touched).
    public init?(fileName: String) {
        guard fileName.hasPrefix(Self.fileNamePrefix), fileName.hasSuffix(Self.fileNameExtension) else { return nil }
        let middle = fileName.dropFirst(Self.fileNamePrefix.count).dropLast(Self.fileNameExtension.count)
        guard let id = UUID(uuidString: String(middle)) else { return nil }
        self.id = id
    }
}

/// An expense's receipts: how many it may have, and which files to let go
/// when some are taken off it.
public enum ReceiptList {
    /// The most receipts one expense keeps. The editor's add controls go
    /// away once it has this many.
    public static let maximum = 10

    /// How many more receipts fit beside `count`.
    public static func room(after count: Int) -> Int {
        max(0, maximum - count)
    }

    /// `list` with as many of `new` as fit, in order, after the ones it has.
    public static func adding<Item>(_ new: [Item], to list: [Item]) -> [Item] {
        list + new.prefix(room(after: list.count))
    }

    /// The photos of `old` no expense refers to any more (`inUse`), in
    /// order: the files to delete once an edit that took them off is saved.
    public static func released(from old: [ReceiptPhoto], inUse: Set<ReceiptPhoto>) -> [ReceiptPhoto] {
        old.filter { !inUse.contains($0) }
    }
}

/// iCloud sync keeps each photo as a record of its own, keyed by the
/// photo's ID, and the expense's list of IDs in its order
/// (`ReceiptSyncKind`).
extension Expense: ReceiptHolding {
    public var receiptPhotoIDs: [UUID] { receipts.map(\.id) }
}

extension Database {
    /// Every receipt photo an expense refers to, in every account.
    public var receiptPhotos: Set<ReceiptPhoto> {
        Set(accounts.flatMap(\.expenses).flatMap(\.receipts))
    }
}
