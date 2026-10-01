import KeaserKit
import SwiftUI

/// The Settings tab: its own NavigationStack, whose path is
/// `AppRouter.settingsPath` so a route can take it back to the root, and the
/// paywall that Upgrade opens as a sheet.
struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @State private var showsPaywall = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            SettingsRootList(path: $router.settingsPath, showsPaywall: $showsPaywall)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SettingsPage.self) { $0.destination }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        // A route (a widget, Siri, Spotlight) closes the paywall: a sheet
        // left up would hide the tab the route selects.
        .onChange(of: router.modalReset) { showsPaywall = false }
    }
}

private struct SettingsRootList: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Binding var path: [SettingsPage]
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
                    let card = NavigationLink(value: SettingsPage.account(account.id)) {
                        AccountSummary(account: account)
                    }
                    .cardRow(.single, insets: .settingsTextRow)
                    // iCloud sync's status as the card's small print, only
                    // while sync is on.
                    if let status = CloudSync.shared.displayedStatus {
                        Section { card } footer: { CloudSyncFootnote(status: status) }
                    } else {
                        Section { card }
                    }
                } else if let status = CloudSync.shared.displayedStatus {
                    Section {} footer: { CloudSyncFootnote(status: status) }
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

                // The reference shows these two rows without a chevron, so
                // they are buttons that push the page rather than links.
                Section {
                    SettingsSectionTitle("Others")
                    Button { path.append(.privacy) } label: {
                        SettingsRow(symbol: "lock.fill", title: "Privacy Policy", hasDisclosure: false)
                    }
                    .cardRow(.first)
                    Button { path.append(.terms) } label: {
                        SettingsRow(symbol: "doc.text.fill", title: "Terms of Service", hasDisclosure: false)
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
                // `-KeaserSettingsScroll bottom` starts at the end of the page,
                // once: coming back to the tab must not scroll it again.
                guard DebugLaunch.string("KeaserSettingsScroll") == "bottom",
                      DebugLaunch.firstTime("settingsRootScroll")
                else { return }
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
    /// The monogram circle grows with the text, up to half as big again.
    @ScaledMetric(relativeTo: .title) private var textScale: CGFloat = 1
    /// Narrow enough that the subtitle breaks after "categories", as in the
    /// reference, at every text size.
    @ScaledMetric(relativeTo: .footnote) private var subtitleWidth: CGFloat = 160

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let scale = min(textScale, 1.5)
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            // Sized with the circle rather than as text, so the letter always
            // fills it the same way.
            Text(account.initial)
                .font(.system(size: 32 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(width: 70 * scale, height: 70 * scale)
                .background(Color.settingsTile, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .keaserFont(22, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(isLarge ? 3 : 1)
                // 13pt on an 18pt line, as in the reference.
                Text("Account info, categories and payments")
                    .keaserFont(13, relativeTo: .footnote)
                    .lineSpacing(2.5)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isLarge ? .infinity : subtitleWidth, alignment: .leading)
            }
        }
        .padding(.vertical, isLarge ? 16 : 0)
        .frame(minHeight: 116)
        .accessibilityElement(children: .combine)
    }
}

/// Logo, then the name and version on two centred lines, at the end of the
/// page.
private struct SettingsFooter: View {
    var body: some View {
        let version = AppVersion.current
        VStack(spacing: 20) {
            KeaserLogo(size: 68)
            VStack(spacing: 0) {
                Text("Keaser")
                Text(version.short)
            }
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keaser version \(version.marketing)")
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
