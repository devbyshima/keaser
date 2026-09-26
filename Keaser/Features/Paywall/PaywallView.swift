import KeaserKit
import StoreKit
import SwiftUI

/// Keaser Pro upgrade sheet. Present it as a sheet from wherever a Pro feature
/// is gated; it dismisses itself after a successful purchase or restore.
struct PaywallView: View {
    /// The feature that triggered the paywall, if any, so it can lead with it.
    var highlighting: ProFeature? = nil

    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPlan: ProProduct = .yearly
    @State private var legalDocument: LegalDocument?
    /// The legal links' text height: one footnote line, scaled.
    @ScaledMetric(relativeTo: .footnote) private var linkTextHeight: CGFloat = UIFont.preferredFont(
        forTextStyle: .footnote,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
    ).lineHeight

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    features
                        .padding(.top, 24)
                    if pro.hasPurchased {
                        thanks
                            .padding(.top, 16)
                    } else {
                        plans
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, KeaserMetrics.screenPadding)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .keaserBottomBar { footer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HeaderIconButton("xmark", label: "Close") { dismiss() }
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
        .keaserSheetChrome()
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            KeaserLogo(size: 60)
                .padding(.bottom, 6)
            Text("Keaser Pro")
                .keaserFont(28, weight: .bold, relativeTo: .title)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(ProStatusText.subtitle(trialDaysRemaining: pro.trialDaysRemaining, hasPurchased: pro.hasPurchased))
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
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
        return KeaserCard(fill: .keaserSheetCard) {
            ForEach(Array(ordered.enumerated()), id: \.element) { index, feature in
                FeatureRow(feature: feature, isHighlighted: feature == highlighted)
                if index < ordered.count - 1 {
                    // Under the text, past the 36pt tile.
                    KeaserRowSeparator(leading: 64)
                }
            }
        }
    }

    private var plans: some View {
        // Side by side, or one above the other once the prices would no
        // longer fit.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ForEach(ProProduct.allCases) { kind in
                PlanCard(
                    kind: kind,
                    plan: pro.plan(kind),
                    state: pro.productsState,
                    isSelected: selectedPlan == kind
                ) {
                    withAnimation(.snappy(duration: 0.2)) { selectedPlan = kind }
                }
            }
        }
        // Both cards as tall as the taller one.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var thanks: some View {
        KeaserCard(fill: .keaserSheetCard) {
            thanksContent
        }
        .accessibilityElement(children: .combine)
    }

    private var thanksContent: some View {
        VStack(spacing: 8) {
            // A badge in a fixed spot above the text, not text itself.
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("You have Keaser Pro")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Every feature is unlocked. Thank you for supporting an independent app.")
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    /// The band above the footer where content fades out (before iOS 26).
    private static let footerFade: CGFloat = 24

    /// How far the legal links' 44pt tap targets reach above and below their
    /// text. The footer's spacing gives it back, so the text sits where the
    /// design puts it.
    private var linkSlop: CGFloat { max(0, (44 - linkTextHeight) / 2) }

    private var footer: some View {
        VStack(spacing: 12) {
            if let message = pro.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.keaserDestructive)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if pro.productsState == .unavailable && !pro.hasPurchased {
                HStack(spacing: 6) {
                    Text("Prices could not be loaded.")
                        .foregroundStyle(Color.keaserSecondaryText)
                    Button("Try Again") {
                        Task { await pro.loadProducts() }
                    }
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                }
                .font(.footnote)
                .transition(.opacity)
            }
            if pro.hasPurchased {
                Button("Done") { dismiss() }
                    .buttonStyle(.keaserPrimary)
            } else {
                Button {
                    upgrade()
                } label: {
                    if pro.purchasingPlan != nil {
                        ProgressView().tint(.black)
                    } else {
                        Text("Upgrade")
                    }
                }
                .buttonStyle(.keaserPrimary)
                .disabled(pro.plan(selectedPlan) == nil || pro.purchasingPlan != nil || pro.isRestoring)

                legalLinks
                    .padding(.top, -linkSlop)
            }
        }
        .padding(.horizontal, KeaserMetrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, pro.hasPurchased ? 8 : 8 - linkSlop)
        .background(alignment: .top) {
            if #available(iOS 26.0, *) {
                // keaserBottomBar gives the bar the system's scroll edge
                // effect.
                EmptyView()
            } else {
                // Content fades out in a fixed band above the footer, then
                // the footer is opaque, so nothing scrolls behind its text
                // however tall a large text size makes it.
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.keaserCard.opacity(0), Color.keaserCard], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.footerFade)
                    Color.keaserCard
                }
                .padding(.top, -Self.footerFade)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.2), value: pro.errorMessage)
    }

    /// Restore Purchases, Terms and Privacy on one line, or stacked when
    /// they no longer fit.
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                restoreLink
                linkSeparator
                termsLink
                linkSeparator
                privacyLink
            }
            VStack(spacing: 0) {
                restoreLink
                HStack(spacing: 24) {
                    termsLink
                    privacyLink
                }
            }
            VStack(spacing: 0) {
                restoreLink
                termsLink
                privacyLink
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.keaserSecondaryText)
        .buttonStyle(.plain)
    }

    private var linkSeparator: some View {
        Text("  \u{00B7}  ")
            .foregroundStyle(Color.keaserTertiaryText)
            .accessibilityHidden(true)
    }

    private var restoreLink: some View {
        Button {
            restore()
        } label: {
            Group {
                if pro.isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restore Purchases")
                }
            }
            .legalLinkTarget()
        }
        .disabled(pro.isRestoring || pro.purchasingPlan != nil)
    }

    private var termsLink: some View {
        Button { legalDocument = .terms } label: { Text("Terms").legalLinkTarget() }
    }

    private var privacyLink: some View {
        Button { legalDocument = .privacy } label: { Text("Privacy").legalLinkTarget() }
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

/// One Pro feature; the one that opened the paywall gets a white tile.
private struct FeatureRow: View {
    let feature: ProFeature
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            // A glyph in a fixed tile, sized with the tile.
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.black : Color.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isHighlighted ? Color.white : Color.white.opacity(0.08))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .keaserFont(16, weight: .semibold, relativeTo: .callout)
                    .foregroundStyle(.white)
                Text(feature.detail)
                    .font(.footnote)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// A selectable plan with its price, or a loading / unavailable state.
private struct PlanCard: View {
    let kind: ProProduct
    let plan: ProStore.Plan?
    let state: ProStore.ProductsState
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(kind.title)
                        .keaserFont(15, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                    Spacer(minLength: 4)
                    // The selected trait says this; the radio is only drawn.
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.white : Color.keaserTertiaryText)
                        .accessibilityHidden(true)
                }
                price
                    .frame(minHeight: 26, alignment: .leading)
                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KeaserMetrics.rowRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0.06), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KeaserMetrics.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var price: some View {
        if let plan {
            Text(plan.priceLabel)
                .keaserFont(20, weight: .bold, relativeTo: .title3)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        } else if state == .loading || state == .idle {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Unavailable")
                .font(.subheadline)
                .foregroundStyle(Color.keaserTertiaryText)
        }
    }
}

private extension View {
    /// At least 44pt tall and wide to tap, whatever the text size.
    func legalLinkTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}
