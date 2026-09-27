import SwiftUI

// Built with the iOS 27 SDK, Keaser can be resized freely: in a window on
// iPad and in iPhone Mirroring on the Mac. Its screens are drawn for a
// phone's width, so on anything wider their content keeps to a centred
// column instead of stretching edge to edge. At phone widths (and in a
// sheet no wider than the column) these change nothing.

extension KeaserMetrics {
    /// The widest column of content: Home, Settings, the sheets. A phone's
    /// width fits well inside it.
    static let readableWidth: CGFloat = 600
    /// Onboarding and the paywall, whose pictures and full-width buttons
    /// are drawn for a phone.
    static let narrowReadableWidth: CGFloat = 520
}

extension View {
    /// Keeps this view to a centred column at most `width` wide (including
    /// its own padding), with `alignment` inside the column.
    func keaserReadableWidth(_ width: CGFloat = KeaserMetrics.readableWidth, alignment: Alignment = .center) -> some View {
        frame(maxWidth: width, alignment: alignment)
            .frame(maxWidth: .infinity)
    }

    /// For a scroll view or list: widens its horizontal content margins so
    /// the content keeps to a centred column at most `width` wide, while the
    /// scroll view itself (where a swipe scrolls it, its indicators, its
    /// edge effects) still fills the window. `base` is the margin the
    /// content has at phone widths.
    func keaserReadableScrollContent(base: CGFloat = 0, width: CGFloat = KeaserMetrics.readableWidth) -> some View {
        modifier(ReadableScrollMargins(base: base, width: width))
    }

    /// For a row of controls along the top of a screen: in a window on iPad
    /// (iOS 26 and later) its leading end moves past the window's close and
    /// resize controls when it reaches that corner, and the row gives up
    /// that much width. Elsewhere, and before iOS 26, nothing changes.
    @ViewBuilder
    func keaserClearsWindowControls() -> some View {
        if #available(iOS 26.0, *) {
            containerCornerOffset(.leading, sizeToFit: true)
        } else {
            self
        }
    }
}

private struct ReadableScrollMargins: ViewModifier {
    let base: CGFloat
    let width: CGFloat

    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, base + max(0, (containerWidth - width) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
    }
}
