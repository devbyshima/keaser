import KeaserKit
import SwiftUI

/// New Expense and Edit Expense: title, amount, category, payment method and
/// date on one card, with Smart Suggestions under the title while typing,
/// and the photos of its receipts under the card.
struct ExpenseEditorView: View {
    let accountID: UUID
    /// Nil when creating.
    let original: Expense?
    /// Called instead of dismissing the sheet when Cancel, Save or Delete
    /// ends the edit: the expense details use it to come back into view.
    let onClose: (() -> Void)?
    /// New Expense opened by the Scan Receipt control: the document camera
    /// (or the photo picker) comes up at once, and the scan fills the card.
    let scansReceipt: Bool

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
    /// Receipt reading: while a receipt is read, what the note under the
    /// card says once it filled the fields in, and whether a scan turned
    /// out not to be a receipt.
    @State private var readingReceipt = false
    @State private var receiptNote: String?
    @State private var receiptNotFound = false
    /// The photos kept with the expense, oldest first: the ones it has and
    /// ones attached here, in memory until Save.
    @State private var receipts: [ReceiptImageSource]
    /// Captures being made ready to keep (and read); Save waits for them.
    @State private var preparingReceipts = 0
    @State private var receiptTasks: [Task<Void, Never>] = []
    /// The camera or photo picker showing, and what for.
    @State private var capture: ReceiptCaptureRequest?
    @State private var viewing: ReceiptViewing?
    @State private var receiptToRemove: ReceiptImageSource?
    @State private var receiptsRemoved = 0
    @State private var receiptNotSaved = false
    @State private var date: Date
    /// Set once the person picks a date themselves; a receipt's day only
    /// fills a date still as the editor opened it.
    @State private var datePicked: Bool
    @State private var confirmingDelete = false
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

    private static let receiptsID = "receipts"

    init(accountID: UUID, expense: Expense? = nil, scansReceipt: Bool = false, onClose: (() -> Void)? = nil) {
        self.accountID = accountID
        self.original = expense
        self.onClose = onClose
        self.scansReceipt = scansReceipt && expense == nil
        _receipts = State(initialValue: expense?.receipts.map(ReceiptImageSource.saved) ?? [])
        _datePicked = State(initialValue: expense != nil)
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0 && preparingReceipts == 0
    }

