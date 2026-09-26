import SwiftUI

/// Measured from the reference: the header's centre line sits 36pt below the
/// top of the sheet and the first card starts 64pt below that line.
enum HomeSheetMetrics {
    static let headerTop: CGFloat = 14
    static let contentTop: CGFloat = 42
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
