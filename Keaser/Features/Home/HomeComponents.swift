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
    /// Where the "No Expenses" block starts, below the top bar.
    static let emptyStateTop: CGFloat = 120
}

/// One expense on Home: category symbol, title, date and amount.
struct HomeExpenseRow: View {
    let expense: Expense
    let symbol: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 16) {
            SymbolTile(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(expense.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(1)
                Text(expense.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.string(expense.amount, currencyCode: currencyCode))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.keaserCard, in: RoundedRectangle(cornerRadius: HomeLayout.rowRadius, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: HomeLayout.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The large centred empty states on Home ("No Account", "No Expenses",
/// "No Results"): grey symbol, bold title, grey message, optional action.
struct HomeEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color(white: 0.62))
                .frame(height: 42)
                .padding(.bottom, 21)
            // Fixed sizes rather than .title3: the text style's line height
            // is taller than the reference's 25pt lines.
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.keaserPrimaryText)
            Text(message)
                .font(.system(size: 20))
                .lineSpacing(1)
                .padding(.top, 3)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, 30)
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .contain)
    }
}

extension HomeEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// The small white capsule under an empty state ("Add Account").
struct HomeCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(Capsule().fill(Color.white))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// The round white "+" that floats at the bottom trailing corner.
struct HomeAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(width: HomeLayout.addButtonSize, height: HomeLayout.addButtonSize)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Add Expense")
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
