import Foundation

/// The photo of a receipt kept with an expense. Only this reference is in
/// the database; the image is a JPEG in the Receipts folder
/// (`ReceiptFolder`), named from `id`.
///
/// A photo is written once and never changed: attaching another one gives a
/// new ID and a new file, so an expense brought back by undo still finds the
/// photo it had.
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

extension Database {
    /// Every receipt photo an expense refers to, in every account.
    public var receiptPhotos: Set<ReceiptPhoto> {
        Set(accounts.flatMap(\.expenses).compactMap(\.receipt))
    }
}
