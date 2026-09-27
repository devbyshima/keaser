import SwiftUI

/// Keaser is dark-only and monochrome: black canvas, charcoal cards, white
/// type, white as the only accent. Every colour in the app comes from here.
extension Color {
    /// Screen background. Pure black, as in the reference.
    static let keaserBackground = Color.black
    /// Cards, list rows, the chart panel. iOS dark secondary grouped.
    static let keaserCard = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    /// Controls sitting on a card (icon tiles, date pill, text fields).
    static let keaserCardRaised = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    /// Hairlines between rows.
    static let keaserSeparator = Color.white.opacity(0.12)
    static let keaserPrimaryText = Color.white
    static let keaserSecondaryText = Color(white: 0.56)
    static let keaserTertiaryText = Color(white: 0.36)
    static let keaserDestructive = Color(red: 1, green: 0.27, blue: 0.23)
    /// The chart's long-press callout: darker than the card it floats over.
    static let keaserCallout = Color(white: 0.045)
    /// Large empty-state symbols ("No Expenses") and other muted icons.
    static let keaserMutedIcon = Color(white: 0.62)
    /// The close (xmark) glyph: grey and lighter in weight than the other
    /// header glyphs (back, add, confirm), as in the reference.
    static let keaserCloseGlyph = Color(white: 0.56)

    /// Card fill for content on a sheet. A light veil rather than a solid
    /// colour, so it reads the same on the iOS 18 charcoal sheet and on iOS 26
    /// glass.
    static let keaserSheetCard = Color.white.opacity(0.055)
    /// The barely visible tile behind row symbols and monograms on a sheet.
    static let keaserSheetTile = Color.white.opacity(0.014)
    /// Symbol tiles and text fields sitting directly on a sheet.
    static let keaserSheetField = Color.white.opacity(0.03)
}

enum KeaserMetrics {
    static let screenPadding: CGFloat = 16
    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 24
    static let primaryButtonHeight: CGFloat = 58
}

extension Font {
    // Prefer text styles (.body, .headline...). When a design needs an exact
    // size, use `keaserFont(_:weight:)` instead of Font.system(size:), so the
    // size still follows Dynamic Type.

    /// Onboarding and sheet page titles: Title 1 semibold (28pt at the
    /// default text size).
    static let keaserTitle = Font.title.weight(.semibold)
}

extension View {
    /// An exact design size that still follows Dynamic Type: `size` at the
    /// default text size, scaled like `style` at every other size. Use this
    /// instead of `.font(.system(size:))` for any text.
    func keaserFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: Font.TextStyle? = nil
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, style: style ?? .keaserNearest(to: size)))
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension Font.TextStyle {
    /// The text style whose default size is closest to `size`, so a custom
    /// size scales at the same rate as the text around it.
    static func keaserNearest(to size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}
