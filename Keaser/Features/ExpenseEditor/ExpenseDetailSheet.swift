import KeaserKit
import SwiftUI

/// What tapping an expense shows: its details, read only, on the same card
/// the Add Expense shortcut confirms with (the amount, then title, account,
/// category, payment method and date), and the receipt's photo under it
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
    @State private var viewingReceipt: ReceiptImageSource?

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
            ScrollView {
                VStack(spacing: 16) {
                    if let expense, let account {
                        KeaserCard(fill: .homeSheetCard) {
                            ExpenseCardView(card: IntentSupport.card(for: expense, in: account, store: store))
                                .padding(.bottom, 8)
                        }
                        if let photo = expense.receipt {
                            ReceiptDetailRow(photo: photo) { viewingReceipt = .saved(photo) }
                        }
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, HomeSheetMetrics.contentTop)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .keaserReadableScrollContent()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
        // The details tell Siri which expense is open, as Edit Expense does.
        .keaserEntity(expense: expenseID)
        .fullScreenCover(item: $viewingReceipt) { source in
            ReceiptViewer(source: source, title: expense?.title ?? "")
        }
        #if DEBUG
        // `-KeaserReceiptViewer 1` opens the receipt, for screenshots.
        .task {
            guard DebugLaunch.int("KeaserReceiptViewer") == 1, let photo = expense?.receipt else { return }
            try? await Task.sleep(for: .milliseconds(700))
            viewingReceipt = .saved(photo)
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
        KeaserCard(fill: .homeSheetCard) {
            Button {
                confirmingDelete = true
            } label: {
                Text("Delete Expense")
                    .font(.body)
                    .foregroundStyle(Color.keaserDestructive)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowButtonStyle())
        }
    }

    private func delete() {
        deletedCount += 1
        withAnimation(.smooth(duration: 0.3)) {
            store.deleteExpense(expenseID, in: accountID)
        }
    }
}
