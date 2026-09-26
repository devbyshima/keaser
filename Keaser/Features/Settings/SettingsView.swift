import KeaserKit
import SwiftUI

/// The Settings sheet, presented from Home's gear button. Owns its own
/// NavigationStack.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsPage]
    @State private var showsPaywall = false

    init() {
        _path = State(initialValue: SettingsPage.launchPath(store: AppEnvironment.store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsRootList(showsPaywall: $showsPaywall)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HeaderIconButton("xmark", label: "Close") { dismiss() }
                    }
                }
                .navigationDestination(for: SettingsPage.self) { $0.destination }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .keaserSheetChrome()
    }
}

private struct SettingsRootList: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Binding var showsPaywall: Bool

    private static let footerID = "settings-footer"

    var body: some View {
        let preferences = store.preferences
        ScrollViewReader { proxy in
            List {
                Section {
                    ProBanner(
                        subtitle: ProStatusText.subtitle(trialDaysRemaining: pro.trialDaysRemaining, hasPurchased: pro.hasPurchased),
                        showsUpgrade: !pro.hasPurchased
                    ) {
                        showsPaywall = true
                    }
                    .padding(.bottom, 21)
                    .plainListRow()
                }

                if let account = store.selectedAccount {
                    Section {
                        NavigationLink(value: SettingsPage.account(account.id)) {
                            AccountSummary(account: account)
                        }
                        .cardRow(.single, insets: .settingsTextRow)
                    }
                }

                Section {
                    SettingsSectionTitle("Preferences")
                    NavigationLink(value: SettingsPage.currency) {
                        SettingsRow(symbol: "dollarsign.circle.fill", title: "Currency", value: preferences.currencyCode)
                    }
                    .cardRow(.first)
                    NavigationLink(value: SettingsPage.startWeek) {
                        SettingsRow(symbol: "calendar", title: "Start Week On", value: preferences.firstWeekday.title)
                    }
                    .cardRow(.middle)
                    NavigationLink(value: SettingsPage.smartSuggestions) {
                        SettingsRow(symbol: "text.viewfinder", title: "Smart Suggestions", value: preferences.smartSuggestionsEnabled ? "On" : "Off")
                    }
                    .cardRow(.middle)
                    NavigationLink(value: SettingsPage.weeklySummary) {
                        SettingsRow(symbol: "bell.fill", title: "Weekly Summary", value: preferences.weeklySummaryEnabled ? "On" : "Off")
                    }
                    .cardRow(.middle)
                    NavigationLink(value: SettingsPage.shortcut) {
                        SettingsRow(symbol: "command", title: "Shortcut")
                    }
                    .cardRow(.last)
                }

                Section {
                    SettingsSectionTitle("Support")
                    let rows = SupportRow.visible
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        NavigationLink(value: row.page) {
                            SettingsRow(symbol: row.symbol, title: row.title)
                        }
                        .cardRow(CardPosition(index: index, count: rows.count))
                    }
                }

                Section {
                    SettingsSectionTitle("Others")
                    NavigationLink(value: SettingsPage.privacy) {
                        SettingsRow(symbol: "lock.fill", title: "Privacy Policy")
                    }
                    .cardRow(.first)
                    NavigationLink(value: SettingsPage.terms) {
                        SettingsRow(symbol: "doc.text.fill", title: "Terms of Service")
                    }
                    .cardRow(.last)
                }

                Section {
                    SettingsFooter()
                        .plainListRow()
                        .id(Self.footerID)
                }
            }
            .settingsListStyle(sectionSpacing: 14)
            .task {
                #if DEBUG
                // `-KeaserSettingsScroll bottom` starts at the end of the page.
                guard DebugLaunch.string("KeaserSettingsScroll") == "bottom" else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(Self.footerID, anchor: .bottom)
                #endif
            }
        }
    }
}

/// Rows of the Support card. Help & Feedback and Follow Us only appear when
/// there is somewhere for them to point (see `AppLinks`).
private enum SupportRow: Hashable {
    case tutorials, whatsNew, help, followUs

