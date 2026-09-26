import KeaserKit
import SwiftUI

/// Notion status and actions for a linked account (sync now, last synced,
/// disconnect). Returns `Section`s drawn with the Settings card style: embed
/// it directly inside Account Settings' `List`, only when
/// `account.notion != nil`.
struct NotionAccountSection: View {
    let accountID: UUID

    @Environment(KeaserStore.self) private var store
    @State private var confirmingDisconnect = false
    private var engine: NotionSyncEngine { .shared }

    var body: some View {
        if let notion = store.account(id: accountID)?.notion {
            let status = engine.status(for: accountID)
            let error = status.isSyncing ? nil : status.lastError
            Section {
                SettingsSectionTitle("Notion")
                databaseRow(notion)
                    .cardRow(.first)
                lastSyncedRow(notion)
                    .cardRow(.middle)
                syncButton(status: status)
                    .cardRow(error == nil ? .last : .middle)
                if let error {
                    errorRow(error)
                        .cardRow(.last)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmingDisconnect = true
                } label: {
                    Text("Disconnect Notion")
                        .font(.body)
                        .foregroundStyle(Color.keaserDestructive)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cardRow(.single, insets: .settingsTextRow)
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
                SettingsFootnote("Keaser stops syncing with this database. Nothing is deleted in Keaser or in Notion.")
            }
        }
    }

    private func databaseRow(_ notion: NotionConnection) -> some View {
        HStack(spacing: 13) {
            HStack(spacing: 13) {
                emojiTile(notion.iconEmoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notion.databaseTitle)
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .lineLimit(2)
                    Text(notion.workspaceName ?? "Notion")
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .lineLimit(2)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let url = notion.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .keaserFont(14, weight: .semibold)
                        .foregroundStyle(Color.keaserSecondaryText)
                        // Drawn small, tapped at a full 44pt.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in Notion")
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .cardSeparatorTrailing()
    }

    /// The database's emoji on the same faint tile as the symbols of the
    /// other rows, or its symbol when it has none.
    @ViewBuilder
    private func emojiTile(_ emoji: String?) -> some View {
        if let emoji, !emoji.isEmpty {
            // Fixed with the 38pt SettingsSymbol tiles in the rows below it.
            Text(emoji)
                .font(.system(size: 21))
                .frame(width: 38, height: 38)
                .background(Color.keaserSheetTile, in: RoundedRectangle(cornerRadius: 38 * 0.3, style: .continuous))
                .accessibilityHidden(true)
        } else {
            SettingsSymbol(symbol: "tablecells")
                .accessibilityHidden(true)
        }
    }

    private func lastSyncedRow(_ notion: NotionConnection) -> some View {
        HStack(spacing: 13) {
            SettingsSymbol(symbol: "clock.fill")
                .accessibilityHidden(true)
            Text("Last Synced")
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            // Re-rendered every half minute so "2 min ago" stays true.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.relative(notion.lastSyncedAt, now: context.date))
                    .font(.body)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .contentTransition(.numericText())
            }
        }
        .frame(minHeight: 68)
        .cardSeparatorTrailing()
        .accessibilityElement(children: .combine)
    }

    private func syncButton(status: NotionSyncStatus) -> some View {
        Button {
            Task { try? await engine.syncNow(accountID: accountID) }
        } label: {
            HStack(spacing: 13) {
                SettingsSymbol(symbol: "arrow.triangle.2.circlepath")
                    .accessibilityHidden(true)
                Text(status.isSyncing ? "Syncing…" : "Sync Now")
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                if status.isSyncing {
                    ProgressView().tint(.white)
                }
            }
            .frame(minHeight: 68)
            .cardSeparatorTrailing()
            .contentShape(Rectangle())
        }
        .disabled(status.isSyncing)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            SettingsSymbol(symbol: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last Sync Failed")
                    .font(.body)
                    .foregroundStyle(Color.keaserDestructive)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .frame(minHeight: 68)
        .cardSeparatorTrailing()
        .accessibilityElement(children: .combine)
    }

    static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

#if DEBUG
/// `-KeaserSheet notion -KeaserNotionStep section`: Account Settings for a
/// demo-linked account, so the section can be screenshotted where it lives
/// without opening the Settings sheet.
struct NotionAccountSectionPreviewHost: View {
    @Environment(KeaserStore.self) private var store
    @State private var accountID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if let accountID {
                    AccountSettingsView(accountID: accountID)
                } else {
                    Color.clear
                }
            }
            .navigationDestination(for: SettingsPage.self) { $0.destination }
        }
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
