import KeaserKit
import SwiftUI
import WidgetKit

// The animated pictures at the top of each onboarding page. Each one plays its
// entrance once, when its page appears, and then rests in the state the
// screenshots capture. With Reduce Motion they either start in that resting
// state or only fade their parts in.
//
// These are pictures drawn at sizes measured from the reference, so their
// text uses fixed point sizes: the page pins them to the default text size
// and shrinks the whole picture at accessibility sizes instead.

// MARK: - Page 0: sample expenses

/// Three sample expenses rise in one after another above the logo; the stack
/// re-centres as each one arrives.
struct SampleExpensesIllustration: View {
    let currencyCode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        // The stack re-centres as rows arrive, which is movement, so Reduce
        // Motion shows all three from the start.
        let visible = reduceMotion ? samples.count : shown
        VStack(spacing: 14) {
            ForEach(samples.prefix(visible)) { sample in
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
            guard !reduceMotion else { return }
            for index in samples.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 400 : 800))
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { shown = index + 1 }
            }
        }
    }
}

/// An expense row with an icon tile, as in the reference's first page.
private struct SampleExpenseRow: View {
    let title: String
    let amount: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            SymbolTile(symbol: symbol, size: 47, background: OnboardingPalette.tile)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 19, weight: .medium))
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.keaserPrimaryText)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPrompt = false

    var body: some View {
        LockScreenPanel(height: 325) {
            ZStack(alignment: .top) {
                LockScreenClock()
                if showsPrompt {
                    ShortcutPrompt()
                        .padding(.horizontal, 15)
                        .padding(.top, 20)
                        .transition(reduceMotion ? .opacity : .promptIn)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(duration: 0.5, bounce: 0.22)) { showsPrompt = true }
        }
    }
}

/// The Shortcuts "Ask for Input" prompt, drawn rather than captured.
private struct ShortcutPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amount")
                .font(.system(size: 18))
                .foregroundStyle(Color.keaserPrimaryText)
                .padding(.leading, 1)
            Text("16.99")
                .font(.system(size: 37, weight: .bold))
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 73)
                .background(OnboardingPalette.promptField, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 11)
            HStack(spacing: 8) {
                Text("Cancel")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OnboardingPalette.promptCancel, in: Capsule())
                Text("Done")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.keaserOnInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.keaserInk, in: Capsule())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedStage = Stage.smallLeading

    private enum Stage { case smallLeading, medium, smallTrailing }

    /// Reduce Motion skips the resizing and rests where it would end.
    private var stage: Stage { reduceMotion ? .smallTrailing : animatedStage }

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
                .background(OnboardingPalette.widgetSurface, in: RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [OnboardingPalette.widgetHighlight, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                )
                .shadow(color: OnboardingPalette.widgetShadow, radius: 1.5)
                .offset(x: x, y: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A Spending widget on a home screen, showing this month's total")
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(duration: 0.55, bounce: 0.15)) { animatedStage = .medium }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.spring(duration: 0.55, bounce: 0.15)) { animatedStage = .smallTrailing }
        }
    }
}

// MARK: - Page 3: Pro pass

/// The four Pro features as a 2x2 grid of icon tiles, unfolding into a list of
/// labelled pills.
struct ProPassIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedUnfold = false

    private let features = ProFeature.allCases

    /// Reduce Motion shows the list without the unfolding.
    private var unfolded: Bool { reduceMotion || animatedUnfold }

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
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(500))
            animatedUnfold = true
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
                .accessibilityHidden(true)
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
        .foregroundStyle(Color.keaserPrimaryText)
        .frame(width: width, height: unfolded ? 66 : 67)
        .onboardingPill(cornerRadius: unfolded ? 24 : 28)
    }
}

// MARK: - Page 4: notifications

/// A lock screen that receives the weekly summary; once the user answers the
/// permission prompt it gives way to a large check (or a muted bell).
struct NotificationsIllustration: View {
    let step: NotificationStep
    let currencyCode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                                .transition(reduceMotion ? .opacity : .riseIn)
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            } else {
                Circle()
                    .fill(OnboardingPalette.answerCircle)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: step == .granted ? "checkmark" : "bell.slash.fill")
                            .font(.system(size: step == .granted ? 60 : 46, weight: .bold))
                            .foregroundStyle(Color.keaserPrimaryText)
                    )
                    .offset(y: 14)
                    .transition(reduceMotion ? .opacity : AnyTransition(.scale(0.6).combined(with: .opacity).combined(with: .blurReplace)))
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard step == .ask else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(duration: 0.55, bounce: 0.2)) { showsBanner = true }
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
                        .foregroundStyle(Color.keaserPrimaryText)
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
        .accessibilityElement(children: .combine)
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
    /// iOS 26 the material stand-in is duller than the glass these mimic, so
    /// it gets a lift.
    @ViewBuilder
    func illustrationGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            keaserGlass(in: shape)
        } else {
            background(OnboardingPalette.glassLift, in: shape).keaserGlass(in: shape)
        }
    }

    /// The pill of the sample rows and Pro features, with the faint lower rim
    /// the reference gives them.
    func onboardingPill(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(OnboardingPalette.pill, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [OnboardingPalette.pillRimTop, OnboardingPalette.pillRimBottom], startPoint: .top, endPoint: .bottom),
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
