import KeaserKit
import SwiftUI
import WidgetKit

// The animated pictures at the top of each onboarding page. Each one plays its
// entrance once, when its page appears, and then rests in the state the
// screenshots capture.

// MARK: - Page 0: sample expenses

/// Three sample expenses rise in one after another above the logo; the stack
/// re-centres as each one arrives.
struct SampleExpensesIllustration: View {
    let currencyCode: String
    @State private var shown = 0

    private struct Sample: Identifiable {
        let title: String
        let amount: Decimal
        let symbol: String
        var id: String { title }
    }

    private let samples = [
        Sample(title: "Coffee", amount: Decimal(string: "4.50")!, symbol: "cup.and.saucer.fill"),
        Sample(title: "Groceries", amount: Decimal(string: "87.23")!, symbol: "basket.fill"),
        Sample(title: "Gas", amount: 42, symbol: "fuelpump.fill"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(samples.prefix(shown)) { sample in
                SampleExpenseRow(
                    title: sample.title,
                    amount: MoneyFormat.string(sample.amount, currencyCode: currencyCode),
                    symbol: sample.symbol
                )
                .transition(.riseIn)
            }
        }
        .frame(width: 320)
        .accessibilityElement(children: .combine)
        .task {
            for index in samples.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 400 : 800))
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { shown = index + 1 }
            }
        }
    }
}

/// A black expense row with an icon tile, as in the reference's first page.
private struct SampleExpenseRow: View {
    let title: String
    let amount: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            SymbolTile(symbol: symbol, size: 47, background: OnboardingPalette.tile)
            Text(title)
                .font(.system(size: 19, weight: .medium))
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 21)
        .frame(height: 70)
        .onboardingPill(cornerRadius: KeaserMetrics.rowRadius)
    }
}

// MARK: - Page 1: Shortcuts

/// A lock screen; then the "Add Expense" shortcut's amount prompt floats in
/// over the clock.
struct ShortcutsIllustration: View {
    @State private var showsPrompt = false

    var body: some View {
        LockScreenPanel(height: 325) {
            ZStack(alignment: .top) {
                LockScreenClock()
                if showsPrompt {
                    ShortcutPrompt()
                        .padding(.horizontal, 15)
                        .padding(.top, 20)
                        .transition(.promptIn)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.spring(duration: 0.5, bounce: 0.22)) { showsPrompt = true }
        }
    }
}

/// The Shortcuts "Ask for Input" prompt, drawn rather than captured.
private struct ShortcutPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amount")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .padding(.leading, 1)
            Text("16.99")
                .font(.system(size: 37, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 73)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 11)
            HStack(spacing: 8) {
                Text("Cancel")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.07), in: Capsule())
                Text("Done")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white, in: Capsule())
            }
            .frame(height: 50)
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .illustrationGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A shortcut asking for an amount, 16.99")
    }
}

// MARK: - Page 2: widgets

/// A home screen with the real Spending widget. It starts small on the left,
/// widens to the medium size, then settles small on the right.
struct WidgetsIllustration: View {
    let currencyCode: String
    @State private var stage = Stage.smallLeading

    private enum Stage { case smallLeading, medium, smallTrailing }

    var body: some View {
        LockScreenPanel(height: 325) {
            GeometryReader { proxy in
                let inset: CGFloat = 16
                let small: CGFloat = 160
                let width = stage == .medium ? proxy.size.width - inset * 2 : small
                let x = stage == .smallTrailing ? proxy.size.width - inset - small : inset
                let snapshot = SpendingSnapshot.sample(currencyCode: currencyCode)
                ZStack {
                    if stage == .medium {
                        SpendingWidgetView(snapshot: snapshot, family: .systemMedium, inApp: true)
                            .transition(.opacity)
                    } else {
                        SpendingWidgetView(snapshot: snapshot, family: .systemSmall, inApp: true)
                            .transition(.opacity)
                    }
                }
                .padding(16)
                .frame(width: width, height: small)
                .background(WidgetPalette.background, in: RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 1.5)
                .offset(x: x, y: 20)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(duration: 0.55, bounce: 0.15)) { stage = .medium }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.spring(duration: 0.55, bounce: 0.15)) { stage = .smallTrailing }
        }
    }
}

// MARK: - Page 3: Notion

/// Keaser and Notion linked by travelling dots, then what the link brings,
/// one line at a time.
struct NotionIllustration: View {
    @State private var shownLines = 0

    private let lines = [
        "Fast logging with Apple Shortcuts.",
        "Easily filter and visualize your data using charts.",
        "Add home screen widgets to view total spending at a glance.",
    ]

    var body: some View {
        VStack(spacing: 44) {
            HStack(spacing: 16) {
                KeaserLogo(size: 90)
                    .frame(width: 100, height: 100)
                TravellingDots()
                NotionTile(size: 100)
            }
            // Every line is laid out from the start, hidden, so the picture
            // does not move as they appear.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let visible = index < shownLines
                    HStack(spacing: 15) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 13)
                        Text(line)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.keaserSecondaryText)
                    .opacity(visible ? 1 : 0)
                    .blur(radius: visible ? 0 : 6)
                    .offset(y: visible ? 0 : 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 43)
        }
        .offset(y: 24)
        .task {
            for index in lines.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 500 : 900))
                withAnimation(.smooth(duration: 0.5)) { shownLines = index + 1 }
            }
        }
    }
}

/// Five dots with a bright one running from Keaser to Notion, on a loop.
private struct TravellingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            // The head moves 4.5 dots a second over 5 dots plus a short rest.
            let head = (context.date.timeIntervalSinceReferenceDate * 4.5).truncatingRemainder(dividingBy: 7)
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    let behind = head - Double(index)
                    let glow = behind >= 0 && behind < 1.6 ? 1 - behind / 1.6 : 0
                    Circle()
                        .fill(Color.white.opacity(0.27 + 0.61 * glow))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A neutral stand-in for the Notion mark: an outlined tile with a plain "N".
