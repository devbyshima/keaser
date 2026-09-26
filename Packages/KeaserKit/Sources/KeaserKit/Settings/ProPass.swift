import Foundation
import Security
import Synchronization

/// The 7-day Pro pass start, kept outside the database as well. The database
/// is deleted with the app; the Keychain is not, so reinstalling cannot
/// start a second pass.
public enum ProPass {
    /// The pass start to use: the earlier of the two records, so neither a
    /// reinstall (empty database) nor a stale Keychain entry can move it
    /// later. Nil while neither has one.
    public static func startDate(database: Date?, remembered: Date?) -> Date? {
        [database, remembered].compactMap { $0 }.min()
    }
}

/// Where the first pass start is remembered across installs.
public protocol ProPassRecord: Sendable {
    var firstStart: Date? { get }
    func remember(_ start: Date)
}

/// One generic password in the Keychain. Readable after the first unlock, so
/// a launch while the phone is locked in a pocket still finds it.
public struct KeychainProPassRecord: ProPassRecord {
    public static let service = "com.fulltimestudio.keaser.pass"
    private static let account = "firstStart"

    public init() {}

    public var firstStart: Date? {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let seconds = TimeInterval(text)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public func remember(_ start: Date) {
        let update: [String: Any] = [
            kSecValueData as String: Data(String(start.timeIntervalSince1970).utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(Self.baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = Self.baseQuery
            add.merge(update) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Memory only: tests and seeded debug launches, which must not leave a pass
/// behind in the simulator's Keychain.
public final class InMemoryProPassRecord: ProPassRecord {
    private let start: Mutex<Date?>

    public init(_ start: Date? = nil) {
        self.start = Mutex(start)
    }

    public var firstStart: Date? { start.withLock { $0 } }

    public func remember(_ start: Date) {
        self.start.withLock { $0 = start }
    }
}