    @MainActor
    static var visible: [SupportRow] {
        var rows: [SupportRow] = [.tutorials, .whatsNew]
        if SupportLinks.hasAny { rows.append(.help) }
        if !SupportLinks.social.isEmpty { rows.append(.followUs) }
        return rows
    }

    var title: String {
        switch self {
        case .tutorials: "Tutorials"
        case .whatsNew: "What's New"
        case .help: "Help & Feedback"
        case .followUs: "Follow Us"
        }
    }

    var symbol: String {
        switch self {
        case .tutorials: "book.pages"
        case .whatsNew: "sparkles"
        case .help: "star.bubble.fill"
        case .followUs: "person.fill.checkmark"
        }
    }

    var page: SettingsPage {
        switch self {
        case .tutorials: .tutorials
        case .whatsNew: .whatsNew
        case .help: .help
        case .followUs: .followUs
        }
    }
}

/// The selected account: monogram, name, and what the page behind it holds.
/// At accessibility sizes the text moves under the monogram, where it has
/// the card's full width.
private struct AccountSummary: View {
    let account: Account

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The monogram tile grows with the text, up to half as big again.
    @ScaledMetric(relativeTo: .title) private var textScale: CGFloat = 1

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let scale = min(textScale, 1.5)
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 18))
        layout {
            // Sized with the tile rather than as text, so the letter always
            // fills it the same way.
            Text(account.initial)
                .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 70 * scale, height: 70 * scale)
                .background(Color.settingsTile, in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .keaserFont(22, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(.white)
                    .lineLimit(isLarge ? 3 : 1)
                Text("Account info, categories and payments")
                    .keaserFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isLarge ? .infinity : 180, alignment: .leading)
            }
        }
        .padding(.vertical, isLarge ? 16 : 0)
        .frame(minHeight: 116)
        .accessibilityElement(children: .combine)
    }
}

/// Logo and version at the end of the page.
private struct SettingsFooter: View {
    var body: some View {
        VStack(spacing: 10) {
            KeaserLogo(size: 64)
            VStack(spacing: 2) {
                Text("Keaser")
                Text(AppVersion.current.display)
            }
            .font(.subheadline)
            .foregroundStyle(Color.keaserSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keaser version \(AppVersion.current.display)")
    }
}

extension AppVersion {
    /// This build's version, from the main bundle.
    static var current: AppVersion { AppVersion(infoDictionary: Bundle.main.infoDictionary) }
}

/// Where Help & Feedback and Follow Us lead, resolved from `AppLinks`.
@MainActor
enum SupportLinks {
    static var featureRequests: URL? {
        #if DEBUG
        if usesSamples { return URL(string: "https://example.com/keaser/ideas") }
        #endif
        return AppLinks.featureRequests
    }

    static var supportEmail: URL? {
        var address = AppLinks.supportEmail
        #if DEBUG
        if usesSamples { address = "support@example.com" }
        #endif
        return address.flatMap {
            SupportMail.url(to: $0, version: .current, system: "iOS \(UIDevice.current.systemVersion)")
        }
    }

    static var hasAny: Bool { featureRequests != nil || supportEmail != nil }

    static var social: [AppLinks.SocialLink] {
        #if DEBUG
        if usesSamples {
            return [
                AppLinks.SocialLink(service: "Website", handle: "example.com", url: URL(string: "https://example.com")!, symbol: "globe"),
                AppLinks.SocialLink(service: "Newsletter", handle: "Monthly", url: URL(string: "https://example.com/news")!, symbol: "envelope.open.fill"),
            ]
        }
        #endif
        return AppLinks.social
    }

    #if DEBUG
    /// `-KeaserSampleLinks 1` fills every link with example.com addresses,
    /// so the rows can be screenshotted before the real ones exist.
    private static var usesSamples: Bool { DebugLaunch.string("KeaserSampleLinks") == "1" }
    #endif
}
