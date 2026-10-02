import KeaserKit
import StoreKit
import SwiftUI

/// Keaser Pro upgrade sheet. Present it as a sheet from wherever a Pro feature
/// is gated; it dismisses itself after a successful purchase or restore.
///
/// The features scroll under a panel pinned to the bottom that holds the
/// plans. Lifetime is offered first; "Show more plans" adds the
/// subscriptions above it.
struct PaywallView: View {
    /// The feature that triggered the paywall, if any, so it can lead with it.
    var highlighting: ProFeature? = nil

    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var selectedPlan: ProProduct = .lifetime
    @State private var showsAllPlans = PaywallView.startsWithAllPlans
    @State private var legalDocument: LegalDocument?
    /// The home indicator's inset, so the panel can sit as low as the
    /// reference's, inside the screen's rounded corners.
    @State private var bottomSafeArea: CGFloat = 0
    /// Where the plans panel meets the features at rest (`PaywallFold`), in
    /// the sheet's coordinates: each feature's text as it would be without
    /// `foldShift`, the panel's top, how far the list is scrolled, and how
    /// far the content is moved down so the panel's edge falls between two
    /// lines.
    @State private var featureLines: [Int: PaywallFold.Row] = [:]
    @State private var panelTop: CGFloat?
    @State private var topSafeArea: CGFloat = 0
    @State private var scrolledBy: CGFloat = 0
    @State private var foldShift: CGFloat = 0
    @State private var foldPlaced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    features
                        .padding(.top, 32)
                }
                .padding(.top, Self.topPadding + foldShift)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrolledBy = offset
            }
            .keaserReadableScrollContent(width: KeaserMetrics.narrowReadableWidth)
            .mask(alignment: .top) { underPanelMask }
            .keaserBottomBar { bottomBar }
            .coordinateSpace(.named(Self.sheetSpace))
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeArea = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topSafeArea = $0 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HeaderIconButton("xmark", label: "Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !pro.hasPurchased {
                        RestoreButton(isRestoring: pro.isRestoring, action: restore)
                            .disabled(pro.isRestoring || pro.purchasingPlan != nil)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $legalDocument) { LegalDocumentSheet(document: $0) }
        .task {
            if pro.productsState == .idle || pro.productsState == .unavailable {
                await pro.loadProducts()
            }
        }
        .onDisappear { pro.errorMessage = nil }
        .modifier(PaywallSheetChrome())
    }

    // MARK: Header and features

    /// The gap above the logo, measured from the reference (iOS 26). iOS 27
    /// starts scroll content 4pt lower under an inline navigation bar, so it
    /// takes those 4pt back there.
    private static var topPadding: CGFloat {
        if #available(iOS 27.0, *) { return 22 }
        return 26
    }

    private var header: some View {
        VStack(spacing: 0) {
            KeaserLogo(size: 106)
            HStack(spacing: 9) {
                Text("Keaser")
                    .keaserFont(34, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(Color.keaserPrimaryText)
                Text("PRO")
                    .keaserFont(20, weight: .bold, relativeTo: .title3)
                    .foregroundStyle(Color.keaserOnInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.keaserInk))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 35)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Keaser Pro")
            .accessibilityAddTraits(.isHeader)
            Text("Track your expenses like a pro. No limits and more features.")
                .font(.body)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    /// `highlighting`, or in DEBUG `-KeaserPaywallFeature <rawValue>` for
    /// screenshots of the paywall opened from a gated feature.
    private var highlighted: ProFeature? {
        #if DEBUG
        if highlighting == nil, let raw = DebugLaunch.string("KeaserPaywallFeature") {
            return ProFeature(rawValue: raw)
        }
        #endif
        return highlighting
    }

    private var features: some View {
        let ordered = ProFeature.ordered(highlighting: highlighted)
        return VStack(alignment: .leading, spacing: 21) {
            ForEach(Array(ordered.enumerated()), id: \.element) { index, feature in
                FeatureRow(symbol: feature.symbol, title: feature.title, detail: feature.detail, isHighlighted: feature == highlighted, foldShift: foldShift) {
                    measured($0, at: index)
                }
            }
            FeatureRow(symbol: "heart.fill", title: "Support indie development", detail: "Help build more features.", tint: .keaserDestructive, foldShift: foldShift) {
                measured($0, at: ordered.count)
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bottom panel

    /// The gap the reference leaves between the panel and the bottom of the
    /// screen.
    private static let panelGap: CGFloat = 17
    /// The band where content fades out: above the panel before iOS 26,
    /// just under the glass panel's top edge on iOS 26 and later.
    private static let panelFade: CGFloat = 24

    /// On iOS 26 and later the features scroll on under the glass panel,
    /// which would show them refracted through it, the red heart as a smear.
    /// They fade out over `panelFade` under its top edge instead, so the
    /// lines above it stay whole and the glass shows only the sheet. The
    /// mask reaches up under the header too (the scroll view's frame starts
    /// below it), so scrolled content still passes under the header's
    /// buttons into the system's soft edge instead of being cut off.
    @ViewBuilder
    private var underPanelMask: some View {
        if #available(iOS 26.0, *), let panelTop {
            VStack(spacing: 0) {
                Rectangle()
                    .frame(height: topSafeArea + max(0, panelTop))
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.panelFade)
            }
            .offset(y: -topSafeArea)
        } else {
            Rectangle()
                .padding(.top, -topSafeArea)
        }
    }
    /// The reference's Continue, a little taller than onboarding's.
    private static let continueHeight: CGFloat = 62

    private var bottomBar: some View {
        panel
            .padding(.horizontal, KeaserMetrics.screenPadding)
            .keaserReadableWidth(KeaserMetrics.narrowReadableWidth)
            // Reaches down past the safe area, to `panelGap` above the
            // screen's edge; the inset the scroll view sees still ends at
            // the panel's top.
            .padding(.bottom, Self.panelGap - bottomSafeArea)
            .background(alignment: .top) {
                if #available(iOS 26.0, *) {
                    // keaserBottomBar gives the bar the system's scroll edge
                    // effect, and `underPanelMask` keeps the features out
                    // of the glass.
                    EmptyView()
                } else {
                    // Content fades out in a fixed band above the panel,
                    // then the backdrop is opaque, so nothing shows through
                    // the gaps beside and under it.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Color.keaserCard.opacity(0), Color.keaserCard], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.panelFade)
                        Color.keaserCard
                    }
                    .padding(.top, -Self.panelFade)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            .animation(.snappy(duration: 0.2), value: pro.errorMessage)
            .animation(.snappy(duration: 0.2), value: pro.productsState)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if pro.hasPurchased {
                purchased
            } else {
                plans
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, pro.hasPurchased ? 14 : 6)
        .frame(maxWidth: .infinity)
        .modifier(PaywallPanelBackground(bottomRadius: bottomSafeArea > 0 ? 44 : 34))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.sheetSpace)).minY } action: { top in
            panelTop = top
            updateFold()
        }
        // The panel stays on screen whatever the text size, so it stops
        // growing before it would crowd out the features.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(visiblePlans) { kind in
                PlanRow(
                    kind: kind,
                    plan: pro.plan(kind),
                    subtitle: subtitle(for: kind),
                    regularPrice: regularPrice(for: kind),
                    isLoading: pro.productsState == .loading || pro.productsState == .idle,
                    isSelected: selectedPlan == kind
                ) {
                    withAnimation(.snappy(duration: 0.2)) { selectedPlan = kind }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }

        Button {
            withAnimation(.snappy(duration: 0.3)) {
                showsAllPlans.toggle()
                // Only Lifetime stays on screen; never buy a plan that is
                // no longer shown.
                if !showsAllPlans { selectedPlan = .lifetime }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: showsAllPlans ? "chevron.down" : "chevron.up")
                    .keaserFont(13, weight: .semibold, relativeTo: .subheadline)
                Text(showsAllPlans ? "Show fewer plans" : "Show more plans")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        status

        Button(action: upgrade) {
            if pro.purchasingPlan != nil {
                ProgressView().tint(Color.keaserOnInk)
            } else {
                Text("Continue")
            }
        }
        .buttonStyle(PrimaryButtonStyle(height: Self.continueHeight))
        .disabled(pro.plan(selectedPlan) == nil || pro.purchasingPlan != nil || pro.isRestoring)
        .padding(.top, 5)

        legalLinks
            .padding(.top, 6)
    }

    /// A purchase or restore problem, or a way to retry loading prices.
    @ViewBuilder
    private var status: some View {
        if let message = pro.errorMessage {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.keaserDestructive)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
                .transition(.opacity)
        } else if pro.productsState == .unavailable {
            HStack(spacing: 6) {
                Text("Prices could not be loaded.")
                    .foregroundStyle(Color.keaserSecondaryText)
                Button("Try Again") {
                    Task { await pro.loadProducts() }
                }
                .foregroundStyle(Color.keaserPrimaryText)
                .fontWeight(.semibold)
            }
            .font(.footnote)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    private var purchased: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                // A badge in a fixed spot above the text, not text itself.
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .accessibilityHidden(true)
                Text("You have Keaser Pro")
                    .font(.headline)
                    .foregroundStyle(Color.keaserPrimaryText)
                Text("Every feature is unlocked. Thank you for supporting an independent app.")
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: Self.continueHeight))
        }
    }

    /// Terms and Privacy side by side, or stacked when they no longer fit.
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 13) {
                termsLink
                privacyLink
            }
            VStack(spacing: 0) {
                termsLink
                privacyLink
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.keaserSecondaryText.opacity(0.8))
        .buttonStyle(.plain)
    }

    private var termsLink: some View {
        Button { legalDocument = .terms } label: { Text("Terms & Conditions").legalLinkTarget() }
    }

    private var privacyLink: some View {
        Button { legalDocument = .privacy } label: { Text("Privacy Policy").legalLinkTarget() }
    }

    // MARK: Plans

    private var visiblePlans: [ProProduct] {
        showsAllPlans ? ProProduct.allCases : [.lifetime]
    }

    private func subtitle(for kind: ProProduct) -> String? {
        switch kind {
        case .monthly:
            return nil
        case .yearly:
            guard let monthly = pro.plan(.monthly), let yearly = pro.plan(.yearly) else { return nil }
            return ProPricing.annualSubtitle(monthly: monthly.price, yearly: yearly.price)
        case .lifetime:
            return ProPricing.lifetimeSubtitle
        }
    }

    private func regularPrice(for kind: ProProduct) -> String? {
        guard kind == .lifetime, let plan = pro.plan(kind) else { return nil }
        return ProPricing.regularLifetimePrice(for: plan.price).map(plan.formatted)
    }

    #if DEBUG
    /// `-KeaserPaywallPlans all` opens with every plan showing, for
    /// screenshots.
    private static var startsWithAllPlans: Bool { DebugLaunch.string("KeaserPaywallPlans") == "all" }
    #else
    private static let startsWithAllPlans = false
    #endif

    // MARK: Where the panel meets the features

    fileprivate nonisolated static let sheetSpace = "PaywallSheet"
    /// The most the content moves to keep the panel's edge off a line,
    /// enough to clear a two-line detail at the default text size; past
    /// that it stays where it is.
    private static let foldLimit: CGFloat = 20

    private func measured(_ row: PaywallFold.Row, at index: Int) {
        guard featureLines[index] != row else { return }
        featureLines[index] = row
        updateFold()
    }

    /// Moves the content so that, at rest, the panel's top edge falls between
    /// two lines of the feature list rather than through one, as it does in
    /// the reference. The panel's place in the list depends on the sheet's
    /// height and the panel's own, so it is measured, not fixed. Once every
    /// plan is showing, the taller panel covers more of the list, as in the
    /// reference, and the content stays put.
    private func updateFold() {
        guard !showsAllPlans, abs(scrolledBy) < 0.5, let panelTop, featureLines.count == ProFeature.allCases.count + 1 else { return }
        let shift = CGFloat(PaywallFold.shift(panelTop: Double(panelTop), rows: Array(featureLines.values), limit: Double(Self.foldLimit)))
        // The first placement happens as the sheet comes up; later ones
        // (prices failing to load, an error under the plans) glide with the
        // panel.
        let glides = foldPlaced
        foldPlaced = true
        guard abs(shift - foldShift) > 0.25 else { return }
        var transaction = Transaction(animation: glides ? .snappy(duration: 0.2) : nil)
        transaction.disablesAnimations = !glides
        withTransaction(transaction) { foldShift = shift }
    }

    // MARK: Actions

    private func upgrade() {
        guard let plan = pro.plan(selectedPlan) else { return }
        Task {
            if await pro.purchase(plan, using: purchase) { dismiss() }
        }
    }

    private func restore() {
        Task {
            if await pro.restore() { dismiss() }
        }
    }
}

