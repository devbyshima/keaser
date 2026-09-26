import KeaserKit
import SwiftUI

// STUB (owner: notion builder).

/// Notion status and actions for a linked account (sync now, last synced,
/// disconnect). Returns `Section`s: embed it directly inside a `List` in
/// Account Settings, only when `account.notion != nil`.
struct NotionAccountSection: View {
    let accountID: UUID

    var body: some View {
        Section("Notion") { Text("Linked") }
    }
}
