import KeaserKit
import SwiftUI

/// Home's measurements, taken from the reference recording (points on a
/// 402pt wide screen).
enum HomeLayout {
    /// From the bottom of the top bar to the summary card.
    static let contentTop: CGFloat = 45
    static let topBarHeight: CGFloat = 44
    static let addButtonSize: CGFloat = 64
    static let addButtonTrailing: CGFloat = 29
    static let rowRadius: CGFloat = 24
    static let rowSpacing: CGFloat = 8
    /// Where the "No Expenses" block starts, below the top bar (measured
    /// with EmptyStateView, whose symbol takes its own height).
    static let emptyStateTop: CGFloat = 122
}

/// One expense on Home: category symbol, title, date and amount. At
/// accessibility text sizes the amount moves under the date so the title
/// keeps the width it needs.
struct HomeExpenseRow: View {
    let expense: Expense
    let symbol: String
    let currencyCode: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: 16) {
            SymbolTile(symbol: symbol, size: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(expense.title)
                    .keaserFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(isLarge ? 3 : 1)
                Text(expense.date, format: .dateTime.month(.abbreviated).day().year())
                    .keaserFont(15, relativeTo: .subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(isLarge ? 2 : 1)
                if isLarge {
                    amount
                        .padding(.top, 4)
                }
            }
            if isLarge {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 8)
                amount
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.keaserCard, in: RoundedRectangle(cornerRadius: HomeLayout.rowRadius, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: HomeLayout.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(MoneyFormat.string(expense.amount, currencyCode: currencyCode))
            .keaserFont(17, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(Color.keaserPrimaryText)
            .lineLimit(1)
    }
}

/// The round white "+" that floats at the bottom trailing corner.
struct HomeAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // A glyph in a fixed 64pt circle, so it stays fixed; the Large
            // Content Viewer shows it at accessibility sizes instead.
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(width: HomeLayout.addButtonSize, height: HomeLayout.addButtonSize)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Add Expense")
        .accessibilityShowsLargeContentViewer {
            Label("Add Expense", systemImage: "plus")
        }
    }
}

/// A gentle press-down for custom buttons.
struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
