import SwiftUI

/// Measured from the reference: the header's centre line sits 36pt below the
/// top of the sheet and the first card starts 64pt below that line.
enum HomeSheetMetrics {
    static let headerTop: CGFloat = 14
    static let contentTop: CGFloat = 42
}

// Home's floating sheets (Accounts, Add Account, the expense editor) sit
// on glass at a medium detent. In light mode the reference draws their
// cards as a grey veil over that glass, with white symbol tiles, where the
// full-height Settings sheet uses white cards; dark mode keeps the shared
// sheet values exactly.
extension Color {
    /// Cards and fields on Home's sheets.
    static let homeSheetCard = Color(light: .black.opacity(0.055), dark: .white.opacity(0.055))
    /// The tile behind an account's symbol: white in light mode, none in
    /// dark mode, as in the reference.
    static let homeSheetTile = Color(light: .white.opacity(0.75), dark: .clear)
    /// The tile behind a suggested expense's category symbol.
    static let homeSuggestionTile = Color(light: .white.opacity(0.75), dark: .white.opacity(0.08))
}

extension View {
    /// A `KeaserSheetHeader` as Home's floating sheets (Accounts, Add
    /// Account, the expense editor) draw it. Like a navigation bar, its text
    /// stops growing at the largest standard size so the title keeps room
    /// between the side controls; those show the Large Content Viewer.
    func homeSheetHeader() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 16)
            .padding(.top, HomeSheetMetrics.headerTop)
    }
}