/// One line of the feature list: an icon, a title and a grey line under it.
/// The feature that opened the paywall sits on a faint card.
private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = .keaserPrimaryText
    var isHighlighted = false
    /// The paywall's `foldShift` in this layout, taken back out of what
    /// `onLines` reports so moving the content never feeds back into it.
    var foldShift: CGFloat = 0
    /// Reports the title's and the detail's line boxes in the paywall's
    /// sheet, for where the plans panel meets the list.
    var onLines: (PaywallFold.Row) -> Void = { _ in }

    @State private var titleLines: ClosedRange<Double>?
    @State private var detailLines: ClosedRange<Double>?

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 21) {
            Image(systemName: symbol)
                .keaserFont(22, relativeTo: .body)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .onGeometryChange(for: ClosedRange<Double>.self) { [foldShift] in Self.lines($0, less: foldShift) } action: { titleLines = $0; report() }
                // Subheadline, as measured in the reference (15pt on 20pt
                // lines), so "Quick access from your home screen." fits on
                // one line.
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .onGeometryChange(for: ClosedRange<Double>.self) { [foldShift] in Self.lines($0, less: foldShift) } action: { detailLines = $0; report() }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // The highlight card spans the column, whatever the text's width.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.keaserInk.opacity(0.06))
                    .padding(.horizontal, -14)
                    .padding(.vertical, -9)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private nonisolated static func lines(_ proxy: GeometryProxy, less shift: CGFloat) -> ClosedRange<Double> {
        let frame = proxy.frame(in: .named(PaywallView.sheetSpace))
        return Double(frame.minY - shift)...Double(max(frame.minY, frame.maxY) - shift)
    }

    private func report() {
        guard let titleLines, let detailLines else { return }
        onLines(PaywallFold.Row(title: titleLines, detail: detailLines))
    }
}

