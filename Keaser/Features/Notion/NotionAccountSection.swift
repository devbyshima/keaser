import KeaserKit
import SwiftUI

/// Notion status and actions for a linked account (sync now, last synced,
/// disconnect). Returns `Section`s: embed it directly inside a `List` in
/// Account Settings, only when `account.notion != nil`.
struct NotionAccountSection: View {
    let accountID: UUID

    @Environment(KeaserStore.self) private var store
    @State private var confirmingDisconnect = false
    private var engine: NotionSyncEngine { .shared }

    var body: some View {
        if let notion = store.account(id: accountID)?.notion {
            let status = engine.status(for: accountID)
            Section {
                databaseRow(notion)
                lastSyncedRow(notion, status: status)
                syncButton(status: status)
                if let error = status.lastError, !status.isSyncing {
                    errorRow(error)
                }
            } header: {
                Text("Notion")
                    .font(.headline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .textCase(nil)
            }
            .listRowBackground(Color.keaserCardRaised)

            Section {
                Button(role: .destructive) {
                    confirmingDisconnect = true
                } label: {
                    Text("Disconnect Notion")
                        .foregroundStyle(Color.keaserDestructive)
                }
                .confirmationDialog(
                    "Disconnect \(notion.databaseTitle)?",
                    isPresented: $confirmingDisconnect,
                    titleVisibility: .visible
                ) {
                    Button("Disconnect Notion", role: .destructive) {
                        engine.disconnect(accountID: accountID)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your expenses stay in Keaser and the Notion database stays as it is. They just stop syncing.")
                }
            } footer: {
                Text("Keaser stops syncing with this database. Nothing is deleted in Keaser or in Notion.")
            }
            .listRowBackground(Color.keaserCardRaised)
        }
    }

    private func databaseRow(_ notion: NotionConnection) -> some View {
        HStack(spacing: Self.iconSpacing) {
            NotionEmojiTile(emoji: notion.iconEmoji, size: Self.iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(notion.databaseTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(notion.workspaceName ?? "Notion")
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let url = notion.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in Notion")
            }
        }
        .frame(minHeight: 44)
    }

    private func lastSyncedRow(_ notion: NotionConnection, status: NotionSyncStatus) -> some View {
        HStack(spacing: Self.iconSpacing) {
            icon("clock.fill")
            Text("Last Synced")
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            // Re-rendered every half minute so "2 min ago" stays true.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.relative(notion.lastSyncedAt, now: context.date))
                    .foregroundStyle(Color.keaserSecondaryText)
                    .contentTransition(.numericText())
            }
        }
        .frame(minHeight: 44)
    }

    private func syncButton(status: NotionSyncStatus) -> some View {
        Button {
            Task { try? await engine.syncNow(accountID: accountID) }
        } label: {
            HStack(spacing: Self.iconSpacing) {
                icon("arrow.triangle.2.circlepath")
                Text(status.isSyncing ? "Syncing…" : "Sync Now")
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if status.isSyncing {
                    ProgressView().tint(.white)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(status.isSyncing)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Self.iconSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.keaserDestructive)
                .frame(width: Self.iconWidth)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
    }

    // With the list's 16pt row inset this puts icons 31pt and text 62pt
    // from the card edge, as in the other Settings rows.
    private static let iconWidth: CGFloat = 30
    private static let iconSpacing: CGFloat = 16

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.iconWidth)
    }

    static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

#if DEBUG
/// `-KeaserSheet notion -KeaserNotionStep section`: the section inside a
/// list, on a demo-linked account, so it can be screenshotted without the
/// Settings sheet.
struct NotionAccountSectionPreviewHost: View {
    var onClose: () -> Void
    @Environment(KeaserStore.self) private var store
    @State private var accountID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            NotionSheetHeader(title: "Account Settings", leading: .back, action: onClose)
            List {
                if let accountID {
                    NotionAccountSection(accountID: accountID)
                }
            }
            .scrollContentBackground(.hidden)
            .listSectionSpacing(28)
        }
        .notionPageBackground()
        .task { await link() }
    }

    private func link() async {
        if let linked = store.accounts.first(where: \.isNotionLinked) {
            accountID = linked.id
            return
        }
        let service = NotionDemo.service
        guard NotionDemo.isEnabled,
              let source = try? await service.searchDataSources().first(where: { $0.title == "Expenses" }),
              let map = NotionPropertyMatcher.autoMap(source)
        else { return }
        let connection = NotionConnection(
            databaseID: source.databaseID ?? source.id,
            databaseTitle: source.displayTitle,
            workspaceName: NotionDemoService.workspaceName,
            properties: map,
            dataSourceID: source.id,
            iconEmoji: source.iconEmoji,
            url: source.url
        )
        let id = try? await NotionSyncEngine.shared.connect(name: source.displayTitle, connection: connection, token: "demo-token").0
        accountID = id
    }
}
#endif
