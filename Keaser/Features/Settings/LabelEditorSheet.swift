import KeaserKit
import SwiftUI

/// New or Edit Category / Payment Method: a large preview of the chosen
/// symbol, the name, and a grid of symbols to pick from.
struct LabelEditorSheet: View {
    let kind: LabelKind
    let accountID: UUID
    /// Nil for a new label.
    let existing: LabelItem?
    /// Called after a save or a deletion, so the list can play its haptic
    /// (this sheet is already on its way out).
    let onCommit: () -> Void

    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String?
    @State private var confirmsDelete = false
    @FocusState private var nameFocused: Bool

    init(kind: LabelKind, accountID: UUID, existing: LabelItem?, startingSymbol: String?, onCommit: @escaping () -> Void = {}) {
        self.kind = kind
        self.accountID = accountID
        self.existing = existing
        self.onCommit = onCommit
        _name = State(initialValue: existing?.name ?? "")
        _symbol = State(initialValue: existing?.symbol ?? startingSymbol)
    }

    /// The kind's symbols, plus the label's own when it is not one of them
    /// (a label imported from Notion, say), so it still shows selected.
    private var choices: [SymbolChoice] {
        let base = kind.choices
        guard let existing, !base.contains(where: { $0.symbol == existing.symbol }) else { return base }
        return [SymbolChoice(existing.symbol, existing.name)] + base
    }

    private var suggestion: String? {
        choices.first { $0.symbol == symbol }?.suggestedName
    }

    private var resolvedName: String? {
        LabelNaming.resolvedName(typed: name, suggestion: suggestion)
    }

    private var isNameTaken: Bool {
        guard let resolvedName else { return false }
        let others = store.labels(kind, in: accountID).map { (id: $0.id, name: $0.name) }
        return LabelNaming.isTaken(resolvedName, by: others, excluding: existing?.id)
    }

    private var canSave: Bool {
        symbol != nil && resolvedName != nil && !isNameTaken
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    preview
                        .padding(.top, 38)
                    nameField
                        .padding(.top, 32)
                    if isNameTaken {
                        Text("You already have a \(kind.singularTitle.lowercased()) with this name.")
                            .font(.footnote)
                            .foregroundStyle(Color.keaserSecondaryText)
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                    symbolGrid
                        .padding(.top, 24)
                    if existing != nil {
                        deleteButton
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, KeaserMetrics.screenPadding)
                .padding(.bottom, 24)
                .animation(.snappy(duration: 0.2), value: isNameTaken)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "New \(kind.singularTitle)" : "Edit \(kind.singularTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HeaderIconButton("xmark", label: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmIconButton(isEnabled: canSave, action: save)
                }
            }
            .confirmationDialog("Delete \u{201C}\(existing?.name ?? "")\u{201D}?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete \(kind.singularTitle)", role: .destructive) {
                    if let existing {
                        store.deleteLabel(kind, id: existing.id, in: accountID)
                        onCommit()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(kind == .category
                     ? "Expenses in this category are kept and become uncategorized."
                     : "Expenses paid this way are kept without a payment method.")
            }
        }
        .task {
            // The reference opens New with the keyboard up. Waiting for the
            // sheet to settle keeps the keyboard from fighting its animation.
            guard existing == nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            nameFocused = true
        }
        .keaserSheetChrome()
    }

    private var preview: some View {
        Image(systemName: symbol ?? "questionmark")
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 100, height: 100)
            .background(Color.settingsField, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .accessibilityHidden(true)
    }

    private var nameField: some View {
        TextField(suggestion ?? "Name", text: $name)
            .keaserFont(20, relativeTo: .title3)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { if canSave { save() } }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Color.settingsField, in: Capsule())
            .accessibilityLabel("Name")
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
            ForEach(choices) { choice in
                SymbolChoiceButton(choice: choice, isSelected: choice.symbol == symbol) {
                    withAnimation(.snappy(duration: 0.25)) { symbol = choice.symbol }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .background(Color.settingsField, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }

    private var deleteButton: some View {
        Button {
            confirmsDelete = true
        } label: {
            Text("Delete \(kind.singularTitle)")
                .font(.body)
                .foregroundStyle(Color.keaserDestructive)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.settingsField, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave, let symbol, let resolvedName else { return }
        let item = LabelItem(id: existing?.id ?? UUID(), name: resolvedName, symbol: symbol)
        store.saveLabel(item, kind: kind, in: accountID)
        onCommit()
        dismiss()
    }
}

/// One circle in the symbol grid; the selected one wears a ring.
private struct SymbolChoiceButton: View {
    let choice: SymbolChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: choice.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .padding(5)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.4 : 0), lineWidth: 3)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.suggestedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The round checkmark that confirms a sheet. On iOS 26 the system draws it
/// as a prominent glass button; before that, the shared `KeaserConfirmButton`
/// (white once there is something valid to save), as on New Account.
struct ConfirmIconButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "checkmark")
            }
            .disabled(!isEnabled)
            .accessibilityLabel("Save")
            // The checkmark glyph would otherwise make VoiceOver say "selected".
            .accessibilityRemoveTraits(.isSelected)
        } else {
            KeaserConfirmButton("Save", isEnabled: isEnabled, action: action)
        }
    }
}
