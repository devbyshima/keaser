import KeaserKit
import SwiftUI

/// The note from the makers shown once, over Home, right after onboarding.
/// Dismissing it (Continue on the last page, the close button, or a swipe)
/// marks it seen; RootView owns that flag.
///
/// A second page lists the makers' social profiles, but only when
/// `AppLinks.social` has any; otherwise Continue on the letter dismisses.
struct WelcomeLetterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = WelcomeLetterLaunch.initialPage
    @State private var showsSummary = WelcomeLetterLaunch.showsSummary

    fileprivate enum Page { case letter, followAlong }

    private let links = WelcomeLetterLaunch.socialLinks

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                switch page {
                case .letter: letter.transition(pageTransition)
                case .followAlong: FollowAlongPage(links: links).transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The text stays white until it reaches the button, which floats
            // over it without a bar behind it, and shows faintly below it.
            .mask {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea(edges: .bottom)
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                    }
                }
            }

            KeaserCircleButton("xmark", label: "Close") { dismiss() }
                .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Continue", action: next)
                .buttonStyle(.keaserPrimary)
                .padding(.horizontal, 28)
        }
        .presentationDetents([.large])
        .keaserSheetChrome()
    }

    private var letter: some View {
        ScrollView {
            VStack(spacing: 0) {
                KeaserLogo(size: 104)
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)
                Text("Welcome to\nKeaser 🎉")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)
                VStack(alignment: .leading, spacing: 26) {
                    Button {
                        withAnimation(.smooth(duration: 0.4)) { showsSummary.toggle() }
                    } label: {
                        Text(showsSummary ? "Click for the full letter" : "Click for TL;DR")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.keaserPrimaryText)
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(.plain)
                    ZStack(alignment: .topLeading) {
                        if showsSummary {
                            LetterText(paragraphs: WelcomeLetter.summary)
                                .transition(textTransition)
                        } else {
                            LetterText(paragraphs: WelcomeLetter.paragraphs)
                                .transition(textTransition)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 52)
                .padding(.horizontal, 45)
                .padding(.bottom, 40)
            }
            .padding(.top, 70)
        }
        .scrollIndicators(.hidden)
    }

    private func next() {
        if page == .letter, !links.isEmpty {
            withAnimation(.smooth(duration: 0.5)) { page = .followAlong }
        } else {
            dismiss()
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .push(from: .trailing)
    }

    private var textTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}

/// Paragraphs separated by a blank line, as in a letter.
private struct LetterText: View {
    let paragraphs: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body)
        .foregroundStyle(Color.keaserPrimaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The letter's copy. Markdown bold marks a Settings path.
///
/// Help & Feedback only exists in Settings when there is somewhere to send
/// feedback (`AppLinks`), so the letter only points there then; otherwise it
/// points at What's New, which every build has.
private enum WelcomeLetter {
    static var paragraphs: [LocalizedStringKey] {
        [
            "Hi there 👋, a quick note from the Keaser team.",
            "Thank you for giving Keaser a try. It's brand new, so your first impressions mean a lot to us.",
            "Keaser is intentionally minimal. There's no sign-in, no setup to get through and no maze of reports. Open it, note what you spent, and get on with your day.",
            "Everything is built around quick logging. Smart Suggestions fill in the category and payment method as you type, Shortcuts add an expense from the lock screen or the moment you tap your wallet, and Widgets keep your total a glance away.",
            acceptsFeedback
                ? "There's plenty more we want to build. If you have an idea, or something doesn't feel right, reach us anytime from **Settings > Help & Feedback**."
                : "There's plenty more we want to build. Each update is listed in **Settings > What's New**, so you can see what changed.",
            "We're glad you're here. Happy tracking!",
        ]
    }

    static var summary: [LocalizedStringKey] {
        [
            acceptsFeedback
                ? "Fast logging, no sign-in, no clutter.\nIdeas? **Settings > Help & Feedback**."
                : "Fast logging, no sign-in, no clutter.\nUpdates: **Settings > What's New**.",
        ]
    }

    private static var acceptsFeedback: Bool {
        AppLinks.supportEmail != nil || AppLinks.featureRequests != nil
    }
}

/// "Follow along our journey": the makers' profiles from `AppLinks.social`.
private struct FollowAlongPage: View {
    let links: [AppLinks.SocialLink]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Follow along\nour journey 🚌")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                KeaserLogo(size: 76)
                    .frame(width: 86, height: 86)
                    .padding(.top, 34)
                    .accessibilityHidden(true)
                Text("Keaser is made by a small team that shares its work as it goes. Follow along for release notes, early looks at what's next, and a say in where the app heads.")
                    .font(.callout)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
                    .padding(.horizontal, 20)
                // Smaller corners than a KeaserCard, as in the reference.
                VStack(spacing: 0) {
                    ForEach(links) { link in
                        Button {
                            openURL(link.url)
                        } label: {
                            FollowLinkRow(link: link)
                        }
                        .buttonStyle(HighlightRowButtonStyle())
                        if link != links.last {
                            KeaserRowSeparator(leading: 0, trailing: 0)
                        }
                    }
                }
                .background(Color.keaserSheetCard)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 38)
            }
            .padding(.top, 58)
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}