    private var suggestions: [Expense] {
        guard store.preferences.smartSuggestionsEnabled, focus == .title, !title.isEmpty, let account else { return [] }
        return SmartSuggester.suggestions(for: title, in: account.expenses, excluding: original?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: isNew ? "New Expense" : "Edit Expense") {
                Button("Cancel", action: close)
                    .homeSheetHeaderButton()
                    .accessibilityShowsLargeContentViewer()
            } trailing: {
                Button("Save", action: save)
                    .homeSheetHeaderButton(confirms: true)
                    .disabled(!canSave)
                    .accessibilityShowsLargeContentViewer()
            }
            .homeSheetHeader(top: EditorMetrics.headerTop)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 16) {
                        card
                        ReceiptAttachmentSection(
                            receipts: receipts,
                            isPreparing: preparingReceipts > 0,
                            onChoose: { startCapture($0, for: .attach) },
                            onOpen: { viewing = ReceiptViewing(receipts: receipts, start: $0) },
                            onRemove: { receiptToRemove = $0 }
                        )
                        .id(Self.receiptsID)
                        .confirmationDialog(
                            "Remove Receipt?",
                            isPresented: Binding(get: { receiptToRemove != nil }, set: { if !$0 { receiptToRemove = nil } }),
                            titleVisibility: .visible,
                            presenting: receiptToRemove
                        ) { source in
                            Button("Remove Receipt", role: .destructive) { removeReceipt(source) }
                            Button("Cancel", role: .cancel) {}
                        } message: { source in
                            Text(ReceiptViewer.removalMessage(for: source, in: receipts))
                        }
                        if let receiptNote {
                            ReceiptNote(text: receiptNote)
                        }
                        if !isNew {
                            deleteButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, EditorMetrics.contentTop)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .keaserReadableScrollContent()
                #if DEBUG
                // `-KeaserExpenseScroll receipts` scrolls down to the receipts,
                // to screenshot the gallery under the card.
                .task {
                    guard DebugLaunch.string("KeaserExpenseScroll") == "receipts" else { return }
                    try? await Task.sleep(for: .milliseconds(900))
                    scroller.scrollTo(Self.receiptsID, anchor: .top)
                }
                #endif
            }
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
            // `-KeaserReceiptAttached <n>` starts New Expense with n sample
            // receipts attached; `-KeaserReceiptViewer <i>` then opens the
            // i-th full screen.
            if isNew, let count = DebugLaunch.string("KeaserReceiptAttached") {
                receipts = ReceiptImage.debugSamples(count).map { .unsaved(UnsavedReceipt(jpeg: $0)) }
            }
            if let number = DebugLaunch.int("KeaserReceiptViewer"), receipts.indices.contains(number - 1) {
                let shown = ReceiptViewing(receipts: receipts, start: number - 1)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    viewing = shown
                }
            }
            // `-KeaserReceipt <sample>` reads a sample receipt as if it had
            // just been scanned, so without the keyboard.
            if isNew, let source = ReceiptScanner.debugSource {
                if ReceiptScanner.holdsReading {
                    readingReceipt = true
                } else {
                    addReceipts(from: source, for: .scan)
                }
                return
            }
            // `-KeaserExpenseFocus none` keeps the keyboard down, to see
            // what sits under the card.
            if DebugLaunch.string("KeaserExpenseFocus") == "none" { return }
            #endif
            if scansReceipt {
                scanOnOpen()
                return
            }
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
            receiptTasks.forEach { $0.cancel() }
        }
        .receiptCapture($capture) { request in
            // The camera the Scan Receipt control opened was closed: the
            // expense can still be typed in.
            if request.purpose == .scan, scansReceipt, title.isEmpty { focus = .title }
        } onCapture: { request, source in
            addReceipts(from: source, for: request.purpose)
        }
        .fullScreenCover(item: $viewing) { shown in
            ReceiptViewer(shown, title: title) { removeReceipt($0) }
        }
        .sensoryFeedback(.success, trigger: receiptsRemoved)
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
        .alert("Receipt Not Saved", isPresented: $receiptNotSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Keaser couldn't keep a receipt photo, so nothing was saved. Try again, or remove the receipts to save the expense without them.")
        }
    }

    // MARK: Card

    private var card: some View {
        KeaserCard(fill: .homeSheetCard) {
            titleRow
            ForEach(suggestions) { suggestion in
                separator
                SuggestionRow(
                    expense: suggestion,
                    symbol: account?.symbol(for: suggestion) ?? ExpenseCategory.fallbackSymbol,
                    currencyCode: currencyCode
                ) {
                    apply(suggestion)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            separator
            amountRow
            separator
            categoryRow
            separator
            paymentRow
            separator
            dateRow
        }
        .animation(.snappy(duration: 0.25), value: suggestions.map(\.id))
    }

    private var separator: some View {
        KeaserRowSeparator(overlapsRows: EditorMetrics.separatorsOverlapRows)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Title").foregroundStyle(EditorMetrics.placeholder))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .focused($focus, equals: .title)
                // With a prompt, the field's title is not read out on its own.
                .accessibilityLabel("Title")
                .textInputAutocapitalization(.sentences)
                .onSubmit { focus = .amount }
            // An add control like the receipt area's, gone at the cap.
            if isNew, readingReceipt || ReceiptList.room(after: receipts.count) > 0 {
                ReceiptScanButton(isReading: readingReceipt) { startCapture($0, for: .scan) }
            }
        }
        .editorRow(height: EditorMetrics.titleRowHeight)
    }

    private var amountRow: some View {
        EditorField("Amount", fillsRow: true) {
            TextField(
                "Amount",
                text: $amountDisplay,
                prompt: Text(MoneyFormat.string(0, currencyCode: currencyCode)).foregroundStyle(EditorMetrics.placeholder)
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
            DatePicker("Date", selection: Binding(get: { date }, set: { date = $0; datePicked = true }), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
        .editorRow(height: EditorMetrics.dateRowHeight)
    }

    /// Delete Expense under the card, shown only while no field is being
    /// typed in: the reference's Edit Expense opens with the keyboard up and
    /// no button under the card. Rows keep Delete in their menu and swipe.
    private var deleteButton: some View {
        let shows = focus == nil
        return KeaserActionCard("Delete Expense", role: .destructive) {
            focus = nil
            confirmingDelete = true
        }
        .opacity(shows ? 1 : 0)
        .allowsHitTesting(shows)
        .accessibilityHidden(!shows)
        .animation(.easeOut(duration: 0.15), value: shows)
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

    /// Opens the camera or the photo picker for as many receipts as the
    /// expense still has room for: from the title row's scanner (`.scan`)
    /// or the receipt area (`.attach`).
    private func startCapture(_ source: ReceiptCaptureRequest.Source, for purpose: ReceiptCaptureRequest.Purpose) {
        focus = nil
        let room = ReceiptList.room(after: receipts.count)
        guard room > 0 else { return }
        if wantsReading { ReceiptScanner.prewarm() }
        capture = ReceiptCaptureRequest(source: source, purpose: purpose, limit: room)
    }

    /// The Scan Receipt control: the camera, or the photo picker where
    /// there is none, once the sheet is up (a cover asked for while the
    /// sheet is still arriving is not shown).
    private func scanOnOpen() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard finished == 0 else { return }
            startCapture(ReceiptCaptureRequest.hasCamera ? .camera : .library, for: .scan)
        }
    }

    private var titleIsEmpty: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var amountIsEmpty: Bool { (amount ?? 0) == 0 }

    /// Whether a receipt added now is read: only while the title or the
    /// amount is empty (`ReceiptFill.wantsReading`).
    private var wantsReading: Bool {
        ReceiptFill.wantsReading(titleIsEmpty: titleIsEmpty, amountIsEmpty: amountIsEmpty)
    }

    /// Keeps what was captured with the expense, each page of a scan and
    /// each picked photo a receipt of its own, in order, as many as fit.
    /// While the title or the amount is empty they are also read, together
    /// as one receipt, and fill in only what is still empty (`fill`). A
    /// scan from the title row that is not a receipt is not kept, and the
    /// person is told; photos added in the receipt area are kept either
    /// way. Nothing is saved: the person checks the fields and taps Save.
    private func addReceipts(from source: ReceiptScanner.Source, for purpose: ReceiptCaptureRequest.Purpose) {
        focus = nil
        let reads = wantsReading
        let room = ReceiptList.room(after: receipts.count)
        let calendar = store.preferences.calendar
        preparingReceipts += 1
        if reads { readingReceipt = true }
        let task = Task {
            defer { preparingReceipts -= 1 }
            let pages = await ReceiptScanner.pages(of: source)
            // The photos are made ready to keep while the text is read.
            async let kept = ReceiptImage.jpegs(of: Array(pages.prefix(room)))
            var draft: ReceiptDraft?
            if reads {
                if case .lines(let lines) = source {
                    draft = await ReceiptScanner.read(lines: [lines], calendar: calendar)
                } else {
                    draft = await ReceiptScanner.read(pages, calendar: calendar)
                }
            }
            let jpegs = await kept
            guard !Task.isCancelled, finished == 0 else { return }
            if reads { readingReceipt = false }
            let isReceipt = draft?.isReceipt ?? false
            if purpose == .scan, reads, !isReceipt {
                receiptNotFound = true
                return
            }
            attach(jpegs)
            if let draft, isReceipt { fill(from: draft) }
        }
        receiptTasks.append(task)
    }

    private func attach(_ jpegs: [Data]) {
        let before = receipts.count
        withAnimation(.smooth(duration: 0.3)) {
            receipts = ReceiptList.adding(jpegs.map { .unsaved(UnsavedReceipt(jpeg: $0)) }, to: receipts)
        }
        let added = receipts.count - before
        guard added > 0 else { return }
        AccessibilityNotification.Announcement(added == 1 ? "Receipt attached" : "\(added) receipts attached").post()
    }

    /// Takes one photo off the expense. A kept one is deleted once the edit
    /// is saved (`releaseRemovedReceipts`); one attached here was never
    /// written.
    private func removeReceipt(_ source: ReceiptImageSource) {
        withAnimation(.smooth(duration: 0.3)) { receipts.removeAll { $0 == source } }
        receiptsRemoved += 1
        AccessibilityNotification.Announcement("Receipt removed").post()
    }

    /// Fills in the receipt's merchant, total and day where the card is
    /// still empty (`ReceiptFill`), never over what the person typed or
    /// picked. The merchant becomes the title, so Smart Suggestions then
    /// guess its labels as for a typed one.
    private func fill(from draft: ReceiptDraft) {
        let fill = ReceiptFill(draft, titleIsEmpty: titleIsEmpty, amountIsEmpty: amountIsEmpty, dateIsUntouched: !datePicked)
        guard !fill.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            if let merchant = fill.title { title = merchant }
            if let total = fill.total {
                amountDisplay = AmountInput.field(for: total, currencyCode: currencyCode)
                amountSeed = nil
            }
            if let day = fill.day, let filled = day.date(keepingTimeOf: date, calendar: store.preferences.calendar) {
                date = filled
            }
            receiptNote = draft.note(recordingIn: currencyCode)
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
        guard let kept = writeReceipts() else {
            receiptNotSaved = true
            return
        }
        expense.receipts = kept
        focus = nil
        store.saveExpense(expense, in: accountID)
        releaseRemovedReceipts()
        if isNew { IntentDonations.addedInApp(expense, accountID: accountID, store: store) }
        finished += 1
        close()
    }

    /// The expense's receipts as saved, the new ones written to the
    /// Receipts folder now; nil, with nothing left written, when one
    /// cannot be.
    private func writeReceipts() -> [ReceiptPhoto]? {
        let folder = AppEnvironment.receipts
        var kept: [ReceiptPhoto] = []
        var written: [ReceiptPhoto] = []
        for source in receipts {
            switch source {
            case .saved(let photo):
                kept.append(photo)
            case .unsaved(let new):
                guard let photo = try? folder.add(new.jpeg) else {
                    folder.remove(written)
                    return nil
                }
                kept.append(photo)
                written.append(photo)
            }
        }
        return kept
    }

    /// The receipts this edit took off: their files go once the change is
    /// on disk. If it could not be written they wait for the clean-up at a
    /// later launch, as a deleted expense's do.
    private func releaseRemovedReceipts() {
        guard let original, store.lastSaveError == nil else { return }
        let released = ReceiptList.released(from: original.receipts, inUse: store.database.receiptPhotos)
        guard !released.isEmpty else { return }
        let folder = AppEnvironment.receipts
        Task { await ReceiptImage.remove(released, from: folder) }
    }

    private func delete() {
        guard let original else { return }
        store.deleteExpense(original.id, in: accountID)
        finished += 1
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
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

/// The editor's layout. On iOS 26 and later it is the reference's, measured
/// in the sheet's own points: with the keyboard up, iOS draws the floating
/// sheet at 96% (in the reference as here), so lengths read straight off the
/// recording's pixels come out 4% short. Before iOS 26 the sheet keeps its
/// earlier layout.
private enum EditorMetrics {
    private static var isFloatingSheet: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    /// Above Cancel and Save, which are 44pt glass capsules there.
    static var headerTop: CGFloat { isFloatingSheet ? 16 : HomeSheetMetrics.headerTop }
    /// Between the header and the card.
    static var contentTop: CGFloat { isFloatingSheet ? 45 : HomeSheetMetrics.contentTop }
    static var titleRowHeight: CGFloat { isFloatingSheet ? 51.5 : 50 }
    /// Amount, Category and Payment.
    static var rowHeight: CGFloat { isFloatingSheet ? 52 : 50 }
    static var dateRowHeight: CGFloat { isFloatingSheet ? 67 : 64 }
    /// The reference's hairlines sit on the boundary between two rows
    /// rather than add to their height.
    static var separatorsOverlapRows: Bool { isFloatingSheet }
    /// The Title and $0.00 prompts.
    static var placeholder: Color { isFloatingSheet ? .homeSheetPlaceholder : .keaserTertiaryText }
}

private extension View {
    func editorRow(height: CGFloat = EditorMetrics.rowHeight) -> some View {
        padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}
