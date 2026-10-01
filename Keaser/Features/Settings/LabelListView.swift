import KeaserKit
import SwiftUI

/// A category or payment method, whichever `LabelKind` the screen is for.
struct LabelItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
}

/// Categories or Payment Methods of one account: tap to edit, swipe to
/// delete, reorder from the context menu, + to add.
struct LabelListView: View {
    let kind: LabelKind
    let accountID: UUID
    var opening: Opening = .list

    /// What the screen shows when it first appears.
    enum Opening: Hashable {
        case list
        /// The New sheet.
        case newLabel
        /// The Edit sheet for the first label.
        case firstLabel
    }

    @Environment(KeaserStore.self) private var store
    @State private var editor: EditorTarget?
    @State private var pendingDelete: LabelItem?
    @State private var editMode: EditMode = .inactive
    @State private var didOpen = false
    /// Counts saves and deletions, for the same success haptic as deleting
    /// an expense.
    @State private var committedChanges = 0

    private enum EditorTarget: Identifiable {
        case new
        case edit(LabelItem)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let item): item.id.uuidString
            }
        }
    }

    var body: some View {
        let items = store.labels(kind, in: accountID)
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        // While reordering, taps belong to the edit controls.
                        guard !editMode.isEditing else { return }
                        editor = .edit(item)
                    } label: {
                        LabelRow(item: item)
                    }
                    .cardRow(CardPosition(index: index, count: items.count), insets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDelete = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Color.keaserDestructive)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editor = .edit(item) }
                        if items.count > 1 {
                            Button("Reorder", systemImage: "arrow.up.arrow.down") {
                                withAnimation { editMode = .active }
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    }
                }
                .onMove { source, destination in
                    store.moveLabels(kind, in: accountID, fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    // Edit mode's delete button: confirm like a swipe does.
                    if let index = offsets.first, items.indices.contains(index) { pendingDelete = items[index] }
                }
            }
        }
        .settingsListStyle()
        .environment(\.editMode, $editMode)
        .overlay {
            if items.isEmpty {
                EmptyStateView(
                    symbol: kind == .category ? "tag" : "creditcard",
                    title: "No \(kind.pluralTitle)",
                    message: "Tap + to add one."
                )
            }
        }
        .settingsPage(kind.pluralTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    HeaderIconButton("checkmark", label: "Done") {
                        withAnimation { editMode = .inactive }
                    }
                } else {
                    HeaderIconButton("plus", label: "New \(kind.singularTitle)") { editor = .new }
                }
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .new:
                LabelEditorSheet(kind: kind, accountID: accountID, existing: nil, startingSymbol: startingSymbol(items)) {
                    committedChanges += 1
                }
            case .edit(let item):
                LabelEditorSheet(kind: kind, accountID: accountID, existing: item, startingSymbol: item.symbol) {
                    committedChanges += 1
                }
            }
        }
        .sensoryFeedback(.success, trigger: committedChanges)
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete \(kind.singularTitle)", role: .destructive) {
                withAnimation { store.deleteLabel(kind, id: item.id, in: accountID) }
                committedChanges += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(deleteMessage(for: item))
        }
        .onAppear {
            guard !didOpen else { return }
            didOpen = true
            switch opening {
            case .list: break
            case .newLabel: editor = .new
            case .firstLabel: editor = items.first.map { .edit($0) }
            }
        }
    }

    private func startingSymbol(_ items: [LabelItem]) -> String? {
        LabelNaming.startingChoice(from: kind.choices, usedSymbols: Set(items.map(\.symbol)))?.symbol
    }

    private func deleteMessage(for item: LabelItem) -> String {
        let uses = store.expenseCount(using: item.id, kind: kind, in: accountID)
        let noun = uses == 1 ? "1 expense uses" : "\(uses) expenses use"
        switch kind {
        case .category:
            return uses == 0
                ? "No expenses use this category."
                : "\(noun) this category. They will be kept and become uncategorized."
        case .paymentMethod:
            return uses == 0
                ? "No expenses use this payment method."
                : "\(noun) this payment method. They will be kept without a payment method."
        }
    }
}

/// Symbol and name, as in the reference's Categories list.
private struct LabelRow: View {
    let item: LabelItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 16) {
            SettingsSymbol(symbol: item.symbol, size: 44, pointSize: 21)
            Text(item.name)
                .keaserFont(17, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Color.keaserPrimaryText)
                // At accessibility sizes a name of several words may wrap,
                // but a single long word ("Transportation") shrinks rather
                // than break in the middle.
                .lineLimit(dynamicTypeSize.isAccessibilitySize && item.name.contains(" ") ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.6 : 1)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 74)
        .cardSeparatorTrailing()
        .contentShape(Rectangle())
    }
}

extension KeaserStore {
    func labels(_ kind: LabelKind, in accountID: UUID) -> [LabelItem] {
        guard let account = account(id: accountID) else { return [] }
        switch kind {
        case .category: return account.categories.map { LabelItem(id: $0.id, name: $0.name, symbol: $0.symbol) }
        case .paymentMethod: return account.paymentMethods.map { LabelItem(id: $0.id, name: $0.name, symbol: $0.symbol) }
        }
    }

    func saveLabel(_ item: LabelItem, kind: LabelKind, in accountID: UUID) {
        saveLabel(id: item.id, name: item.name, symbol: item.symbol, kind: kind, in: accountID)
    }

    func deleteLabel(_ kind: LabelKind, id: UUID, in accountID: UUID) {
        switch kind {
        case .category: deleteCategory(id, in: accountID)
        case .paymentMethod: deletePaymentMethod(id, in: accountID)
        }
    }

    func moveLabels(_ kind: LabelKind, in accountID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        switch kind {
        case .category: moveCategories(in: accountID, fromOffsets: source, toOffset: destination)
        case .paymentMethod: movePaymentMethods(in: accountID, fromOffsets: source, toOffset: destination)
        }
    }

    func expenseCount(using labelID: UUID, kind: LabelKind, in accountID: UUID) -> Int {
        guard let account = account(id: accountID) else { return 0 }
        switch kind {
        case .category: return account.expenses.count { $0.categoryID == labelID }
        case .paymentMethod: return account.expenses.count { $0.paymentMethodID == labelID }
        }
    }
}
