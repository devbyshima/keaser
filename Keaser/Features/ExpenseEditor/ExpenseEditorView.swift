import KeaserKit
import SwiftUI

/// New Expense and Edit Expense: title, amount, category, payment method and
/// date on one card, with Smart Suggestions under the title while typing.
struct ExpenseEditorView: View {
    let accountID: UUID
    /// Nil when creating.
    let original: Expense?

    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title: String
    /// Exactly what the amount field shows, symbol included ("$20").
    @State private var amountDisplay: String
    /// The stored amount the field was last filled in from (the expense
    /// being edited, or a suggestion). Saved as is while the field still
    /// shows it, so a title-only edit never rounds the amount.
    @State private var amountSeed: Decimal?
    @State private var categoryID: UUID?
    @State private var paymentMethodID: UUID?
    /// Set once the user chooses a label themselves (in the menu, or by
    /// taking a suggestion), so a guess never replaces their choice.
    @State private var categoryPicked: Bool
    @State private var paymentPicked: Bool
    /// The title the labels were last guessed for.
    @State private var guessedTitle: String
    /// A guessed payment method waiting to be shown a beat after the
    /// category. Save applies it if the user is faster than that.
    @State private var pendingPayment: PendingPayment?
    /// The rule guess for a title nothing else knows, held back while the
    /// on-device model is asked, so the labels change once. Save fills it in
    /// rather than wait.
    @State private var heldGuess: HeldGuess?
    @State private var modelTask: Task<Void, Never>?
    /// Receipt scanning, New Expense only: while a receipt is read, what
    /// the note under the card says once it filled the fields in, and
    /// whether the photo turned out not to be a receipt.
    @State private var readingReceipt = false
    @State private var receiptTask: Task<Void, Never>?
    @State private var receiptNote: String?
    @State private var receiptNotFound = false
    @State private var date: Date
    @State private var confirmingDelete = false
    /// Where the scroll view and Delete Expense end on screen: the button
    /// only shows when all of it is above the keyboard.
    @State private var visibleBottom = CGFloat.infinity
    @State private var deleteBottom = CGFloat.zero
    @State private var suggestionTaken = 0
    @State private var finished = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, amount }

    private struct PendingPayment: Equatable {
        let methodID: UUID?
        let title: String
    }

    private struct HeldGuess: Equatable {
        let guess: SmartSuggester.LabelGuess
        let title: String
    }

    /// The pause between the guessed category and payment method landing,
    /// matching the reference.
    private static let paymentGuessDelay = Duration.milliseconds(350)

    init(accountID: UUID, expense: Expense? = nil) {
        self.accountID = accountID
        self.original = expense
        _title = State(initialValue: expense?.title ?? "")
        _amountDisplay = State(initialValue: "")
        _amountSeed = State(initialValue: expense?.amount)
        _categoryID = State(initialValue: expense?.categoryID)
        _paymentMethodID = State(initialValue: expense?.paymentMethodID)
        _categoryPicked = State(initialValue: expense?.categoryID != nil)
        _paymentPicked = State(initialValue: expense?.paymentMethodID != nil)
        _guessedTitle = State(initialValue: ExpenseQuery.normalized(expense?.title ?? ""))
        _date = State(initialValue: expense?.date ?? .now)
    }

    private var isNew: Bool { original == nil }
    private var account: Account? { store.account(id: accountID) }
    private var currencyCode: String { store.preferences.currencyCode }

    private var amount: Decimal? {
        AmountInput.amount(from: amountDisplay, seed: amountSeed, currencyCode: currencyCode)
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
            KeaserSheetHeader(title: isNew ? "New Expense" : "Edit Expense") {
                Button("Cancel") { dismiss() }
                    .homeSheetHeaderButton()
                    .accessibilityShowsLargeContentViewer()
            } trailing: {
                Button("Save", action: save)
                    .homeSheetHeaderButton(confirms: true)
                    .disabled(!canSave)
                    .accessibilityShowsLargeContentViewer()
            }
            .homeSheetHeader()
            ScrollView {
                VStack(spacing: 16) {
                    card
                    if let receiptNote {
                        ReceiptNote(text: receiptNote)
                    }
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
            .keaserReadableScrollContent()
            // Where the scroll view ends on screen: at the keyboard's top
            // edge while it is up. Delete Expense only shows above it.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { visibleBottom = $0 }
        }
        // One detent, as in the reference: the keyboard lifts the sheet
        // instead of expanding it.
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
        // Edit Expense tells Siri which expense is open.
        .keaserEntity(expense: original?.id)
        .onAppear {
            if let original {
                amountDisplay = AmountInput.field(for: original.amount, currencyCode: currencyCode)
            }
            #if DEBUG
            // `-KeaserExpenseTitle Co` types a title, to screenshot Smart
            // Suggestions.
            if isNew, let typed = DebugLaunch.string("KeaserExpenseTitle") { title = typed }
            #endif
            prewarmCategoryModel()
            #if DEBUG
            // `-KeaserReceipt <sample>` reads a sample receipt as if it had
            // just been scanned, so without the keyboard.
            if isNew, let source = ReceiptScanner.debugSource {
                if ReceiptScanner.holdsReading {
                    readingReceipt = true
                } else {
                    readReceipt(source)
                }
                return
            }
            #endif
            focus = .title
            #if DEBUG
            // `-KeaserExpenseFocus amount` then moves on to the amount, as
            // Return does, to screenshot the guessed labels.
            if DebugLaunch.string("KeaserExpenseFocus") == "amount" {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    focus = .amount
                }
            }
            #endif
        }
        .onChange(of: focus) { old, new in
            // Moving on from the title is when the reference guesses its
            // category and payment method.
            if old == .title, new != .title { guessLabels() }
        }
        .onDisappear {
            modelTask?.cancel()
            receiptTask?.cancel()
        }
        .sensoryFeedback(.selection, trigger: suggestionTaken)
        .sensoryFeedback(.success, trigger: finished)
        .confirmationDialog("Delete Expense?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This expense will be removed from the account.")
        }
        .alert("No Receipt Found", isPresented: $receiptNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Keaser couldn't find a total or a date. Try again with the whole receipt flat and in view.")
        }
    }

    // MARK: Card

    private var card: some View {
        KeaserCard(fill: .homeSheetCard) {
            titleRow
            ForEach(suggestions) { suggestion in
                KeaserRowSeparator()
                SuggestionRow(
                    expense: suggestion,
                    symbol: account?.symbol(for: suggestion) ?? ExpenseCategory.fallbackSymbol,
                    currencyCode: currencyCode
                ) {
                    apply(suggestion)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            KeaserRowSeparator()
            amountRow
            KeaserRowSeparator()
            categoryRow
            KeaserRowSeparator()
            paymentRow
            KeaserRowSeparator()
            dateRow
        }
        .animation(.snappy(duration: 0.25), value: suggestions.map(\.id))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Title").foregroundStyle(Color.keaserTertiaryText))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .focused($focus, equals: .title)
                // With a prompt, the field's title is not read out on its own.
                .accessibilityLabel("Title")
                .textInputAutocapitalization(.sentences)
                .onSubmit { focus = .amount }
            if isNew {
                ReceiptScanButton(isReading: readingReceipt, onOpen: openReceiptScanner, onScan: readReceipt)
            }
        }
        .editorRow()
    }

    private var amountRow: some View {
        EditorField("Amount", fillsRow: true) {
            TextField(
                "Amount",
                text: $amountDisplay,
                prompt: Text(MoneyFormat.string(0, currencyCode: currencyCode)).foregroundStyle(Color.keaserTertiaryText)
            )
            .font(.body)
            .foregroundStyle(Color.keaserPrimaryText)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .focused($focus, equals: .amount)
            .accessibilityLabel("Amount")
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
        let name = account?.category(id: categoryID)?.name ?? "None"
        return EditorField("Category") {
            Menu {
                Picker("Category", selection: Binding(get: { categoryID }, set: pickCategory)) {
                    Text("None").tag(UUID?.none)
                    ForEach(account?.categories ?? []) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            } label: {
                MenuValueLabel(text: name)
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Category")
            .accessibilityValue(name)
        }
        .editorRow()
    }

    private var paymentRow: some View {
        let name = account?.paymentMethod(id: paymentMethodID)?.name ?? "None"
        return EditorField("Payment") {
            Menu {
                Picker("Payment", selection: Binding(get: { paymentMethodID }, set: pickPaymentMethod)) {
                    Text("None").tag(UUID?.none)
                    ForEach(account?.paymentMethods ?? []) { method in
                        Text(method.name).tag(UUID?.some(method.id))
                    }
                }
            } label: {
                MenuValueLabel(text: name)
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Payment")
            .accessibilityValue(name)
        }
        .editorRow()
    }

    private var dateRow: some View {
        // The compact picker reads as "Date Picker" whatever its label, so
        // the row's own label stays spoken here.
        EditorField("Date", speaksLabel: true) {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
        .editorRow(height: 64)
    }

    /// Delete Expense under the card. Smart Suggestions' rows (or a large
    /// text size) can push it down to the keyboard's edge; rather than show
    /// it cut in half there, it stays out of sight until it is scrolled
    /// fully into view, or the keyboard or the rows go away.
    private var deleteButton: some View {
        let fits = deleteBottom <= visibleBottom + 0.5
        return KeaserCard(fill: .homeSheetCard) {
            Button {
                focus = nil
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
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { deleteBottom = $0 }
        .opacity(fits ? 1 : 0)
        .allowsHitTesting(fits)
        .animation(.easeOut(duration: 0.15), value: fits)
    }

    // MARK: Actions

    /// Fills everything from a past expense; the date stays as chosen.
    private func apply(_ suggestion: Expense) {
        title = suggestion.title
        guessedTitle = ExpenseQuery.normalized(suggestion.title)
        amountDisplay = AmountInput.field(for: suggestion.amount, currencyCode: currencyCode)
        amountSeed = suggestion.amount
        // Only labels that still exist in this account.
        categoryID = account?.category(id: suggestion.categoryID)?.id
        paymentMethodID = account?.paymentMethod(id: suggestion.paymentMethodID)?.id
        categoryPicked = true
        paymentPicked = true
        focus = nil
        suggestionTaken += 1
    }

    private func pickCategory(_ id: UUID?) {
        categoryID = id
        categoryPicked = true
    }

    private func pickPaymentMethod(_ id: UUID?) {
        paymentMethodID = id
        paymentPicked = true
    }

    /// Smart Suggestions' guess for a title no suggestion was taken for. It
    /// only fills in labels the user has not chosen themselves.
    ///
    /// For a title neither the history nor the word rules know, the
    /// on-device model is asked first, for up to `SmartLabels.editorBudget`;
    /// the guess then lands once, as it always has.
    private func guessLabels() {
        guard store.preferences.smartSuggestionsEnabled, finished == 0, let account, !(categoryPicked && paymentPicked) else { return }
        let normalized = ExpenseQuery.normalized(title)
        if let heldGuess {
            guard heldGuess.title != normalized else { return }
            modelTask?.cancel()
            self.heldGuess = nil
        }
        guard normalized != guessedTitle else { return }
        let guess = SmartSuggester.guessLabels(
            for: title,
            categories: account.categories,
            paymentMethods: account.paymentMethods,
            history: account.expenses,
            excluding: original?.id
        )
        let model = categoryPicked ? nil : CategoryModels.current
        guard SmartLabels.wantsModel(model, for: title, in: account, excluding: original?.id) else {
            return show(guess, for: normalized)
        }
        heldGuess = HeldGuess(guess: guess, title: normalized)
        let typed = title
        let excluded = original?.id
        modelTask = Task {
            let refined = await SmartLabels.guess(for: typed, in: account, excluding: excluded, model: model, budget: SmartLabels.editorBudget)
            guard !Task.isCancelled, heldGuess?.title == normalized else { return }
            heldGuess = nil
            // Dropped if the title has changed since; moving on from it
            // guesses again.
            guard ExpenseQuery.normalized(title) == normalized else { return }
            show(refined, for: normalized)
        }
    }

    /// Shows a guess: the category now and the payment method a beat later,
    /// never over a label the user chose.
    private func show(_ guess: SmartSuggester.LabelGuess, for normalized: String) {
        guessedTitle = normalized
        let fillsCategory = !categoryPicked && categoryID != guess.categoryID
        if fillsCategory {
            withAnimation(.snappy(duration: 0.25)) { categoryID = guess.categoryID }
        }
        guard !paymentPicked, paymentMethodID != guess.paymentMethodID else { return }
        // The category lands first, the payment method a beat later, so the
        // guess reads as two decisions rather than one jump.
        let pending = PendingPayment(methodID: guess.paymentMethodID, title: normalized)
        pendingPayment = pending
        Task { @MainActor in
            if fillsCategory { try? await Task.sleep(for: Self.paymentGuessDelay) }
            applyPendingPayment(pending)
        }
    }

    /// Shows a waiting payment guess, unless the user has since picked a
    /// method or changed the title it was guessed for.
    private func applyPendingPayment(_ pending: PendingPayment? = nil) {
        guard let current = pendingPayment, pending == nil || pending == current else { return }
        pendingPayment = nil
        guard !paymentPicked, current.title == guessedTitle else { return }
        withAnimation(.snappy(duration: 0.25)) { paymentMethodID = current.methodID }
    }

    /// Loads the on-device model while the title is typed, when it may be
    /// asked about it.
    private func prewarmCategoryModel() {
        guard store.preferences.smartSuggestionsEnabled, !categoryPicked, let account else { return }
        SmartLabels.prewarm(CategoryModels.current, for: account)
    }

    /// Save never waits for the model: a guess still held back is filled in
    /// as the history and word rules made it.
    private func applyHeldGuess() {
        modelTask?.cancel()
        guard let held = heldGuess else { return }
        heldGuess = nil
        guard held.title == ExpenseQuery.normalized(title) else { return }
        guessedTitle = held.title
        if !categoryPicked { categoryID = held.guess.categoryID }
        if !paymentPicked { paymentMethodID = held.guess.paymentMethodID }
    }

    // MARK: Receipt

    private func openReceiptScanner() {
        focus = nil
        ReceiptScanner.prewarm()
    }

    /// Reads a scanned receipt, then fills in what it found. Nothing is
    /// saved: the person checks the fields and taps Save.
    private func readReceipt(_ source: ReceiptScanner.Source) {
        receiptTask?.cancel()
        focus = nil
        readingReceipt = true
        let before = (title: title, amount: amountDisplay, date: date)
        let calendar = store.preferences.calendar
        receiptTask = Task {
            let draft = await ReceiptScanner.read(source, calendar: calendar)
            guard !Task.isCancelled, finished == 0 else { return }
            readingReceipt = false
            guard draft.isReceipt else {
                receiptNotFound = true
                return
            }
            fill(from: draft, over: before)
        }
    }

    /// Fills in the receipt's merchant, total and day, leaving any field
    /// the person changed while it was read. The merchant becomes the
    /// title, so Smart Suggestions then guess its labels as for a typed one.
    private func fill(from draft: ReceiptDraft, over before: (title: String, amount: String, date: Date)) {
        withAnimation(.snappy(duration: 0.25)) {
            if let merchant = draft.merchant, title == before.title { title = merchant }
            if let total = draft.total, amountDisplay == before.amount {
                amountDisplay = AmountInput.field(for: total, currencyCode: currencyCode)
                amountSeed = nil
            }
            if let day = draft.day, date == before.date,
               let filled = day.date(keepingTimeOf: date, calendar: store.preferences.calendar) {
                date = filled
            }
            receiptNote = draft.isInOtherCurrency(than: currencyCode)
                ? "Filled in from your receipt, which shows \(draft.currencyCode ?? ""). Keaser records amounts in \(currencyCode), so check the amount before saving."
                : "Filled in from your receipt. Check the details before saving."
        }
        focus = nil
        guessLabels()
        AccessibilityNotification.Announcement("Filled in from your receipt").post()
    }

    private func save() {
        guard canSave, let amount else { return }
        applyHeldGuess()
        applyPendingPayment()
        var expense = original ?? Expense(title: "", amount: 0)
        expense.title = title
        expense.amount = amount
        expense.categoryID = categoryID
        expense.paymentMethodID = paymentMethodID
        expense.date = date
        focus = nil
        store.saveExpense(expense, in: accountID)
        if isNew { IntentDonations.addedInApp(expense, accountID: accountID, store: store) }
        finished += 1
        dismiss()
    }

    private func delete() {
        guard let original else { return }
        store.deleteExpense(original.id, in: accountID)
        finished += 1
        dismiss()
    }
}

/// The note under the card once a receipt filled it in, set like a list
/// section's footer. On iOS 26 and later Home's + button shows blurred
/// through the glass sheet at the trailing edge, level with the note, as
/// in the reference; the note's lines wrap before they reach it.
private struct ReceiptNote: View {
    let text: String

    /// The + button and its blur, measured from the note's trailing edge.
    private static var trailingClearance: CGFloat {
        if #available(iOS 26.0, *) { 72 } else { 0 }
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.trailing, Self.trailingClearance)
            .transition(.opacity)
    }
}

/// A labelled row of the editor card: the label on the leading side and the
/// control on the trailing side, or the control under the label at
/// accessibility text sizes. The control carries the label for VoiceOver
/// unless `speaksLabel` is set.
private struct EditorField<Control: View>: View {
    let label: String
    /// True for a text field, which takes the rest of the row itself.
    var fillsRow = false
    var speaksLabel = false
    @ViewBuilder var control: Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ label: String, fillsRow: Bool = false, speaksLabel: Bool = false, @ViewBuilder control: () -> Control) {
        self.label = label
        self.fillsRow = fillsRow
        self.speaksLabel = speaksLabel
        self.control = control()
    }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .fixedSize()
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
                .accessibilityHidden(!speaksLabel)
            if !stacked && !fillsRow {
                Spacer(minLength: 8)
            }
            control
        }
        .padding(.vertical, stacked ? 10 : 0)
    }
}

/// A past expense offered by Smart Suggestions.
private struct SuggestionRow: View {
    let expense: Expense
    let symbol: String
    let currencyCode: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the amount goes under the title, so neither
        // is cut short.
        let stacked = dynamicTypeSize.isAccessibilitySize
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolTile(symbol: symbol, size: 30, background: .homeSuggestionTile)
                (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 12))) {
                    Text(expense.title)
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .lineLimit(stacked ? 3 : 1)
                    if !stacked {
                        Spacer(minLength: 8)
                    }
                    Text(MoneyFormat.string(expense.amount, currencyCode: currencyCode))
                        .font(.body)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .lineLimit(1)
                }
                if stacked {
                    Spacer(minLength: 0)
                }
                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowButtonStyle())
        .accessibilityLabel("Use \(expense.title), \(MoneyFormat.string(expense.amount, currencyCode: currencyCode))")
    }
}

/// The trailing value of a menu row: "None" with up and down chevrons. At
/// accessibility sizes the value has its own line under the label and wraps
/// there rather than being cut short.
private struct MenuValueLabel: View {
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.body)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
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
}
