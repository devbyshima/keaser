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
}

enum KeaserMetrics {
    static let screenPadding: CGFloat = 16
    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 22
    static let tileRadius: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 58
}

extension Font {
    /// The big total on Home ("$20.00"): 40pt bold in the reference.
    static let keaserHero = Font.system(size: 40, weight: .bold)
    /// Onboarding and sheet page titles: Title 1 semibold (28pt at the
    /// default text size).
    static let keaserTitle = Font.title.weight(.semibold)
}
