import KeaserKit
import SwiftUI

/// The six-page first-run flow. Calls `onFinish` after the last page.
///
/// Pages advance only with the button (no swiping), so every page's entrance
/// animation plays from the start and the Pro pass and notification steps
/// cannot be skipped by accident.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @State private var page: Int
    @State private var notifications: NotificationStep

    nonisolated static let pageCount = 6

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: OnboardingLaunch.initialPage)
        _notifications = State(initialValue: OnboardingLaunch.initialNotificationStep)
    }

    var body: some View {
        ZStack {
            OnboardingPalette.background.ignoresSafeArea()
            #if DEBUG
            if let gallery = OnboardingLaunch.widgetGallery {
                WidgetGallery(showsLockedStates: gallery == .locked)
            } else {
                flow
            }
            #else
            flow
            #endif
        }
    }

    private var flow: some View {
        VStack(spacing: 0) {
            OnboardingPageIndicator(count: Self.pageCount, current: page)
                .padding(.top, 16)
            ZStack {
                currentPage
                    .id(page)
                    .transition(.push(from: .trailing))
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case 0:
            OnboardingPage(
                title: "Welcome to Keaser",
                // The break matches the reference's short first line.
                subtitle: "Your simple, delightful way to\ntrack expenses.",
                button: "Get Started",
                illustrationHeight: 374,
                action: advance
            ) {
                SampleExpensesIllustration(currencyCode: store.preferences.currencyCode)
            } accessory: {
                // A solid tile reads heavier than an outline, so the mark is
                // drawn a little inside the reference's 140pt logo box.
                KeaserLogo(size: 120)
                    .frame(width: 140, height: 140)
                    .padding(.bottom, 13)
            }
        case 1:
            OnboardingPage(
                title: "Faster Logging\nwith Shortcuts",
                subtitle: "Quickly add expenses from the lock screen or when you tap your wallet.",
                button: "Continue",
                action: advance
            ) {
                ShortcutsIllustration()
            }
        case 2:
            OnboardingPage(
                title: "Stay Updated\nwith Widgets",
                subtitle: "Add home screen widgets to view your spending at a glance.",
                button: "Continue",
                action: advance
            ) {
                WidgetsIllustration(currencyCode: store.preferences.currencyCode)
            }
        case 3:
            OnboardingPage(
                title: "Syncs with Notion",
                subtitle: "Continue where you left off in Notion, with a faster, dedicated experience.",
                button: "Continue",
                action: advance
            ) {
                NotionIllustration()
            }
        case 4:
            OnboardingPage(
                title: "7-Day Pro Pass,\nOn Us",
                subtitle: "Enjoy full Pro features for 7 days. No automatic billing after pass expires.",
                button: "Continue",
                action: {
                    pro.startTrialIfNeeded()
                    advance()
                }
            ) {
                ProPassIllustration()
            }
        default:
            notificationsPage
        }
    }

    private var notificationsPage: some View {
        OnboardingPage(
            title: notifications.title,
            subtitle: notifications.subtitle,
            button: notifications == .ask ? "Enable Notifications" : "Continue",
            action: {
                if notifications == .ask {
                    requestNotifications()
                } else {
                    onFinish()
                }
            }
        ) {
            NotificationsIllustration(step: notifications, currencyCode: store.preferences.currencyCode)
        }
    }

    private func advance() {
        guard page < Self.pageCount - 1 else { return onFinish() }
        withAnimation(.smooth(duration: 0.5)) { page += 1 }
    }

    private func requestNotifications() {
        Task {
            let permission = await NotificationPermission.request()
            let granted = permission == .granted
            store.updatePreferences { $0.weeklySummaryEnabled = granted }
            withAnimation(.smooth(duration: 0.55)) {
                notifications = granted ? .granted : .denied
            }
        }
    }
}

// MARK: - Page layout

/// One onboarding page: an illustration in a fixed band at the top, and the
/// title, subtitle and button anchored to the bottom.
private struct OnboardingPage<Illustration: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let button: String
    /// The band the illustration is centred in. A fixed band (rather than the
    /// space left over) keeps illustrations at the same height whether the
    /// title takes one line or two.
    var illustrationHeight: CGFloat = 500
    let action: () -> Void
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .frame(maxWidth: .infinity, maxHeight: illustrationHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            accessory
            // Each text sits in a ZStack so that when it changes (the last
            // page's answer) the old and new copies cross-fade in place
            // instead of stacking.
            VStack(spacing: 8) {
                ZStack {
                    Text(title)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Color.keaserPrimaryText)
                        .lineSpacing(1.5)
                        .id(title)
                        .transition(.blurReplace)
                }
                ZStack {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .id(subtitle)
                        .transition(.blurReplace)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, OnboardingMetrics.horizontalPadding)
            .padding(.bottom, 28)
            Button(action: action) {
                ZStack {
                    Text(button)
                        .id(button)
                        .transition(.blurReplace)
                }
            }
            .buttonStyle(.keaserPrimary)
            .padding(.horizontal, OnboardingMetrics.horizontalPadding)
        }
    }
}

extension OnboardingPage where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        button: String,
        illustrationHeight: CGFloat = 500,
        action: @escaping () -> Void,
        @ViewBuilder illustration: () -> Illustration
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            button: button,
            illustrationHeight: illustrationHeight,
            action: action,
            illustration: illustration,
            accessory: { EmptyView() }
        )
    }
}

/// Six dots; the current page is a wider white capsule.
private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.white : Color.white.opacity(0.36))
                    .frame(width: index == current ? 24 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.4), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// The last page's state: asking, then the answer.
enum NotificationStep: Equatable {
    case ask
    case granted
    case denied

    var title: String {
        switch self {
        case .ask: "Get Notified"
        case .granted: "Notifications Enabled"
        case .denied: "Notifications Off"
        }
    }

    var subtitle: String {
        switch self {
        case .ask: "Enable notifications to stay aware of your spending trends and synced updates."
        case .granted: "Notifications are enabled. We'll send reminders and spending updates."
        case .denied: "You can turn them on anytime in the Settings app, under Keaser."
        }
    }
}

enum OnboardingMetrics {
    static let horizontalPadding: CGFloat = 28
}

/// Shades used only by the onboarding illustrations, measured from the
/// reference. The page itself is a lifted black, not the app's pure black.
enum OnboardingPalette {
    static let background = Color(white: 25 / 255)
    /// The lock screen and home screen panels.
    static let panel = Color(red: 38 / 255, green: 37 / 255, blue: 40 / 255)
    /// The "9:41" on those panels.
    static let clock = Color(red: 149 / 255, green: 148 / 255, blue: 156 / 255)
    /// Icon tiles on the sample expense rows.
    static let tile = Color(white: 0.2)
}

// MARK: - Launch arguments

/// `-KeaserOnboardingPage 0...5 | widgetGallery | widgetGalleryLocked` and
/// `-KeaserNotifState granted|denied` (DEBUG only; see AGENTS.md).
enum OnboardingLaunch {
    enum Gallery { case unlocked, locked }

    static var initialPage: Int {
        min(max(DebugLaunch.int("KeaserOnboardingPage") ?? 0, 0), OnboardingView.pageCount - 1)
    }

    static var initialNotificationStep: NotificationStep {
        switch DebugLaunch.string("KeaserNotifState") {
        case "granted": .granted
        case "denied": .denied
        default: .ask
        }
    }

    static var widgetGallery: Gallery? {
        switch DebugLaunch.string("KeaserOnboardingPage") {
        case "widgetGallery": .unlocked
        case "widgetGalleryLocked": .locked
        default: nil
        }
    }
}