struct NotionTile: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: size * 0.07)
            )
            .overlay(
                Text("N")
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .accessibilityLabel("Notion")
    }
}

// MARK: - Page 4: Pro pass

/// The four Pro features as a 2x2 grid of icon tiles, unfolding into a list of
/// labelled pills.
struct ProPassIllustration: View {
    @State private var unfolded = false

    private let features = ProFeature.allCases

    var body: some View {
        ZStack {
            ForEach(Array(features.enumerated()), id: \.element) { index, feature in
                ProFeaturePill(feature: feature, unfolded: unfolded)
                    .offset(offset(of: index))
                    .animation(.spring(duration: 0.7, bounce: 0.18).delay(Double(index) * 0.04), value: unfolded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            unfolded = true
        }
    }

    /// Grid cells are 100x67 with 8pt and 15pt gaps; list pills are 66pt tall
    /// with 18pt gaps. Both are centred on the same point.
    private func offset(of index: Int) -> CGSize {
        if unfolded {
            return CGSize(width: 0, height: (CGFloat(index) - 1.5) * (66 + 18))
        }
        let column = CGFloat(index % 2), row = CGFloat(index / 2)
        return CGSize(width: (column - 0.5) * (100 + 8), height: (row - 0.5) * (67 + 15))
    }
}

private struct ProFeaturePill: View {
    let feature: ProFeature
    let unfolded: Bool

    private static let width: CGFloat = 300

    var body: some View {
        let width = unfolded ? Self.width : 100
        ZStack {
            Image(systemName: feature.symbol)
                .font(.system(size: 30, weight: .semibold))
                // Scaled rather than resized: a font change swaps the symbol
                // instead of animating it, which lets the icon lag the pill.
                .scaleEffect(unfolded ? 22 / 30 : 1)
                .frame(width: 34)
                // Centred in a tile; 42pt from the pill's leading edge.
                .offset(x: unfolded ? 42 - width / 2 : 0)
            Text(feature.title)
                .font(.system(size: 19, weight: .semibold))
                .fixedSize()
                .frame(width: Self.width - 73, alignment: .leading)
                // 73pt from the pill's leading edge in both layouts, so it
                // travels with the edge and never runs under the icon.
                .offset(x: 73 + (Self.width - 73) / 2 - width / 2)
                .opacity(unfolded ? 1 : 0)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: unfolded ? 66 : 67)
        .onboardingPill(cornerRadius: unfolded ? 24 : 28)
    }
}

// MARK: - Page 5: notifications

/// A lock screen that receives the weekly summary; once the user answers the
/// permission prompt it gives way to a large check (or a muted bell).
struct NotificationsIllustration: View {
    let step: NotificationStep
    let currencyCode: String
    @State private var showsBanner = false

    var body: some View {
        ZStack {
            if step == .ask {
                LockScreenPanel(height: 292) {
                    ZStack(alignment: .top) {
                        LockScreenClock()
                        if showsBanner {
                            NotificationBanner(currencyCode: currencyCode)
                                .padding(.horizontal, 14.7)
                                .padding(.top, 175.7)
                                .transition(.riseIn)
                        }
                    }
                }
                .transition(.blurReplace)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.21))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: step == .granted ? "checkmark" : "bell.slash.fill")
                            .font(.system(size: step == .granted ? 60 : 46, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(y: 14)
                    .transition(.scale(0.6).combined(with: .opacity).combined(with: .blurReplace))
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard step == .ask else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { showsBanner = true }
        }
    }
}

private struct NotificationBanner: View {
    let currencyCode: String

    var body: some View {
        HStack(spacing: 10) {
            KeaserAppIcon(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(WeeklySummary.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text("now")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.keaserSecondaryText)
                }
                Text(WeeklySummary.body(total: Decimal(string: "188.20")!, currencyCode: currencyCode))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .illustrationGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Shared pieces

/// A phone's lock or home screen, cropped: a tall rounded panel that fades
/// into the page towards the bottom.
private struct LockScreenPanel<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(OnboardingPalette.panel)
            .overlay(alignment: .top) { content }
            .frame(height: height)
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.77), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.horizontal, 26)
    }
}

private struct LockScreenClock: View {
    var body: some View {
        Text("9:41")
            .font(.system(size: 80))
            .foregroundStyle(OnboardingPalette.clock)
            .padding(.top, 59)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// System glass for the drawn Shortcuts prompt and notification. Before
    /// iOS 26 the material stand-in is darker than the glass these mimic, so
    /// it gets a faint lift.
    @ViewBuilder
    func illustrationGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            keaserGlass(in: shape)
        } else {
            background(Color.white.opacity(0.055), in: shape).keaserGlass(in: shape)
        }
    }

    /// The black pill of the sample rows and Pro features, with the faint
    /// lower rim the reference gives them.
    func onboardingPill(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Color.black, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.03), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
    }
}

private extension AnyTransition {
    /// Up from below, out of a blur.
    static var riseIn: AnyTransition {
        .modifier(active: RiseIn(progress: 0), identity: RiseIn(progress: 1))
    }

    /// Grows out of a blur, like a system alert.
    static var promptIn: AnyTransition {
        .modifier(active: PromptIn(progress: 0), identity: PromptIn(progress: 1))
    }
}

private struct RiseIn: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress)
            .offset(y: 44 * (1 - progress))
            .blur(radius: 8 * (1 - progress))
    }
}

private struct PromptIn: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.82 + 0.18 * progress)
            .blur(radius: 10 * (1 - progress))
    }
}