/// A selectable plan: a radio, its name and price, or a loading or
/// unavailable state in place of the price.
private struct PlanRow: View {
    let kind: ProProduct
    let plan: ProStore.Plan?
    let subtitle: String?
    let regularPrice: String?
    let isLoading: Bool
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                radio
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .keaserFont(17, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(Color.keaserPrimaryText)
                        if let subtitle {
                            // Footnote-sized and on one line, as in the
                            // reference, so the prices keep their room.
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(Color.keaserSecondaryText)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    price
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 17)
            .padding(.vertical, 19)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? Color.paywallSelectedPlan : Color.paywallPlan, in: Self.shape)
            .overlay {
                Self.shape
                    .strokeBorder(Color.keaserInk, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var radio: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.keaserOnInk, Color.keaserInk)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Color.keaserMutedIcon)
            }
        }
        .keaserFont(20, relativeTo: .headline)
    }

    @ViewBuilder
    private var price: some View {
        if let plan {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let regularPrice {
                    Text(regularPrice)
                        .font(.footnote)
                        .strikethrough()
                        .foregroundStyle(Color.keaserSecondaryText)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(plan.displayPrice)
                        .keaserFont(17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(Color.keaserPrimaryText)
                    if let suffix = kind.priceSuffix {
                        Text(suffix)
                            .font(.body)
                            .foregroundStyle(Color.keaserSecondaryText)
                    }
                }
            }
            .lineLimit(1)
            .fixedSize()
        } else if isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            // As readable as the plan's subtitle on the selected card.
            Text("Unavailable")
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
        }
    }

    /// "Annual, 47% off monthly plan, $24.99 per year".
    private var spokenLabel: String {
        var parts = [kind.title]
        if let subtitle { parts.append(subtitle) }
        if let plan {
            switch kind {
            case .monthly: parts.append("\(plan.displayPrice) per month")
            case .yearly: parts.append("\(plan.displayPrice) per year")
            case .lifetime: parts.append(plan.displayPrice)
            }
            if let regularPrice { parts.append("regularly \(regularPrice)") }
        } else {
            parts.append(isLoading ? "Loading price" : "Unavailable")
        }
        return parts.joined(separator: ", ")
    }
}

