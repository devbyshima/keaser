import Foundation

/// Where iCloud sync stands, for the quiet line under the account card in
/// Settings. Only shown while sync is on.
public enum CloudSyncStatus: Hashable, Sendable {
    case syncing
    case synced(Date)
    case waitingForNetwork
    /// No iCloud account, or iCloud switched off for Keaser.
    case iCloudOff
    /// Parental controls or device management keep iCloud off.
    case restricted
    /// Another Apple Account is signed in than the one this device's data
    /// syncs with. Sync stops rather than mix two people's data.
    case otherAccount
    case storageFull
    case unavailable
    /// Anything else. Sync tries again on its own.
    case failed

    public func text(now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        switch self {
        case .syncing: "Syncing with iCloud"
        case .synced(let date): "Synced with iCloud \(Self.ago(date, now: now, locale: locale, timeZone: timeZone))"
        case .waitingForNetwork: "Waiting for network"
        case .iCloudOff: "iCloud is off in Settings"
        case .restricted: "iCloud is restricted on this iPhone"
        case .otherAccount: "Paused: a different iCloud account is signed in"
        case .storageFull: "iCloud storage is full"
        case .unavailable: "iCloud is temporarily unavailable"
        case .failed: "Couldn't sync with iCloud. Keaser will try again."
        }
    }

    /// An SF Symbol for the line.
    public var symbol: String {
        switch self {
        case .syncing: "arrow.clockwise.icloud"
        case .synced: "checkmark.icloud"
        case .waitingForNetwork, .iCloudOff, .restricted, .unavailable: "icloud.slash"
        case .otherAccount, .storageFull, .failed: "exclamationmark.icloud"
        }
    }

    /// "just now", "2 min ago", "3 hr ago", then "on Sep 26".
    static func ago(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600)) hr ago"
        default:
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
            style.timeZone = timeZone
            return "on \(date.formatted(style))"
        }
    }

    /// The states `-KeaserCloudStatus <name>` shows in Settings for
    /// screenshots (DEBUG): `synced` (two minutes ago), `syncing`,
    /// `offline`, `off`, `restricted`, `otherAccount`, `full`,
    /// `unavailable`, `failed`.
    public static func preview(named name: String, now: Date = .now) -> CloudSyncStatus? {
        switch name {
        case "synced": .synced(now.addingTimeInterval(-120))
        case "syncing": .syncing
        case "offline": .waitingForNetwork
        case "off": .iCloudOff
        case "restricted": .restricted
        case "otherAccount": .otherAccount
        case "full": .storageFull
        case "unavailable": .unavailable
        case "failed": .failed
        default: nil
        }
    }
}
