import SwiftUI

// Liquid Glass on iOS 26 and later, a close material look-alike on iOS 18.
// Always go through these helpers instead of calling `glassEffect` directly,
// so the deployment target can stay at iOS 18.

extension View {
    /// Glass behind this view, clipped to `shape`. `tint` colours the glass
    /// (pass it with its opacity); before iOS 26 it is laid over the material.
    @ViewBuilder
    func keaserGlass(in shape: some Shape, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background(tint ?? .clear, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.keaserInk.opacity(0.10), lineWidth: 0.5))
        }
    }

    /// Capsule glass, the shape of every toolbar control in the reference.
    func keaserGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        keaserGlass(in: Capsule(), interactive: interactive, tint: tint)
    }

    /// The system glass button style ("Cancel", "Save", the round close
    /// button), or a translucent capsule before iOS 26.
    @ViewBuilder
    func keaserGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(FallbackGlassButtonStyle())
        }
    }
}

/// Groups glass shapes so they blend and morph together on iOS 26.
struct KeaserGlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct FallbackGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Color.keaserPrimaryText : Color.keaserTertiaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.keaserInk.opacity(0.10), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension View {
    /// Sheet chrome: on iOS 26 the system's floating glass sheet is left
    /// alone; before that, a charcoal background with large corners.
    @ViewBuilder
    func keaserSheetChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .presentationBackground(Color.keaserSheetBackground)
                .presentationCornerRadius(32)
        }
    }

    /// The round glass icon button used in sheet headers (close, back,
    /// confirm, add).
    func keaserCircleButton() -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .keaserGlass(in: Circle(), interactive: true)
    }
}

extension View {
    /// Pins `content` under scrolling content, like a toolbar. On iOS 26 it
    /// is a safe area bar, so the system's scroll edge effect softens what
    /// scrolls beneath it; plain `safeAreaInset` content gets no such effect.
    /// Before iOS 26, give `content` its own backing.
    @ViewBuilder
    func keaserBottomBar(@ViewBuilder _ content: () -> some View) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, content: content)
        } else {
            self.safeAreaInset(edge: .bottom, content: content)
        }
    }

    /// For a scroll view that runs under a bar at the bottom (the tab bar,
    /// Search's bar): on iOS 26 and later what scrolls beneath fades and
    /// blurs into the bar, as under any system bar, instead of showing
    /// sharp beside the glass.
    @ViewBuilder
    func keaserSoftBottomEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }
}
