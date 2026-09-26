import KeaserKit
import SwiftUI

// STUB (owner: notion builder).

/// The "Connect to Notion" flow, presented as a sheet from Add Account.
/// Calls `onFinish` with the new account's ID, or nil if cancelled.
struct NotionConnectView: View {
    var onFinish: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            Text("Connect to Notion")
                .toolbar { Button("Cancel") { onFinish(nil) } }
        }
    }
}
