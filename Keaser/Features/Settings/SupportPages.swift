import KeaserKit
import SwiftUI

/// The two guides, each with a line on what it sets up.
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
        .settingsListStyle(sectionSpacing: 22)
        .settingsPage("Tutorials")
    }
}

/// One guide: what it does, numbered steps, and a way into Shortcuts.
struct TutorialDetailView: View {
    let tutorial: Tutorial

    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    SettingsSymbol(symbol: tutorial.symbol, size: 72, pointSize: 32)
                        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text(tutorial.title)
                        .keaserFont(22, weight: .bold, relativeTo: .title2)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(tutorial.intro)
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .plainListRow()
            }

            Section {
                ForEach(Array(tutorial.steps.enumerated()), id: \.offset) { index, step in
                    StepRow(number: index + 1, step: step)
                        .cardRow(CardPosition(index: index, count: tutorial.steps.count), insets: .settingsTextRow)
                }
            } footer: {
                if let note = tutorial.note {
                    SettingsFootnote(note)
                }
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    CompactRow(symbol: "square.stack.3d.up.fill", title: "Open Shortcuts", accessory: "arrow.up.right")
                }
                .cardRow(.single, insets: .settingsTextRow)
            }
        }
        .settingsListStyle(sectionSpacing: 24, topMargin: 24)
        .settingsPage(tutorial.title)
    }
}

private struct StepRow: View {
    let number: Int
    let step: Tutorial.Step

    /// The number's circle grows with the number inside it.
    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 28

    init(number: Int, step: Tutorial.Step) {
        self.number = number
        self.step = step
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .keaserFont(15, weight: .semibold, design: .rounded, relativeTo: .subheadline)
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color.keaserInk.opacity(0.1)))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .keaserFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(Color.keaserPrimaryText)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSeparatorTrailing()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(step.title). \(step.detail)")
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
        if let url = SupportLinks.featureRequests { rows.append(("lightbulb.max.fill", "Feature Requests", url)) }
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
                            CompactRow(symbol: link.symbol, title: link.service, value: link.handle, accessory: "arrow.up.right")
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
