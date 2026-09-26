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
    @State private var selectedPlan: ProProduct = .yearly
    @State private var legalDocument: LegalDocument?

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
            .safeAreaInset(edge: .bottom) { footer }
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
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
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
        return VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element) { index, feature in
                FeatureRow(feature: feature, isHighlighted: feature == highlighted)
                if index < ordered.count - 1 {
                    Rectangle()
                        .fill(Color.keaserSeparator)
                        .frame(height: 1)
                        .padding(.leading, 64)
                }
            }
        }
        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }

    private var plans: some View {
        HStack(spacing: 10) {
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
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
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
        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }

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

                HStack(spacing: 0) {
                    Button {
                        restore()
                    } label: {
                        if pro.isRestoring {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(pro.isRestoring || pro.purchasingPlan != nil)
                    Text("  \u{00B7}  ").foregroundStyle(Color.keaserTertiaryText)
                    Button("Terms") { legalDocument = .terms }
                    Text("  \u{00B7}  ").foregroundStyle(Color.keaserTertiaryText)
                    Button("Privacy") { legalDocument = .privacy }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.keaserSecondaryText)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KeaserMetrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            if #available(iOS 26.0, *) {
                // The system's scroll edge effect already softens the edge.
                EmptyView()
            } else {
                // Content fades out under the button instead of being cut off.
                LinearGradient(colors: [Color.keaserCard.opacity(0), Color.keaserCard], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                    .padding(.top, -20)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.2), value: pro.errorMessage)
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
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.black : Color.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isHighlighted ? Color.white : Color.white.opacity(0.08))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.system(size: 16, weight: .semibold))
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

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.keaserSecondaryText)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.white : Color.keaserTertiaryText)
                }
                price
                    .frame(height: 26, alignment: .leading)
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
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
