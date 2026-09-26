import KeaserKit
import SwiftUI
import UIKit

/// New Expense and Edit Expense: title, amount, category, payment method and
/// date on one card, with Smart Suggestions under the title while typing.
struct ExpenseEditorView: View {
    let accountID: UUID
    /// Nil when creating.
    let original: Expense?

    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    /// Exactly what the amount field shows, symbol included ("$20").
    @State private var amountDisplay: String
    @State private var categoryID: UUID?
    @State private var paymentMethodID: UUID?
    @State private var date: Date
    @State private var confirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, amount }

    init(accountID: UUID, expense: Expense? = nil) {
        self.accountID = accountID
        self.original = expense
        _title = State(initialValue: expense?.title ?? "")
        _amountDisplay = State(initialValue: "")
        _categoryID = State(initialValue: expense?.categoryID)
        _paymentMethodID = State(initialValue: expense?.paymentMethodID)
        _date = State(initialValue: expense?.date ?? .now)
    }

    private var isNew: Bool { original == nil }
    private var account: Account? { store.account(id: accountID) }
    private var currencyCode: String { store.preferences.currencyCode }

    private var amount: Decimal? {
        MoneyFormat.parse(AmountInput.digits(amountDisplay, currencyCode: currencyCode))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0
    }

    private var suggestions: [Expense] {
        guard store.preferences.smartSuggestionsEnabled, focus == .title, !title.isEmpty, let account else { return [] }
        return SmartSuggester.suggestions(for: title, in: account.expenses, excluding: original?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeSheetHeader(title: isNew ? "New Expense" : "Edit Expense") {
                Button("Cancel") { dismiss() }
                    .keaserGlassButtonStyle()
            } trailing: {
                Button("Save", action: save)
                    .keaserGlassButtonStyle()
                    .disabled(!canSave)
            }
            ScrollView {
                VStack(spacing: 16) {
                    card
                    if !isNew {
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, HomeSheetMetrics.contentTop)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        // One detent, as in the reference: the keyboard lifts the sheet
        // instead of expanding it.
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
        .onAppear {
            if let original {
                amountDisplay = AmountInput.display(
                    AmountInput.editingText(for: original.amount, currencyCode: currencyCode),
                    currencyCode: currencyCode
                )
            }
            #if DEBUG
            // `-KeaserExpenseTitle Co` types a title, to screenshot Smart
            // Suggestions.
            if isNew, let typed = DebugLaunch.string("KeaserExpenseTitle") { title = typed }
            #endif
            focus = .title
        }
        .confirmationDialog("Delete Expense?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This expense will be removed from the account.")
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            titleRow
            ForEach(suggestions) { suggestion in
                HomeRowSeparator()
                SuggestionRow(
                    expense: suggestion,
                    symbol: account?.symbol(for: suggestion) ?? ExpenseCategory.fallbackSymbol,
                    currencyCode: currencyCode
                ) {
                    apply(suggestion)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HomeRowSeparator()
            amountRow
            HomeRowSeparator()
            categoryRow
            HomeRowSeparator()
            paymentRow
            HomeRowSeparator()
            dateRow
        }
        .background(Color.keaserCardRaised)
        .clipShape(RoundedRectangle(cornerRadius: HomeSheetMetrics.cardRadius, style: .continuous))
        .animation(.snappy(duration: 0.25), value: suggestions.map(\.id))
    }

    private var titleRow: some View {
        TextField("", text: $title, prompt: Text("Title").foregroundStyle(Color.keaserTertiaryText))
            .font(.system(size: 17))
            .foregroundStyle(Color.keaserPrimaryText)
            .focused($focus, equals: .title)
            .textInputAutocapitalization(.sentences)
            .onSubmit { focus = .amount }
            .editorRow()
    }

    private var amountRow: some View {
        HStack(spacing: 12) {
            Text("Amount")
                .editorLabel()
            TextField(
                "",
                text: $amountDisplay,
                prompt: Text(MoneyFormat.string(0, currencyCode: currencyCode)).foregroundStyle(Color.keaserTertiaryText)
            )
            .font(.system(size: 17))
            .foregroundStyle(Color.keaserPrimaryText)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .focused($focus, equals: .amount)
            .onChange(of: amountDisplay) { _, typed in
                // Re-derive what the field shows so the symbol stays in front
                // and stray characters never stick.
                let cleaned = AmountInput.display(typed, currencyCode: currencyCode)
                if cleaned != typed { amountDisplay = cleaned }
            }
        }
        .editorRow()
        .contentShape(Rectangle())
        .onTapGesture { focus = .amount }
    }

    private var categoryRow: some View {
        HStack(spacing: 12) {
            Text("Category")
                .editorLabel()
            Spacer(minLength: 8)
            Menu {
                Picker("Category", selection: $categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(account?.categories ?? []) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            } label: {
                MenuValueLabel(text: account?.category(id: categoryID)?.name ?? "None")
            }
            .menuOrder(.fixed)
        }
        .editorRow()
    }

    private var paymentRow: some View {
        HStack(spacing: 12) {
            Text("Payment")
                .editorLabel()
            Spacer(minLength: 8)
            Menu {
                Picker("Payment", selection: $paymentMethodID) {
                    Text("None").tag(UUID?.none)
                    ForEach(account?.paymentMethods ?? []) { method in
                        Text(method.name).tag(UUID?.some(method.id))
                    }
                }
            } label: {
                MenuValueLabel(text: account?.paymentMethod(id: paymentMethodID)?.name ?? "None")
            }
            .menuOrder(.fixed)
        }
        .editorRow()
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Date")
                .editorLabel()
            Spacer(minLength: 8)
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
        .editorRow(height: 64)
    }

    private var deleteButton: some View {
        Button {
            focus = nil
            confirmingDelete = true
        } label: {
            Text("Delete Expense")
                .font(.system(size: 17))
                .foregroundStyle(Color.keaserDestructive)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeHighlightRowStyle())
        .background(Color.keaserCardRaised)
        .clipShape(RoundedRectangle(cornerRadius: HomeSheetMetrics.cardRadius, style: .continuous))
    }

    // MARK: Actions

    /// Fills everything from a past expense; the date stays as chosen.
    private func apply(_ suggestion: Expense) {
        title = suggestion.title
        amountDisplay = AmountInput.display(
            AmountInput.editingText(for: suggestion.amount, currencyCode: currencyCode),
            currencyCode: currencyCode
        )
        // Only labels that still exist in this account.
        categoryID = account?.category(id: suggestion.categoryID)?.id
        paymentMethodID = account?.paymentMethod(id: suggestion.paymentMethodID)?.id
        focus = nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func save() {
        guard canSave, let amount else { return }
        var expense = original ?? Expense(title: "", amount: 0)
        expense.title = title
        expense.amount = amount
        expense.categoryID = categoryID
        expense.paymentMethodID = paymentMethodID
        expense.date = date
        focus = nil
        store.saveExpense(expense, in: accountID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func delete() {
        guard let original else { return }
        store.deleteExpense(original.id, in: accountID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// A past expense offered by Smart Suggestions.
private struct SuggestionRow: View {
    let expense: Expense
    let symbol: String
    let currencyCode: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolTile(symbol: symbol, size: 30, background: Color.white.opacity(0.08))
                Text(expense.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(MoneyFormat.string(expense.amount, currencyCode: currencyCode))
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(1)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeHighlightRowStyle())
        .accessibilityLabel("Use \(expense.title), \(MoneyFormat.string(expense.amount, currencyCode: currencyCode))")
    }
}

/// The trailing value of a menu row: "None" with up and down chevrons.
private struct MenuValueLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 17))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.keaserPrimaryText)
        .contentShape(Rectangle())
    }
}

private extension View {
    func editorRow(height: CGFloat = 50) -> some View {
        padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }

    func editorLabel() -> some View {
        font(.system(size: 17))
            .foregroundStyle(Color.keaserPrimaryText)
            .fixedSize()
    }
}
