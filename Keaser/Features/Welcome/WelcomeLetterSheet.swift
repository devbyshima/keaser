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
    @State private var page: Page = WelcomeLetterLaunch.initialPage
    @State private var showsSummary = WelcomeLetterLaunch.showsSummary

    fileprivate enum Page { case letter, followAlong }

    private let links = WelcomeLetterLaunch.socialLinks

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                switch page {
                case .letter: letter.transition(.push(from: .trailing))
                case .followAlong: FollowAlongPage(links: links).transition(.push(from: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The text fades as it scrolls under the button, which floats
            // over it without a bar behind it.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.8),
                        .init(color: .black.opacity(0.45), location: 0.89),
                        .init(color: .black.opacity(0.2), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.keaserSecondaryText)
                    .keaserCircleButton()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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
                Text("Welcome to\nKeaser 🎉")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
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
                                .transition(.blurReplace)
                        } else {
                            LetterText(paragraphs: WelcomeLetter.paragraphs)
                                .transition(.blurReplace)
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

/// The letter's copy. Markdown bold marks the Settings path.
private enum WelcomeLetter {
    static var paragraphs: [LocalizedStringKey] {
        [
            "Hi there 👋, a quick note from the Keaser team.",
            "Thank you for giving Keaser a try. It's brand new, so your first impressions mean a lot to us.",
            "Keaser is intentionally minimal. There's no sign-in, no setup to get through and no maze of reports. Open it, note what you spent, and get on with your day.",
            "Everything is built around quick logging. Smart Suggestions fill in the category and payment method as you type, Shortcuts add an expense from the lock screen or the moment you tap your wallet, and Widgets keep your total a glance away.",
            "There's plenty more we want to build. If you have an idea, or something doesn't feel right, reach us anytime from **Settings → Help & Feedback**.",
            "We're glad you're here. Happy tracking!",
        ]
    }

    static var summary: [LocalizedStringKey] {
        ["Fast logging, no sign-in, no clutter.\nIdeas? **Settings → Help & Feedback**."]
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
                KeaserLogo(size: 76)
                    .frame(width: 86, height: 86)
                    .padding(.top, 34)
                Text("Keaser is made by a small team that shares its work as it goes. Follow along for release notes, early looks at what's next, and a say in where the app heads.")
                    .font(.callout)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
                    .padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(links) { link in
                        Button {
                            openURL(link.url)
                        } label: {
                            FollowLinkRow(link: link)
                        }
                        .buttonStyle(.plain)
                        if link != links.last {
                            Rectangle()
                                .fill(Color.keaserSeparator)
                                .frame(height: 1 / 3)
                        }
                    }
                }
                .background(Color.keaserCardRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 38)
            }
            .padding(.top, 58)
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FollowLinkRow: View {
    let link: AppLinks.SocialLink

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: link.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(link.service)
                .foregroundStyle(Color.keaserPrimaryText)
            Spacer(minLength: 8)
            Text(link.handle)
                .foregroundStyle(Color.keaserSecondaryText)
                .lineLimit(1)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.keaserSecondaryText)
        }
        .font(.body)
        .padding(.horizontal, 15)
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
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
