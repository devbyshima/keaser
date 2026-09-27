import SwiftUI

/// The Keaser mark, drawn in code so it stays sharp at every size: a white
/// rounded tile with a "K" cut out of it. `size` is the tile's side.
///
/// The K is cut out rather than painted black, so it shows whatever the logo
/// sits on (the black canvas, a charcoal sheet).
struct KeaserLogo: View {
    var size: CGFloat = 96
    /// Ink by default: white in dark mode, black in light mode. The app
    /// icon picture passes white, since the icon itself never changes.
    var color: Color = .keaserInk

    var body: some View {
        KeaserMark()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel("Keaser")
    }
}

/// The mark's outline. The app icon (scripts/make_icon.swift) draws the same
/// shape from the same numbers; change both together.
struct KeaserMark: Shape {
    // Fractions of the tile's side.
    private static let cornerRadius: CGFloat = 0.27
    private static let stroke: CGFloat = 0.14
    private static let stemOrigin = CGPoint(x: 0.245, y: 0.235)
    private static let stemHeight: CGFloat = 0.53
    private static let armStart = CGPoint(x: 0.33, y: 0.575)
    private static let armEnd = CGPoint(x: 0.70, y: 0.265)
    // The leg springs from the arm, not the stem: that junction is what makes
    // it Keaser's K rather than a typeface's.
    private static let legStart = CGPoint(x: 0.49, y: 0.44)
    private static let legEnd = CGPoint(x: 0.70, y: 0.735)

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }

        let tile = RoundedRectangle(cornerRadius: Self.cornerRadius * side, style: .continuous)
            .path(in: CGRect(origin: origin, size: CGSize(width: side, height: side)))
        let width = Self.stroke * side
        let stem = Path(
            roundedRect: CGRect(origin: point(Self.stemOrigin), size: CGSize(width: width, height: Self.stemHeight * side)),
            cornerRadius: width / 2
        )
        var strokes = Path()
        strokes.move(to: point(Self.armStart))
        strokes.addLine(to: point(Self.armEnd))
        strokes.move(to: point(Self.legStart))
        strokes.addLine(to: point(Self.legEnd))
        let letter = stem.union(strokes.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)))
        return tile.subtracting(letter)
    }
}

/// The app icon as a view: the mark on black inside the icon's rounded
/// square, for places that picture the icon (the notification preview).
struct KeaserAppIcon: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color.black)
            .overlay(KeaserLogo(size: size * 0.6, color: .white))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 32) {
        KeaserLogo(size: 140)
        HStack(spacing: 20) {
            KeaserLogo(size: 30)
            KeaserAppIcon(size: 60)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
