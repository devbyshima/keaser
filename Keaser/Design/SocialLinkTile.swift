import SwiftUI

extension Color {
    /// Behind a social profile's glyph: black in both appearances, like
    /// the brand marks in the reference's Follow Us rows and welcome letter.
    static let socialTile = Color(light: .black, dark: .black)
    /// The glyph on `socialTile`.
    static let socialTileGlyph = Color(light: .white, dark: .white)
}

/// A social profile's mark (`AppLinks.SocialLink.symbol`): a white glyph on
/// a black rounded square `size` points wide, 24 in the reference. The
/// glyph is sized from the tile, not from the text beside it.
struct SocialLinkTile: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 13 / 24, weight: .semibold))
            .foregroundStyle(Color.socialTileGlyph)
            .frame(width: size, height: size)
            .background(Color.socialTile, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}
