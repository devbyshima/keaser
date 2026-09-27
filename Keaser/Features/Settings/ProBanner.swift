import SwiftUI

/// The Keaser Pro card at the top of Settings: a slow night-sky gradient with
/// drifting stars, the pass status and an Upgrade button. At accessibility
/// sizes the button moves under the text so neither is squeezed; the small
/// seal shown after a purchase stays beside it.
///
/// The card is a night sky in both appearances, as in the reference, so it
/// always draws with the dark palette: white text and a white Upgrade button.
struct ProBanner: View {
    let subtitle: String
    let showsUpgrade: Bool
    let upgrade: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let stacks = isLarge && showsUpgrade
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 1) {
                Text("Keaser Pro")
                    .keaserFont(22, weight: .semibold, relativeTo: .title2)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .keaserFont(16, relativeTo: .callout)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .lineLimit(isLarge ? 3 : 1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            if !stacks { Spacer(minLength: 8) }
            if showsUpgrade {
                Button("Upgrade", action: upgrade)
                    .buttonStyle(.keaserCapsule(height: 34, horizontalPadding: 13))
            } else {
                // A badge in a fixed spot on the card, not text.
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, isLarge ? 18 : 0)
        .frame(maxWidth: .infinity, minHeight: 97, alignment: .leading)
        .background(StarfieldBackground())
        .clipShape(RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .environment(\.colorScheme, .dark)
    }
}

/// A near-black sky whose glow drifts between midnight blue and violet, with
/// a fixed, seeded star field that slides and twinkles. Stands still when
/// Reduce Motion is on.
struct StarfieldBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stars = Star.field(count: 260, seed: 0x5EED_4B45)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.drawSky(in: &context, size: size, time: t)
                Self.drawStars(in: &context, size: size, time: t)
            }
        }
        .accessibilityHidden(true)
    }

    private static func drawSky(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(Color(red: 0.012, green: 0.02, blue: 0.045)))

        // Hue swings from midnight blue to violet and back every ~24s; the
        // glow's centre wanders across the card on a slower loop.
        let swing = (sin(time * 2 * .pi / 24) + 1) / 2
        let glow = Color(
            red: 0.06 + 0.10 * swing,
            green: 0.08 - 0.03 * swing,
            blue: 0.19 + 0.02 * swing
        )
        let wander = time * 2 * .pi / 37
        let center = CGPoint(
            x: size.width * (0.5 + 0.32 * sin(wander)),
            y: size.height * (0.5 + 0.25 * cos(wander * 0.7))
        )
        let radius = max(size.width, size.height) * 0.55
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [glow, glow.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private static func drawStars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        for star in stars {
            // Slow sideways drift, wrapping around the card.
            let x = (star.x * size.width + time * star.drift).truncatingRemainder(dividingBy: size.width + 4) - 2
            let y = star.y * size.height
            let twinkle = 0.55 + 0.45 * sin(time * star.twinkleSpeed + star.phase)
            let opacity = star.brightness * twinkle
            if star.isSparkle {
                context.fill(sparkle(at: CGPoint(x: x, y: y), radius: star.size), with: .color(.white.opacity(opacity)))
            } else {
                let r = star.size / 2
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: star.size, height: star.size)), with: .color(.white.opacity(opacity)))
            }
        }
    }

    /// A four-pointed star, like the brighter ones in the reference.
    private static func sparkle(at p: CGPoint, radius: CGFloat) -> Path {
        let waist = radius * 0.28
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - radius))
        path.addQuadCurve(to: CGPoint(x: p.x + radius, y: p.y), control: CGPoint(x: p.x + waist, y: p.y - waist))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + radius), control: CGPoint(x: p.x + waist, y: p.y + waist))
        path.addQuadCurve(to: CGPoint(x: p.x - radius, y: p.y), control: CGPoint(x: p.x - waist, y: p.y + waist))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - radius), control: CGPoint(x: p.x - waist, y: p.y - waist))
        return path
    }

    private struct Star {
        var x: Double
        var y: Double
        var size: Double
        var brightness: Double
        var drift: Double
        var twinkleSpeed: Double
        var phase: Double
        var isSparkle: Bool

        /// Deterministic, so the sky is the same on every launch and in every
        /// screenshot.
        static func field(count: Int, seed: UInt64) -> [Star] {
            var state = seed
            func next() -> Double {
                // SplitMix64, reduced to [0, 1).
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
            }
            return (0..<count).map { _ in
                let sparkle = next() < 0.08
                return Star(
                    x: next(),
                    y: next(),
                    // Sparkles: radius of the four points. Dots: diameter.
                    size: sparkle ? 1.4 + next() * 0.8 : 0.6 + next() * 0.9,
                    brightness: 0.5 + next() * 0.5,
                    drift: 1.5 + next() * 3,
                    twinkleSpeed: 0.6 + next() * 1.8,
                    phase: next() * 2 * .pi,
                    isSparkle: sparkle
                )
            }
        }
    }
}
