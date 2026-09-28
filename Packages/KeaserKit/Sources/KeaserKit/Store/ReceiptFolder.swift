import Foundation
import os

/// Where receipt photos are kept: one JPEG per `ReceiptPhoto`, in a Receipts
/// folder beside the database (in the app group container, falling back
/// like `DatabaseFile`). Like the database it is part of the iPhone's
/// backup. The app writes the files; nothing else reads them.
///
/// Deleting an expense leaves its photo in place, so undo (Delete Expense
/// from Siri or Shortcuts) can bring the expense back whole. At launch the
/// app removes the photos no expense refers to any more, once they are older
/// than `gracePeriod` (`orphans(among:keeping:now:gracePeriod:)`). Undo
/// lives only as long as the process that deleted, and a launch starts a new
/// one, so a photo is never removed from under an undo; the grace period
/// also covers a photo written just before its expense reached the disk.
public struct ReceiptFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The Receipts folder next to `DatabaseFile.shared`.
    public static var shared: ReceiptFolder {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: DatabaseFile.appGroupID)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReceiptFolder(url: base.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "Receipts", directoryHint: .isDirectory))
    }

    /// How long a photo no expense refers to is kept before it is removed.
    public static let gracePeriod: TimeInterval = 24 * 60 * 60

    private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "ReceiptFolder")

    public func fileURL(for photo: ReceiptPhoto) -> URL {
        url.appending(path: photo.fileName)
    }

    /// Writes a new photo and returns the reference to keep with the
    /// expense. The file is only readable while the iPhone is unlocked.
    public func add(_ jpeg: Data) throws -> ReceiptPhoto {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let photo = ReceiptPhoto()
        try jpeg.write(to: fileURL(for: photo), options: [.atomic, .completeFileProtection])
        return photo
    }

    /// The photo's JPEG, or nil when its file is missing or locked.
    public func data(for photo: ReceiptPhoto) -> Data? {
        try? Data(contentsOf: fileURL(for: photo))
    }

    // MARK: Clean-up

    /// A file in the folder and when it was last written.
    public struct File: Hashable, Sendable {
        public let name: String
        public let modified: Date

        public init(name: String, modified: Date) {
            self.name = name
            self.modified = modified
        }
    }

    /// The names of the photos to remove: named by Keaser, referred to by
    /// no expense, and written at least `gracePeriod` before `now`. Any
    /// other file is left alone.
    public static func orphans(
        among files: [File],
        keeping inUse: Set<ReceiptPhoto>,
        now: Date,
        gracePeriod: TimeInterval = gracePeriod
    ) -> [String] {
        files.filter { file in
            guard let photo = ReceiptPhoto(fileName: file.name), !inUse.contains(photo) else { return false }
            return now.timeIntervalSince(file.modified) >= gracePeriod
        }
        .map(\.name)
        .sorted()
    }

    /// Every file in the folder; none when it does not exist yet.
    public func files() -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return File(name: file.lastPathComponent, modified: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Removes the orphaned photos (see `orphans(among:keeping:now:gracePeriod:)`)
    /// and returns their names.
    @discardableResult
    public func removeOrphans(keeping inUse: Set<ReceiptPhoto>, now: Date = .now, gracePeriod: TimeInterval = gracePeriod) -> [String] {
        let names = Self.orphans(among: files(), keeping: inUse, now: now, gracePeriod: gracePeriod)
        return names.filter { name in
            do {
                try FileManager.default.removeItem(at: url.appending(path: name))
                return true
            } catch {
                Self.log.error("Could not remove an orphaned receipt: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }
}

extension KeaserStore {
    /// The receipt photos expenses refer to, for the clean-up at launch; nil
    /// when that cannot be known and nothing may be removed: the database
    /// could not be read (before the first unlock), or it has no accounts,
    /// as after a fresh install or when an unreadable file was moved aside.
    public var receiptPhotosInUse: Set<ReceiptPhoto>? {
        guard loadError == nil, !accounts.isEmpty else { return nil }
        return database.receiptPhotos
    }
}