/// A service and handle on one line. At accessibility sizes the icon and
/// arrow move to a line of their own so the service and handle get the full
/// width, and the handle (one unbreakable word) shrinks a little rather than
/// breaking mid-word.
private struct FollowLinkRow: View {
    let link: AppLinks.SocialLink
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the text, but only so far: a huge tile would crowd out the
    /// words it labels.
    @ScaledMetric(relativeTo: .body) private var scaledTile: CGFloat = 24

    private var tile: CGFloat { min(scaledTile, 36) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        icon
                        Spacer(minLength: 8)
                        arrow
                    }
                    .padding(.bottom, 4)
                    Text(link.service)
                        .foregroundStyle(Color.keaserPrimaryText)
                    Text(link.handle)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 12) {
                    icon
                    Text(link.service)
                        .foregroundStyle(Color.keaserPrimaryText)
                    Spacer(minLength: 8)
                    Text(link.handle)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .lineLimit(1)
                    arrow
                }
            }
        }
        .font(.body)
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }

    // The glyphs are sized from the tile they sit in, not from the text.
    private var icon: some View {
        Image(systemName: link.symbol)
            .font(.system(size: tile * 13 / 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: tile, height: tile)
            .background(Color.black, in: RoundedRectangle(cornerRadius: tile / 4, style: .continuous))
            .accessibilityHidden(true)
    }

    private var arrow: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: tile * 13 / 24, weight: .semibold))
            .foregroundStyle(Color.keaserSecondaryText)
            .accessibilityHidden(true)
    }
}

// MARK: - Launch arguments

/// `-KeaserLetterPage tldr|follow` (DEBUG only), used with `-KeaserLetter 1`.
/// `follow` fills in placeholder profiles when `AppLinks.social` is empty, so
/// the page can be checked before real links exist; they never ship.
private enum WelcomeLetterLaunch {
    static var initialPage: WelcomeLetterSheet.Page {
        DebugLaunch.string("KeaserLetterPage") == "follow" ? .followAlong : .letter
    }

    static var showsSummary: Bool {
        DebugLaunch.string("KeaserLetterPage") == "tldr"
    }

    static var socialLinks: [AppLinks.SocialLink] {
        #if DEBUG
        if AppLinks.social.isEmpty, DebugLaunch.string("KeaserLetterPage") == "follow" {
            return [
                AppLinks.SocialLink(service: "X (Twitter)", handle: "@yourhandle", url: URL(string: "https://example.com/x")!, symbol: "at"),
                AppLinks.SocialLink(service: "Threads", handle: "@yourhandle", url: URL(string: "https://example.com/threads")!, symbol: "at.circle"),
                AppLinks.SocialLink(service: "GitHub", handle: "yourhandle", url: URL(string: "https://example.com/github")!, symbol: "chevron.left.forwardslash.chevron.right"),
            ]
        }
        #endif
        return AppLinks.social
    }
}
