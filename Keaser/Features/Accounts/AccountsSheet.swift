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
                // Semibold, as the reference draws Edit.
                .homeSheetHeaderButton(confirms: true)
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
                    CardRowBackground(position: CardPosition(index: index, count: store.accounts.count), fill: .homeSheetCard)
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
                .frame(height: AccountsMetrics.cardSpacing)
                .accessibilityHidden(true)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(true)
                .moveDisabled(true)

            Button(action: addAccount) {
                Text("Add Account")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: AccountsMetrics.addRowHeight, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                CardRowBackground(position: .single, fill: .homeSheetCard)
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
        .contentMargins(.top, HomeSheetMetrics.contentTop - KeaserMetrics.sheetScrollEdge, for: .scrollContent)
        .keaserSheetScrollEdge()
        .keaserReadableScrollContent()
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
        let leading: CGFloat = isLarge ? (isEditing ? 0 : 16) : AccountsMetrics.tileLeading
        let trailing: CGFloat = isLarge && isEditing ? 0 : AccountsMetrics.trailing
        // The separator starts under the name.
        let separatorLeading: CGFloat = isLarge ? leading : AccountsMetrics.nameLeading
        Button(action: action) {
            HStack(spacing: AccountsMetrics.tileSpacing) {
                if !isLarge {
                    // A point larger than the name, as the reference draws it.
                    Image(systemName: "person.fill")
                        .keaserFont(18, weight: .medium, relativeTo: .body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .frame(width: AccountsMetrics.tileSize, height: AccountsMetrics.tileSize)
                        .background(
                            Color.homeSheetTile,
                            in: RoundedRectangle(cornerRadius: AccountsMetrics.tileRadius, style: .continuous)
                        )
                        .accessibilityHidden(true)
                }
                // Medium, as the reference draws account names.
                Text(account.name)
                    .font(.body.weight(.medium))
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
            .frame(minHeight: AccountsMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                KeaserRowSeparator(leading: separatorLeading, thickness: AccountsMetrics.separatorThickness)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Accounts sheet's cards. On iOS 26 and later they are the
/// reference's, measured in the sheet's own points: a floating sheet is
/// drawn at 96%, so the recording's 218 and 150 pixel cards, 101 pixels
/// apart, are 76 and 52pt with 35pt between them (read at 3 pixels a point
/// they had come out 72, 49 and 34, and the rows 4% short). Before iOS 26
/// the attached sheet is drawn at full size, so it keeps the recording's
/// pixels at 3 a point.
private enum AccountsMetrics {
    private static var isFloatingSheet: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    /// An account's row.
    static var rowHeight: CGFloat { isFloatingSheet ? 76 : 73 }
    /// The Add Account row.
    static var addRowHeight: CGFloat { isFloatingSheet ? 52 : 50 }
    /// Between the accounts card and the Add Account card.
    static var cardSpacing: CGFloat { isFloatingSheet ? 35 : 34 }
    /// The symbol's tile (white in light mode, none in dark mode), its
    /// corners, its inset from the card's edge and the gap to the name.
    static var tileSize: CGFloat { isFloatingSheet ? 38 : 36 }
    static var tileRadius: CGFloat { isFloatingSheet ? 12 : 11.5 }
    static var tileLeading: CGFloat { isFloatingSheet ? 16 : 15 }
    static let tileSpacing: CGFloat = 12
    /// Where the name starts, and the separator under it.
    static var nameLeading: CGFloat { tileLeading + tileSize + tileSpacing }
    /// From the checkmark to the card's edge.
    static var trailing: CGFloat { isFloatingSheet ? 16 : 15 }
    /// The reference's separator between accounts: two pixels in both
    /// appearances, where the shared hairline is one on black and three on
    /// white.
    static let separatorThickness: CGFloat = 2 / 3
}
