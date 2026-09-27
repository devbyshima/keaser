import KeaserKit
import SwiftUI

/// Search takes over the whole screen, as in the reference: matching
/// expenses at the top in the usual card, "Search Expenses" or "No Results"
/// in the middle otherwise, and at the bottom, just above the keyboard, the
/// field in a glass capsule beside a round glass button that leaves search.
struct HomeSearchView: View {
    let account: Account
    let result: ExpenseQuery.SearchResult
    let currencyCode: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keaserBottomBar { bar }
            .animation(.smooth(duration: 0.25), value: result)
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .prompt:
            HomeSearchMessage(
                title: "Search Expenses",
                message: "Enter a search term to find expenses"
            )
            .transition(.opacity)
        case .noMatches:
            HomeSearchMessage(
                title: "No Results",
                message: "No expenses match \u{201C}\(text.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
            )
            .transition(.opacity)
        case .matches(let expenses):
            ScrollView {
                LazyVStack(spacing: 0) {
                    HomeExpenseRows(
                        expenses: expenses,
                        account: account,
                        currencyCode: currencyCode,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
                .padding(.horizontal, KeaserMetrics.screenPadding)
                .padding(.top, HomeLayout.searchResultsTop)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .keaserSwipeActionsContainer()
            .keaserReadableScrollContent()
            .transition(.opacity)
        }
    }

    // MARK: Bottom bar

    /// With the keyboard down the bar floats in from the screen edges, as
    /// in the reference; typing widens it to nearly the full width.
    private var bar: some View {
        KeaserGlassContainer(spacing: 8) {
            HStack(spacing: 12) {
                field
                closeButton
            }
        }
        .padding(.horizontal, isFocused.wrappedValue ? 8 : 28)
        .padding(.bottom, isFocused.wrappedValue ? 10 : 0)
        .keaserReadableWidth()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: isFocused.wrappedValue)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.keaserPrimaryText)
                .accessibilityHidden(true)
            TextField(
                "Search expenses",
                text: $text,
                prompt: Text("Search expenses").foregroundStyle(Color.keaserSecondaryText)
            )
            .font(.body)
            .foregroundStyle(Color.keaserPrimaryText)
            .focused(isFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel("Search expenses")
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Taps across 44pt but takes the drawn glyph's room in the
                // capsule.
                .padding(-10)
                .accessibilityLabel("Clear Search")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, 15)
        .padding(.trailing, 14)
        .frame(minHeight: HomeLayout.searchBarHeight)
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
        .keaserGlass()
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(width: HomeLayout.searchBarHeight, height: HomeLayout.searchBarHeight)
                .contentShape(Circle())
                .keaserGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Search")
        .accessibilityShowsLargeContentViewer {
            Label("Close Search", systemImage: "xmark")
        }
    }
}

/// The magnifier, a bold title and a grey line, centred over the space
/// above the search bar. Sized like Home's other empty states, but the
/// message keeps to one line where it fits, as in the reference.
private struct HomeSearchMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .keaserFont(40)
                .foregroundStyle(Color.keaserMutedIcon)
                .padding(.bottom, 21)
                .accessibilityHidden(true)
            Text(title)
                .keaserFont(20, weight: .bold)
                .foregroundStyle(Color.keaserPrimaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .keaserFont(20)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The reference centres the block between the top of the screen
        // (not the status bar) and the search bar.
        .ignoresSafeArea(.container, edges: .top)
        .accessibilityElement(children: .combine)
    }
}
