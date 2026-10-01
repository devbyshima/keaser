import KeaserKit
import SwiftUI

/// Every guide, each on its own card with a line on what it sets up.
struct TutorialsView: View {
    var body: some View {
        List {
            ForEach(Tutorials.all) { tutorial in
                Section {
                    NavigationLink(value: SettingsPage.tutorial(tutorial.id)) {
                        CompactRow(symbol: tutorial.symbol, title: tutorial.title)
                    }
                    .cardRow(.single, insets: .settingsTextRow)
                } footer: {
                    SettingsFootnote(tutorial.summary)
                }
            }
        }
        // Each footnote sits as far above the next card as on the Shortcut
        // page, as in the reference.
        .settingsListStyle(sectionSpacing: 17.5)
        .settingsPage("Tutorials")
    }
}

/// One guide as an article: headline and intro, then its sections, and a
/// way into the Shortcuts app at the end. The pieces are in
/// TutorialArticle.swift, the drawings in TutorialIllustrations.swift.
struct TutorialDetailView: View {
    let tutorial: Tutorial

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TutorialHeader(tutorial: tutorial)
                    ForEach(tutorial.sections) { section in
                        TutorialSectionView(section: section)
                            .id(section.id)
                    }
                    TutorialShortcutsButton()
                        .padding(.top, 36)
                        .id(Tutorials.endAnchor)
                }
                .padding(.horizontal, KeaserMetrics.screenPadding)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .keaserSoftBottomEdge()
            .background(Color.settingsCanvas.ignoresSafeArea())
            .task {
                #if DEBUG
                // `-KeaserTutorialScroll <section id>`, an illustration's
                // name, or `end` starts the article there, so a screenshot
                // can show it (once a launch).
                guard let anchor = DebugLaunch.string("KeaserTutorialScroll"),
                      DebugLaunch.firstTime("tutorialScroll")
                else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(anchor, anchor: .top)
                #endif
            }
        }
        .settingsPage(tutorial.title)
    }
}

/// Every release, newest first.
struct WhatsNewView: View {
    var body: some View {
        let releases = ReleaseHistory.releases
        List {
            Section {
                ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                    NavigationLink(value: SettingsPage.release(release.version)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.title)
                                .font(.body)
                                .foregroundStyle(Color.keaserPrimaryText)
                            Text(release.date)
                                .font(.footnote)
                                .foregroundStyle(Color.keaserSecondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .cardSeparatorTrailing(overChevron: true)
                    }
                    .cardRow(CardPosition(index: index, count: releases.count), insets: .settingsTextRow)
                }
            }
        }
        .settingsListStyle()
        .settingsPage("What's New")
    }
}

/// What one release brought.
struct ReleaseDetailView: View {
    let version: String

    var body: some View {
        let release = ReleaseHistory.releases.first { $0.version == version }
        List {
            if let release {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(release.title)
                            .keaserFont(28, weight: .bold, relativeTo: .title)
                            .foregroundStyle(Color.keaserPrimaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(release.date)
                            .font(.subheadline)
                            .foregroundStyle(Color.keaserSecondaryText)
                        Text(release.summary)
                            .font(.body)
                            .foregroundStyle(Color.keaserPrimaryText.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .plainListRow()
                }

                Section {
                    ForEach(Array(release.highlights.enumerated()), id: \.offset) { index, highlight in
                        HStack(alignment: .top, spacing: 13) {
                            SettingsSymbol(symbol: highlight.symbol)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(highlight.title)
                                    .keaserFont(17, weight: .semibold, relativeTo: .headline)
                                    .foregroundStyle(Color.keaserPrimaryText)
                                Text(highlight.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.keaserSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 8)
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSeparatorTrailing()
                        .accessibilityElement(children: .combine)
                        .cardRow(CardPosition(index: index, count: release.highlights.count))
                    }
                }
            }
        }
        .settingsListStyle(sectionSpacing: 24, topMargin: 24)
        .settingsPage(release?.title ?? "What's New")
    }
}

/// Feature requests and support email, when `AppLinks` provides them.
struct HelpFeedbackView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        let rows = links
        List {
            if !rows.isEmpty {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                        Button {
                            openURL(row.url)
                        } label: {
                            CompactRow(symbol: row.symbol, title: row.title, accessory: "arrow.up.right")
                        }
                        .cardRow(CardPosition(index: index, count: rows.count), insets: .settingsTextRow)
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if rows.isEmpty {
                EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "No Contact Links", message: "Reach us through the support link on Keaser\u{2019}s App Store page.")
            }
        }
        .settingsPage("Help & Feedback")
    }

    private var links: [(symbol: String, title: String, url: URL)] {
        var rows: [(symbol: String, title: String, url: URL)] = []
        // The bulb with dotted rays, as in the reference.
        if let url = SupportLinks.featureRequests { rows.append(("lightbulb.min.fill", "Feature Requests", url)) }
        if let url = SupportLinks.supportEmail { rows.append(("envelope.fill", "Support Email", url)) }
        return rows
    }
}

/// Where to follow Keaser, from `AppLinks.social`.
struct FollowUsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = SupportLinks.social
        List {
            Section {
                VStack(spacing: 16) {
                    KeaserLogo(size: 72)
                    VStack(spacing: 14) {
                        Text("Hey there! Thanks for\ntrying Keaser.")
                        Text("Follow along for product updates and a first look at upcoming features.")
                    }
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .plainListRow()
            }

            if links.isEmpty {
                Section {
                    Text("No profiles yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(maxWidth: .infinity)
                        .plainListRow()
                }
            } else {
                Section {
                    ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                        Button {
                            openURL(link.url)
                        } label: {
                            SocialLinkRow(link: link)
                        }
                        .cardRow(CardPosition(index: index, count: links.count), insets: .settingsTextRow)
                    }
                }
            }
        }
        .settingsListStyle(sectionSpacing: 24, topMargin: 24)
        .settingsPage("Follow Us")
    }
}

/// A profile on Follow Us, laid out as the reference's: the service's tile
/// 16pt in from the card, then 12pt to the name, and again between the
/// handle and the arrow, on a 54pt row. The separator starts under the
/// name. At accessibility sizes the handle moves under the name.
private struct SocialLinkRow: View {
    let link: AppLinks.SocialLink

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the text, but only so far, as in the welcome letter.
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            SocialLinkTile(symbol: link.symbol, size: min(tile, 36))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    service
                    handle
                }
                .padding(.vertical, 10)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
            } else {
                service
                    .lineLimit(1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                handle
                    .lineLimit(1)
            }
            LinkAccessory(symbol: "arrow.up.right")
        }
        .font(.body)
        .frame(minHeight: 54)
        .cardSeparatorTrailing()
        .contentShape(Rectangle())
    }

    private var service: some View {
        Text(link.service)
            .foregroundStyle(Color.keaserPrimaryText)
    }

    private var handle: some View {
        Text(link.handle)
            .foregroundStyle(Color.keaserSecondaryText)
    }
}
