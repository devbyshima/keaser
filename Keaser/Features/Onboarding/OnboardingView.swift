import KeaserKit
import SwiftUI

/// The five-page first-run flow. Calls `onFinish` after the last page.
///
/// Pages advance only with the button (no swiping), so every page's entrance
/// animation plays from the start and the Pro pass and notification steps
/// cannot be skipped by accident.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page: Int
    @State private var notifications: NotificationStep

    nonisolated static let pageCount = 5

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
                    .transition(reduceMotion ? .opacity : .push(from: .trailing))
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
                // The break matches the reference's short first line. At
                // larger sizes the first line would wrap by itself and leave
                // "to" alone on a line, so the text wraps naturally there.
                subtitle: dynamicTypeSize <= .xLarge
                    ? "Your simple, delightful way to\ntrack expenses."
                    : "Your simple, delightful way to track expenses.",
                button: "Get Started",
                illustrationHeight: 374,
                pictureHeight: 260,
                action: advance
            ) {
                SampleExpensesIllustration(currencyCode: store.preferences.currencyCode)
            } accessory: {
                // A solid tile reads heavier than an outline, so the mark is
                // drawn a little inside the reference's 140pt logo box.
                let scale = OnboardingMetrics.pictureScale(for: dynamicTypeSize)
                KeaserLogo(size: 120 * scale)
                    .frame(width: 140 * scale, height: 140 * scale)
                    .padding(.bottom, 13)
                    // The title right below already says "Keaser".
                    .accessibilityHidden(true)
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
        // Tapping Enable is the user's choice, whatever the system prompt
        // answers: the scheduler also needs permission, and re-checks it every
        // time the app becomes active, so allowing notifications later in the
        // Settings app starts the summary without another step here.
        store.updatePreferences { $0.weeklySummaryEnabled = true }
        Task {
            let permission = await NotificationPermission.request()
            withAnimation(.smooth(duration: 0.55)) {
                notifications = permission == .granted ? .granted : .denied
            }
        }
    }
}

// MARK: - Page layout

/// One onboarding page: an illustration in a fixed band at the top, the title
/// and subtitle at the bottom, and the button pinned below them.
///
/// Everything but the button scrolls, so at large text sizes the page grows
/// into a scrolling column instead of pushing the button off screen. At the
/// default size the column exactly fills the screen and nothing moves.
private struct OnboardingPage<Illustration: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let button: String
    /// The band the illustration is centred in. A fixed band (rather than the
    /// space left over) keeps illustrations at the same height whether the
    /// title takes one line or two.
    var illustrationHeight: CGFloat = 500
    /// The least the picture needs. The band never shrinks below it, so when
    /// the text grows the page scrolls rather than drawing text over it.
    var pictureHeight: CGFloat = 330
    let action: () -> Void
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        band
                        accessory
                        texts
                    }
                    .padding(.bottom, 28)
                    // Fills the screen when everything fits, so the band
                    // takes the room left over exactly as a fixed page would.
                    .frame(minHeight: viewport.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Button(action: action) {
                ZStack {
                    Text(button)
                        .multilineTextAlignment(.center)
                        .id(button)
                        .transition(textTransition)
                }
            }
            .buttonStyle(.keaserPrimary)
            .padding(.horizontal, OnboardingMetrics.horizontalPadding)
        }
    }

    /// The illustration is a picture, not text: it keeps its default-size
    /// look at every text size, and at accessibility sizes the whole picture
    /// is drawn smaller to leave the screen to the words.
    private var band: some View {
        let scale = OnboardingMetrics.pictureScale(for: dynamicTypeSize)
        let minimum = pictureHeight * scale
        return illustration
            .dynamicTypeSize(.large)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, minHeight: minimum, maxHeight: scale < 1 ? minimum : illustrationHeight)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    // Each text sits in a ZStack so that when it changes (the last page's
    // answer) the old and new copies cross-fade in place instead of stacking.
    private var texts: some View {
        VStack(spacing: 8) {
            ZStack {
                Text(title)
                    .font(.keaserTitle)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineSpacing(1.5)
                    .accessibilityAddTraits(.isHeader)
                    .id(title)
                    .transition(textTransition)
            }
            ZStack {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .id(subtitle)
                    .transition(textTransition)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, OnboardingMetrics.horizontalPadding)
    }

    private var textTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}

extension OnboardingPage where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        button: String,
        illustrationHeight: CGFloat = 500,
        pictureHeight: CGFloat = 330,
        action: @escaping () -> Void,
        @ViewBuilder illustration: () -> Illustration
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            button: button,
            illustrationHeight: illustrationHeight,
            pictureHeight: pictureHeight,
            action: action,
            illustration: illustration,
            accessory: { EmptyView() }
        )
    }
}

/// One dot per page; the current page is a wider white capsule.
private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.white : Color.white.opacity(0.36))
                    .frame(width: index == current ? 24 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: current)
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
        case .ask: "Get a short summary of your spending at the end of every week."
        case .granted: "You'll get a summary of your spending at the end of each week."
        case .denied: "You can turn them on anytime in the Settings app, under Keaser."
        }
    }
}

enum OnboardingMetrics {
    static let horizontalPadding: CGFloat = 28

    /// How large the illustrations are drawn. At accessibility text sizes
    /// they shrink so the title, subtitle and button keep most of the screen.
    static func pictureScale(for size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? 0.6 : 1
    }
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

/// `-KeaserOnboardingPage 0...4 | widgetGallery | widgetGalleryLocked` and
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