/// "Restore" in a glass capsule. iOS 26 toolbars draw the glass themselves.
private struct RestoreButton: View {
    let isRestoring: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { label }
        } else {
            Button(action: action) {
                // 44pt tall with the style's 8pt vertical padding.
                label.frame(minHeight: 28)
            }
            .keaserGlassButtonStyle()
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRestoring {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Restoring purchases")
        } else {
            Text("Restore")
                .accessibilityLabel("Restore Purchases")
        }
    }
}

/// The plans' panel: Liquid Glass on iOS 26; before that an opaque look-alike,
/// since the backdrop behind it is opaque too.
private struct PaywallPanelBackground: ViewModifier {
    let bottomRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 34,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 34,
            style: .continuous
        )
        if #available(iOS 26.0, *) {
            content.keaserGlass(in: shape)
        } else {
            content.background {
                shape
                    .fill(Color.paywallPanel)
                    .overlay(shape.stroke(Color.keaserSeparator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 4)
            }
        }
    }
}

/// White in light mode like the reference, rather than the grouped grey of
/// other sheets; the same charcoal as other sheets in dark mode.
private struct PaywallSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .presentationBackground(Color.keaserCard)
                .presentationCornerRadius(32)
        }
    }
}

private extension Color {
    /// The plans' panel before iOS 26, measured from the reference.
    static let paywallPanel = Color(light: .init(white: 0.97), dark: .init(red: 47 / 255, green: 46 / 255, blue: 49 / 255))
    /// A plan card that is not selected.
    static let paywallPlan = Color(light: .black.opacity(0.03), dark: .white.opacity(0.06))
    /// The selected plan card, under its ink outline.
    static let paywallSelectedPlan = Color(light: .black.opacity(0.12), dark: .white.opacity(0.12))
}

private extension View {
    /// At least 44pt tall and wide to tap, whatever the text size.
    func legalLinkTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

