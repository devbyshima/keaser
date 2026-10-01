import SwiftUI
import UIKit

/// Keaser is monochrome and follows the system appearance. Dark: black
/// canvas, charcoal cards, white ink. Light: pale grey canvas, white cards,
/// black ink. "Ink" is the one accent: chart bars, the add button, primary
/// buttons. Every colour in the app comes from here, and each one resolves
/// per appearance, so nothing else needs to know which mode is on.
extension Color {
    /// Screen background: pure black, or the reference's pale grey.
    static let keaserBackground = Color(light: .init(white: 245 / 255), dark: .black)
    /// Cards, list rows, the chart panel.
    static let keaserCard = Color(light: .white, dark: .init(red: 28 / 255, green: 28 / 255, blue: 30 / 255))
    /// Controls sitting on a card (icon tiles, date pill, text fields).
    static let keaserCardRaised = Color(light: .init(white: 242 / 255), dark: .init(red: 44 / 255, green: 44 / 255, blue: 46 / 255))
    /// Hairlines between rows.
    static let keaserSeparator = Color(light: .black.opacity(0.1), dark: .white.opacity(0.12))
    /// Hairlines between the rows of a settings list. The reference draws
    /// them fainter on its dark cards than the ones in sheets such as New
    /// Expense; light mode is the same as `keaserSeparator`.
    static let keaserListSeparator = Color(light: .black.opacity(0.1), dark: .white.opacity(0.08))
    static let keaserPrimaryText = Color(light: .black, dark: .white)
    static let keaserSecondaryText = Color(light: .init(white: 0.45), dark: .init(white: 0.56))
    static let keaserTertiaryText = Color(light: .init(white: 0.68), dark: .init(white: 0.36))
    /// Section titles and the small print under settings cards: the cool
    /// grey the reference uses there, a little lighter than
    /// `keaserSecondaryText` in light mode. Row values stay secondary.
    static let keaserCaptionText = Color(
        light: .init(red: 122 / 255, green: 121 / 255, blue: 128 / 255),
        dark: .init(red: 142 / 255, green: 141 / 255, blue: 148 / 255)
    )
    static let keaserDestructive = Color(red: 1, green: 0.27, blue: 0.23)

    /// The accent: chart bars, the add button, primary and capsule buttons,
    /// a filled confirm check. White in dark mode, black in light mode.
    static let keaserInk = Color(light: .black, dark: .white)
    /// Text and glyphs drawn on `keaserInk`.
    static let keaserOnInk = Color(light: .white, dark: .black)

    /// Large empty-state symbols ("No Expenses") and other muted icons.
    static let keaserMutedIcon = Color(light: .init(white: 0.55), dark: .init(white: 0.62))
    /// The close (xmark) glyph: grey and lighter in weight than the other
    /// header glyphs (back, add, confirm), as in the reference. It lets the
    /// glass behind it through, as the reference's does on every sheet
    /// (Accounts, Settings, the paywall, the welcome letter): a grey of 143
    /// measures 100 on a 51 circle and 106 on a 64 one in dark mode, 168 on
    /// 230 and 176 on 249 in light mode.
    static let keaserCloseGlyph = Color(
        light: Color(white: 0.56).opacity(0.7),
        dark: Color(white: 0.56).opacity(0.53)
    )
    /// Behind a row's non-destructive swipe action (Edit), whose label the
    /// system draws white: a grey dark enough for that in both appearances.
    static let keaserSwipeAction = Color(light: .init(white: 0.45), dark: .init(white: 0.32))
    /// Labels and symbols on the shortcut's expense card: the system's
    /// secondary label over its card, which the reference card uses
    /// (measured 0.52 to 0.54 in light mode against 0.45 for
    /// `keaserSecondaryText`), in both appearances.
    static let keaserSnippetLabel = Color(light: .init(white: 0.54), dark: .init(white: 0.6))

    /// A sheet's own background before iOS 26 (from iOS 26 the system draws
    /// glass). Charcoal in dark mode; grouped grey in light mode, so white
    /// cards stand out on it.
    static let keaserSheetBackground = Color(light: .init(red: 242 / 255, green: 242 / 255, blue: 247 / 255), dark: .init(red: 28 / 255, green: 28 / 255, blue: 30 / 255))
    /// Card fill for content on a sheet: a light veil in dark mode, so it
    /// reads the same on the charcoal sheet and on glass; white in light mode.
    static let keaserSheetCard = Color(light: .white, dark: .white.opacity(0.055))
    /// The barely visible tile behind row symbols and monograms on a sheet.
    static let keaserSheetTile = Color(light: .black.opacity(0.03), dark: .white.opacity(0.014))
    /// Symbol tiles and text fields sitting directly on a sheet.
    static let keaserSheetField = Color(light: .black.opacity(0.05), dark: .white.opacity(0.03))

    /// One colour per appearance, resolved by the system whenever the
    /// appearance changes.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum KeaserMetrics {
    static let screenPadding: CGFloat = 16
    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 24
    static let primaryButtonHeight: CGFloat = 58
    /// The band under a sheet's header where scrolled content fades out
    /// (`keaserSheetScrollEdge()`): the cards' 16pt spacing.
    static let sheetScrollEdge: CGFloat = 16
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
