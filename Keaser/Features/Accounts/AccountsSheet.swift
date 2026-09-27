import KeaserKit
import SwiftUI

/// The account switcher: every account with a checkmark on the selected one,
/// and an Add Account row. Edit reorders and deletes.
struct AccountsSheet: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var accountToDelete: Account?
    @State private var isAddingAccount = false
    @State private var paywallShown = false
    @State private var selectedCount = 0
    @State private var deletedCount = 0

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Accounts") {
                KeaserCircleButton("xmark", label: "Close") { dismiss() }
                    .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            } trailing: {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.smooth(duration: 0.3)) { editMode = isEditing ? .inactive : .active }
                }
                .keaserGlassButtonStyle()
                .disabled(store.accounts.isEmpty)
                .accessibilityShowsLargeContentViewer()
            }
            .homeSheetHeader()
            list
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .keaserSheetChrome()
        .confirmationDialog(
            "Delete \u{201C}\(accountToDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { accountToDelete != nil }, set: { if !$0 { accountToDelete = nil } }),
            titleVisibility: .visible,
            presenting: accountToDelete
        ) { account in
            Button("Delete Account", role: .destructive) {
                withAnimation(.smooth(duration: 0.3)) { store.deleteAccount(account.id) }
                deletedCount += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(deletionMessage(for: account))
        }
        .sheet(isPresented: $isAddingAccount) {
            // A new account is selected as it is created; close both sheets
            // so Home shows it, as in the reference.
            AddAccountSheet(onCreated: { dismiss() })
        }
        .sheet(isPresented: $paywallShown) {
            PaywallView(highlighting: .multipleAccounts)
        }
        .onChange(of: store.accounts.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .sensoryFeedback(.selection, trigger: selectedCount)
        .sensoryFeedback(.success, trigger: deletedCount)
        #if DEBUG
        .onAppear {
            // `-KeaserAccountsEditing 1` opens in edit mode for screenshots.
            if DebugLaunch.int("KeaserAccountsEditing") == 1 { editMode = .active }
        }
        #endif
    }

    private var list: some View {
        List {
            ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(
                    account: account,
                    isSelected: account.id == store.selectedAccount?.id,
                    isEditing: isEditing,
                    showsSeparator: index < store.accounts.count - 1
                ) {
                    select(account)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(
                    CardRowBackground(position: CardPosition(index: index, count: store.accounts.count), fill: .keaserSheetCard)
                        .padding(.horizontal, 16)
                )
            }
            .onMove { source, destination in
                store.moveAccounts(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                accountToDelete = offsets.first.map { store.accounts[$0] }
            }

            Color.clear
                .frame(height: 34)
                .accessibilityHidden(true)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(true)
                .moveDisabled(true)

            Button(action: addAccount) {
                Text("Add Account")
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                CardRowBackground(position: .single, fill: .keaserSheetCard)
                    .padding(.horizontal, 16)
            )
            .deleteDisabled(true)
            .moveDisabled(true)
            .disabled(isEditing)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.editMode, $editMode)
        .contentMargins(.top, HomeSheetMetrics.contentTop, for: .scrollContent)
    }

    private func select(_ account: Account) {
        guard !isEditing else { return }
        store.selectAccount(account.id)
        selectedCount += 1
        dismiss()
    }

    /// A second account is Pro (Multiple Accounts).
    private func addAccount() {
        if store.accounts.isEmpty || pro.isPro {
            isAddingAccount = true
        } else {
            paywallShown = true
        }
    }

    private func deletionMessage(for account: Account) -> String {
        let count = account.expenses.count
        let expenses = count == 1 ? "its 1 expense" : "all \(count) of its expenses"
        return count == 0
            ? "This account will be deleted. This cannot be undone."
            : "This account and \(expenses) will be deleted. This cannot be undone."
    }
}

/// One account in the switcher.
private struct AccountRow: View {
    let account: Account
    let isSelected: Bool
    let isEditing: Bool
    let showsSeparator: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the decorative icon goes and the name lines
        // up with the Add Account row; in edit mode it also drops the side
        // margins, where the list adds its own controls. A name then keeps
        // enough width to wrap between words.
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let leading: CGFloat = isLarge ? (isEditing ? 0 : 16) : 22
        let trailing: CGFloat = isLarge && isEditing ? 0 : 24
        // The separator starts under the name.
        let separatorLeading: CGFloat = isLarge ? leading : 62
        Button(action: action) {
            HStack(spacing: 16) {
                if !isLarge {
                    Image(systemName: "person.fill")
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .frame(minWidth: 24)
                        .accessibilityHidden(true)
                }
                Text(account.name)
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(isLarge ? 3 : 1)
                Spacer(minLength: 8)
                if isSelected && !isEditing {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.keaserPrimaryText)
                        .transition(.opacity)
                        // The row itself carries the selected trait.
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                KeaserRowSeparator(leading: separatorLeading)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
