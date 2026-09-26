import Foundation

/// Everything that can go wrong talking to Notion, phrased for the person
/// looking at the screen.
public enum NotionError: Error, Equatable, Sendable, LocalizedError {
    /// 401: the token is wrong, revoked or expired.
    case invalidToken
    /// 403 or 404: the token works but cannot see this page or database.
    case notShared
    /// 429 after every retry.
    case rateLimited
    /// No connection, timeout, TLS failure.
    case network(String)
    /// 400: Notion refused the request body (for example a property that
    /// changed type).
    case rejected(String)
    /// 409: another edit landed at the same moment.
    case conflict
    /// 5xx after every retry.
    case unavailable(status: Int)
    /// A 2xx response Keaser could not read.
    case unreadableResponse
    /// The Keychain has no token for this account.
    case missingToken
    /// The database has no data source Keaser can write to.
    case noDataSource
    /// The database has no title property (Notion always has one, so this
    /// only happens if the schema could not be read).
    case noTitleProperty

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            "Notion didn't accept this token. Copy it again from your connection's Configuration tab."
        case .notShared:
            "Keaser can't see this database. In Notion, open it, tap ••• then Connections, and add your connection."
        case .rateLimited:
            "Notion is busy with too many requests. Try again in a minute."
        case .network:
            "Couldn't reach Notion. Check your internet connection and try again."
        case .rejected(let message):
            "Notion rejected the change: \(message)"
        case .conflict:
            "Notion was saving another change at the same time. Try again."
        case .unavailable(let status):
            "Notion is having trouble right now (error \(status)). Try again later."
        case .unreadableResponse:
            "Notion sent a response Keaser couldn't read."
        case .missingToken:
            "This account's Notion token is missing. Disconnect Notion and connect again."
        case .noDataSource:
            "This Notion database has no table Keaser can use."
        case .noTitleProperty:
            "This Notion database has no title property."
        }
    }

    /// Worth retrying later without the user changing anything.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .network, .conflict, .unavailable: true
        default: false
        }
    }
}

/// The JSON body of a Notion error response.
struct NotionErrorBody: Decodable {
    var status: Int?
    var code: String?
    var message: String?
}
