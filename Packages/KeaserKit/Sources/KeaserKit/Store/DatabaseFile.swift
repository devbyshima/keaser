import Foundation
import os

/// Where the database JSON lives, and how it is read and written.
///
/// The app writes; the widget extension only reads. Writes are atomic
/// (write-to-temp then rename), so a reader never sees half a file.
public struct DatabaseFile: Sendable {
    public static let appGroupID = "group.com.fulltimestudio.keaser"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The shared file in the app group container, falling back to the app's
    /// own Application Support directory when the group is unavailable.
    public static var shared: DatabaseFile {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DatabaseFile(url: base.appending(path: "Keaser", directoryHint: .isDirectory).appending(path: "database.json"))
    }

    private static let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "DatabaseFile")

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Exact round trip: ISO 8601 would drop sub-second precision, and a
        // reloaded database must compare equal to the one that was saved.
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// Reads the database. A missing file is a fresh install. An unreadable
    /// file is moved aside (never deleted) and a fresh database is returned,
    /// so one bad write cannot brick the app and the data stays recoverable.
    public func load() -> Database {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return Database()
        }
        do {
            return try Self.makeDecoder().decode(Database.self, from: data)
        } catch {
            Self.log.error("Database unreadable, moving aside: \(error.localizedDescription, privacy: .public)")
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appending(path: "database.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return Database()
        }
    }

    public func save(_ database: Database) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(database)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
