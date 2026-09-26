import SwiftUI

/// The header of Home's floating sheets (Accounts, Add Account, the expense
/// editor): an optional control on each side and a centred title. Drawn in the
/// sheet rather than in a navigation bar so the glass controls look the same
/// on iOS 18 and iOS 26.
struct HomeSheetHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
                .padding(.horizontal, 96)
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(height: HomeSheetMetrics.headerHeight)
        .padding(.horizontal, 16)
        .padding(.top, HomeSheetMetrics.headerTop)
    }
}

extension HomeSheetHeader where Leading == EmptyView, Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() } trailing: { EmptyView() }
    }
}

/// Measured from the reference: the header's centre line sits 36pt below the
/// top of the sheet and the first card starts 64pt below that line.
enum HomeSheetMetrics {
    static let headerTop: CGFloat = 14
    static let headerHeight: CGFloat = 44
    static let contentTop: CGFloat = 42
    static let cardRadius: CGFloat = 26
}

/// A round glass icon button for sheet headers (close, back).
struct HomeCircleButton: View {
    let symbol: String
    var accessibilityLabel: String
    var tint: Color = .keaserPrimaryText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .keaserCircleButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The hairline between rows of a card, inset like the reference.
struct HomeRowSeparator: View {
    var leading: CGFloat = 16

    var body: some View {
        // Brighter than the shared hairline: these sit on the raised card.
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, leading)
            .padding(.trailing, 16)
    }
}
