import SwiftUI

// The pieces every sheet and card in Keaser is built from. Feature folders
// use these rather than their own copies, so a sheet header, a round glass
// button or a hairline looks and behaves the same everywhere.

/// A round glass icon button: close, back, add, confirm.
///
/// `xmark` is drawn grey and medium weight, like the reference; every other
/// glyph is white and semibold.
struct KeaserCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    private var isClose: Bool { symbol == "xmark" }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: isClose ? .medium : .semibold))
                .foregroundStyle(isClose ? Color.keaserCloseGlyph : Color.keaserPrimaryText)
                .keaserCircleButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        // A checkmark glyph would otherwise make VoiceOver say "selected".
        .accessibilityRemoveTraits(.isSelected)
    }
}

/// The header drawn at the top of a sheet: a control on each side and a
/// centred title. The title stays centred on the sheet while it fits between
/// the side controls, and wraps or shrinks (never overlaps them) at large
/// text sizes.
struct KeaserSheetHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        CenteredTitleLayout(spacing: 8) {
            // Wrapped so an empty side (EmptyView) still counts as one
            // subview; the layout expects exactly three.
            HStack(spacing: 0) { leading }
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.keaserPrimaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) { trailing }
        }
        .frame(minHeight: 44)
    }
}

extension KeaserSheetHeader where Trailing == EmptyView {
    init(title: String, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, leading: leading) { EmptyView() }
    }
}

extension KeaserSheetHeader where Leading == EmptyView, Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() } trailing: { EmptyView() }
    }
}

/// Leading view at the start, trailing view at the end, and the middle view
/// centred in the whole width, given only the room left between equal
/// margins so it cannot run under either side.
private struct CenteredTitleLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let sides = sideSizes(subviews)
        let width = proposal.width ?? (sides.leading.width + sides.trailing.width + 200)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: titleWidth(width, sides), height: nil))
        return CGSize(width: width, height: max(sides.leading.height, sides.trailing.height, title.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sides = sideSizes(subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        let width = titleWidth(bounds.width, sides)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(width: width, height: nil))
    }

    private func sideSizes(_ subviews: Subviews) -> (leading: CGSize, trailing: CGSize) {
        (subviews[0].sizeThatFits(.unspecified), subviews[2].sizeThatFits(.unspecified))
    }

    private func titleWidth(_ total: CGFloat, _ sides: (leading: CGSize, trailing: CGSize)) -> CGFloat {
        let margin = max(sides.leading.width, sides.trailing.width, 44) + spacing
        return max(0, total - margin * 2)
    }
}

/// A charcoal card holding rows. Rows inside are separated with
/// `KeaserRowSeparator`.
struct KeaserCard<Content: View>: View {
    var fill: Color = .keaserCardRaised
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(fill, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }
}

/// The hairline between rows of a card, starting where the row text starts.
struct KeaserRowSeparator: View {
    var leading: CGFloat = 16
    var trailing: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Color.keaserSeparator)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .accessibilityHidden(true)
    }
}

/// A tappable card row that highlights while pressed, like a list cell.
struct HighlightRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The small white capsule ("Add Account", "Upgrade"). Drawn at `height`
/// but always at least 44pt tall to tap.
struct KeaserCapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(Capsule().fill(Color.white))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KeaserCapsuleButtonStyle {
    static var keaserCapsule: KeaserCapsuleButtonStyle { KeaserCapsuleButtonStyle() }
    static func keaserCapsule(height: CGFloat, horizontalPadding: CGFloat = 12) -> KeaserCapsuleButtonStyle {
        KeaserCapsuleButtonStyle(height: height, horizontalPadding: horizontalPadding)
    }
}
