import SwiftUI

/// Where the header and the first card sit in Home's sheets. On iOS 26 and
/// later they are the reference's, measured in the sheet's own points: a
/// floating sheet is drawn at 96% (its 402pt layout in the 386pt between
/// the screen's side margins), so lengths read straight off the recording's
/// pixels come out 4% short. There the header's centre line sits 38pt below
/// the top of the sheet and the first card starts 67pt below that line, as
/// in the expense editor. Before iOS 26 the attached sheets keep their
/// earlier layout.
enum HomeSheetMetrics {
    private static var isFloatingSheet: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    static var headerTop: CGFloat { isFloatingSheet ? 16 : 14 }
    static var contentTop: CGFloat { isFloatingSheet ? 45 : 42 }
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
    /// A header button's label while it is disabled (Save with nothing to
    /// save), measured from the reference.
    static let homeSheetDisabledAction = Color(light: .init(white: 0.56), dark: .init(white: 0.41))
    /// The expense editor's Title and $0.00 prompts on iOS 26 and later,
    /// measured from the reference: darker than `keaserTertiaryText` on the
    /// grey card in light mode, lighter in dark mode.
    static let homeSheetPlaceholder = Color(light: .init(white: 0.37), dark: .init(white: 0.44))
}

extension View {
    /// A `KeaserSheetHeader` as Home's floating sheets (Accounts, Add
    /// Account, the expense editor) draw it. Like a navigation bar, its text
    /// stops growing at the largest standard size so the title keeps room
    /// between the side controls; those show the Large Content Viewer.
    func homeSheetHeader(top: CGFloat = HomeSheetMetrics.headerTop) -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 16)
            .padding(.top, top)
    }

    /// The text buttons in a Home sheet's header: Cancel and Save in the
    /// expense editor, Edit and Done on Accounts. On iOS 26 and later they
    /// are glass capsules at the reference's size, as tall as the round
    /// close button beside them, with Save, Edit and Done in semibold;
    /// before iOS 26 the translucent capsules stay as they are.
    @ViewBuilder
    func homeSheetHeaderButton(confirms: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(HomeSheetHeaderButtonStyle(confirms: confirms))
        } else {
            keaserGlassButtonStyle()
        }
    }
}

/// A glass capsule 44pt tall with 16pt either side of its label, as
/// measured from the reference's Edit Expense and Accounts headers (in the
/// sheet's own points: iOS draws a floating sheet at 96%, so Edit's
/// capsule is 181 x 127 pixels on screen, like the close button). The system
/// glass button style draws its own size, which iOS 27 made smaller (and
/// its large size larger) than the reference.
private struct HomeSheetHeaderButtonStyle: ButtonStyle {
    let confirms: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(confirms ? .semibold : .regular))
            .foregroundStyle(isEnabled ? Color.keaserPrimaryText : Color.homeSheetDisabledAction)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .keaserGlass(interactive: isEnabled)
    }
}
