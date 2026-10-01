import KeaserKit
import SwiftUI

/// What tapping an expense shows: its details, read only, on the same card
/// the Add Expense shortcut confirms with (the amount, then title, account,
/// category, payment method and date), and the photos of its receipts under it
/// when one was kept, opening full screen. Edit turns the sheet into Edit
/// Expense, and Cancel or Save there comes back to the details.
///
/// The reference opens Edit Expense straight away; showing the details
/// first is the founder's choice. Long press and swipe still go straight to
/// Edit and Delete.
struct ExpenseDetailSheet: View {
    let accountID: UUID
    let expenseID: UUID

    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var confirmingDelete = false
    @State private var deletedCount = 0
    @State private var viewing: ReceiptViewing?

    private static let receiptsID = "receipts"

    private var account: Account? { store.account(id: accountID) }
    private var expense: Expense? { account?.expenses.first { $0.id == expenseID } }

    var body: some View {
        Group {
            if isEditing, let expense {
                ExpenseEditorView(accountID: accountID, expense: expense) {
                    withAnimation(.smooth(duration: 0.3)) { isEditing = false }
                }
                .transition(.opacity)
            } else {
                details
                    .transition(.opacity)
            }
        }
        // Deleted here, in Edit Expense or elsewhere: nothing left to show.
        .onChange(of: expense == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .sensoryFeedback(.success, trigger: deletedCount)
    }

    private var details: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Expense") {
                KeaserCircleButton("xmark", label: "Close") { dismiss() }
                    .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            } trailing: {
                Button("Edit") {
                    withAnimation(.smooth(duration: 0.3)) { isEditing = true }
                }
                .homeSheetHeaderButton(confirms: true)
                .disabled(expense == nil)
                .accessibilityShowsLargeContentViewer()
            }
            .homeSheetHeader()
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 16) {
                        if let expense, let account {
                            KeaserCard(fill: .homeSheetCard) {
                                ExpenseCardView(card: IntentSupport.card(for: expense, in: account, store: store))
                                    .padding(.bottom, 8)
                            }
                            ReceiptDetailSection(receipts: expense.receipts) { index in
                                viewing = ReceiptViewing(receipts: expense.receipts.map(ReceiptImageSource.saved), start: index)
                            }
                            .id(Self.receiptsID)
                            deleteButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, HomeSheetMetrics.contentTop - KeaserMetrics.sheetScrollEdge)
                    .padding(.bottom, 24)
                }
                .keaserSheetScrollEdge()
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .keaserReadableScrollContent()
                #if DEBUG
                // `-KeaserExpenseScroll receipts` scrolls down to the
                // receipts, to screenshot the gallery under the header.
                .task {
                    guard DebugLaunch.string("KeaserExpenseScroll") == "receipts" else { return }
                    try? await Task.sleep(for: .milliseconds(900))
                    scroller.scrollTo(Self.receiptsID, anchor: .top)
                }
                #endif
            }
        }
        // Two or more receipts make a gallery that needs the whole height.
        .presentationDetents((expense?.receipts.count ?? 0) > 1 ? [.large] : [.medium])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
        // The details tell Siri which expense is open, as Edit Expense does.
        .keaserEntity(expense: expenseID)
        .fullScreenCover(item: $viewing) { shown in
            ReceiptViewer(shown, title: expense?.title ?? "")
        }
        #if DEBUG
        // `-KeaserReceiptViewer <i>` opens the i-th receipt, for screenshots.
        .task {
            guard let number = DebugLaunch.int("KeaserReceiptViewer"), let receipts = expense?.receipts,
                  receipts.indices.contains(number - 1)
            else { return }
            try? await Task.sleep(for: .milliseconds(700))
            viewing = ReceiptViewing(receipts: receipts.map(ReceiptImageSource.saved), start: number - 1)
        }
        #endif
        .confirmationDialog("Delete Expense?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let expense {
                Text("\u{201C}\(expense.title)\u{201D} will be removed from this account.")
            }
        }
    }

    private var deleteButton: some View {
        KeaserActionCard("Delete Expense", role: .destructive) {
            confirmingDelete = true
        }
    }

    private func delete() {
        deletedCount += 1
        withAnimation(.smooth(duration: 0.3)) {
            store.deleteExpense(expenseID, in: accountID)
        }
    }
}
