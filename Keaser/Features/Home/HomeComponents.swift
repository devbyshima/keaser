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
    /// Where the hairline between expense rows starts: under the title,
    /// past the 16pt margin, the 42pt symbol tile and the 16pt gap.
    static let rowSeparatorLeading: CGFloat = 74
    /// Where the "No Expenses" block starts, below the top bar (measured
    /// with EmptyStateView, whose symbol takes its own height).
    static let emptyStateTop: CGFloat = 122
    /// From the top of the safe area to the first search result.
    static let searchResultsTop: CGFloat = 35
    /// The search field capsule and the round button beside it.
    static let searchBarHeight: CGFloat = 48
}

/// Expenses as the rows of one card, with a hairline under each title
/// between them, as in the reference: Home's "Latest" and the search
/// results. A row opens its expense; its context menu edits or deletes it.
///
/// Place it in a lazy stack with no spacing: each row draws its own slice
/// of the card, so a long list is still built only as it scrolls in.
struct HomeExpenseRows: View {
    let expenses: [Expense]
    let account: Account
    let currencyCode: String
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void

    var body: some View {
        ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
            let position = CardPosition(index: index, count: expenses.count)
            Button {
                onEdit(expense)
            } label: {
                HomeExpenseRow(
                    expense: expense,
                    symbol: account.symbol(for: expense),
                    currencyCode: currencyCode
                )
                .background(CardRowBackground(position: position, fill: .keaserCard))
            }
            // Which expense the row is, for Siri (no visual change).
            .keaserEntity(expense: expense.id)
            .buttonStyle(HomeRowButtonStyle(position: position))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: KeaserMetrics.rowRadius, style: .continuous))
            .contextMenu {
                Button {
                    onEdit(expense)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            // Outside the button, so a lifted row does not carry it.
            .overlay(alignment: .top) {
                if index > 0 {
                    KeaserRowSeparator(leading: HomeLayout.rowSeparatorLeading)
                }
            }
            .keaserSwipeActions(onEdit: { onEdit(expense) }, onDelete: { onDelete(expense) })
            .transition(.opacity)
        }
    }
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

/// A row of the expense card tints while pressed, like a list cell. Drawn
/// over the row, whose own slice of the card would hide it behind.
private struct HomeRowButtonStyle: ButtonStyle {
    let position: CardPosition

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                CardRowBackground(position: position, fill: .keaserInk.opacity(configuration.isPressed ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The round ink "+" that floats at the bottom trailing corner: white on
/// black in dark mode, black on the pale canvas in light mode.
struct HomeAddButton: View {
    let action: () -> Void

    /// Lifts the button off rows scrolling under it in dark mode; the light
    /// reference draws it flat.
    private static let shadow = Color(light: .clear, dark: .black.opacity(0.35))

    var body: some View {
        Button(action: action) {
            // A glyph in a fixed 64pt circle, so it stays fixed; the Large
            // Content Viewer shows it at accessibility sizes instead.
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.keaserOnInk)
                .frame(width: HomeLayout.addButtonSize, height: HomeLayout.addButtonSize)
                .background(Circle().fill(Color.keaserInk))
                .shadow(color: Self.shadow, radius: 12, y: 4)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Add Expense")
        .accessibilityShowsLargeContentViewer {
            Label("Add Expense", systemImage: "plus")
        }
    }
}
