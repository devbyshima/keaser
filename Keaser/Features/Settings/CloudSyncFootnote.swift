import KeaserKit
import SwiftUI

/// Where iCloud sync stands, as the small print under the account card
/// ("Synced with iCloud 2 min ago", "Waiting for network"): the same
/// `SettingsFootnote` other Settings cards carry. Only shown while sync is
/// on (`CloudSync.displayedStatus`).
struct CloudSyncFootnote: View {
    let status: CloudSyncStatus

    var body: some View {
        // "2 min ago" stays true while Settings is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SettingsFootnote(status.text(now: context.date))
        }
    }
}
