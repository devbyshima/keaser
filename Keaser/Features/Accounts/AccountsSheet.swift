import KeaserKit
import SwiftUI
import UIKit

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

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        VStack(spacing: 0) {
            HomeSheetHeader(title: "Accounts") {
                HomeCircleButton(symbol: "xmark", accessibilityLabel: "Close", tint: Color(white: 0.72)) { dismiss() }
            } trailing: {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.smooth(duration: 0.3)) { editMode = isEditing ? .inactive : .active }
                }
                .keaserGlassButtonStyle()
                .disabled(store.accounts.isEmpty)
            }
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
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(deletionMessage(for: account))
        }
        .sheet(isPresented: $isAddingAccount) {
            AddAccountSheet()
        }
        .sheet(isPresented: $paywallShown) {
            PaywallView(highlighting: .multipleAccounts)
        }
        .onChange(of: store.accounts.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
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
                    AccountsCardShape(isFirst: index == 0, isLast: index == store.accounts.count - 1)
                        .fill(Color.keaserCardRaised)
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
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(true)
                .moveDisabled(true)

            Button(action: addAccount) {
                Text("Add Account")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: HomeSheetMetrics.cardRadius, style: .continuous)
                    .fill(Color.keaserCardRaised)
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
        UISelectionFeedbackGenerator().selectionChanged()
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
        let notion = account.isNotionLinked ? " The linked Notion database is not changed." : ""
        return count == 0
            ? "This account will be deleted. This cannot be undone.\(notion)"
            : "This account and \(expenses) will be deleted. This cannot be undone.\(notion)"
    }
}

/// One account in the switcher.
private struct AccountRow: View {
    let account: Account
    let isSelected: Bool
    let isEditing: Bool
    let showsSeparator: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "person.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .frame(width: 24)
                Text(account.name)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected && !isEditing {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.keaserPrimaryText)
                        .transition(.opacity)
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 24)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                HomeRowSeparator(leading: 62)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A card split across list rows: the first row rounds the top corners, the
/// last row the bottom ones, so separate rows read as one card.
private struct AccountsCardShape: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let r = HomeSheetMetrics.cardRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? r : 0,
            bottomLeadingRadius: isLast ? r : 0,
            bottomTrailingRadius: isLast ? r : 0,
            topTrailingRadius: isFirst ? r : 0,
            style: .continuous
        )
        .path(in: rect)
    }
}
