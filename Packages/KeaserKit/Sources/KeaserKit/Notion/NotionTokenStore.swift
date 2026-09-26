import Foundation
import Security
import Synchronization

/// Where each linked account's Notion token is kept.
public protocol NotionTokenStore: Sendable {
    func token(for accountID: UUID) -> String?
    func setToken(_ token: String, for accountID: UUID) throws
    func removeToken(for accountID: UUID)
}

/// Generic passwords in the Keychain, one per account ID. Readable after
/// the first unlock, so a sync triggered while the phone is locked in a
/// pocket still works.
public struct KeychainNotionTokenStore: NotionTokenStore {
    public static let service = "com.fulltimestudio.keaser.notion"

    public init() {}

    public func token(for accountID: UUID) -> String? {
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String, for accountID: UUID) throws {
        let data = Data(token.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(baseQuery(accountID) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(accountID)
            add.merge(update) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removeToken(for accountID: UUID) {
        SecItemDelete(baseQuery(accountID) as CFDictionary)
    }

    private func baseQuery(_ accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }

    public struct KeychainError: Error, LocalizedError {
        public var status: OSStatus
        public var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Couldn't save the Notion token to the Keychain (\(detail))."
        }
    }
}

/// Tokens in memory only: tests, previews and the Notion demo mode.
public final class InMemoryNotionTokenStore: NotionTokenStore {
    private let tokens = Mutex<[UUID: String]>([:])

    public init() {}

    public func token(for accountID: UUID) -> String? {
        tokens.withLock { $0[accountID] }
    }

    public func setToken(_ token: String, for accountID: UUID) throws {
        tokens.withLock { $0[accountID] = token }
    }

    public func removeToken(for accountID: UUID) {
        _ = tokens.withLock { $0.removeValue(forKey: accountID) }
    }
}
