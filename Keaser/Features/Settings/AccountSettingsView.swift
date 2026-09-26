import KeaserKit
import SwiftUI

/// Name, labels, Notion link and deletion for one account.
struct AccountSettingsView: View {
    let accountID: UUID

    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let account = store.account(id: accountID) {
                content(for: account)
            } else {
                // Deleted (possibly from another screen): nothing left to show.
                Color.clear
            }
        }
        .settingsPage("Account Settings")
    }

    private func content(for account: Account) -> some View {
        List {
            Section {
                Button {
                    draftName = account.name
                    isRenaming = true
                } label: {
                    SettingsRow(symbol: "person.fill", title: "Account Name", value: account.name, hasDisclosure: false)
                }
                .cardRow(.single)
                .accessibilityHint("Renames the account")
            }

            Section {
                NavigationLink(value: SettingsPage.labels(.category, accountID: account.id)) {
                    SettingsRow(symbol: "tag.fill", title: "Categories")
                }
                .cardRow(.first)
                NavigationLink(value: SettingsPage.labels(.paymentMethod, accountID: account.id)) {
                    SettingsRow(symbol: "creditcard.fill", title: "Payment Methods")
                }
                .cardRow(.last)
            }

            if account.notion != nil {
                // Card fill and hairlines for rows that do not bring their own.
                NotionAccountSection(accountID: account.id)
                    .listRowBackground(Color.settingsCard)
                    .listRowSeparatorTint(Color.keaserSeparator)
            }

            Section {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Text("Delete This Account")
                        .font(.body)
                        .foregroundStyle(Color.keaserDestructive)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cardRow(.single, insets: .settingsTextRow)
            } footer: {
                SettingsFootnote("This will remove all expenses, payments, and categories associated with this account.")
            }
        }
        .settingsListStyle()
        .alert("Account Name", isPresented: $isRenaming) {
            TextField("Account Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.renameAccount(account.id, to: draftName) }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a new name for this account.")
        }
        .confirmationDialog("Delete \u{201C}\(account.name)\u{201D}?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                dismiss()
                store.deleteAccount(account.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage(for: account))
        }
    }

    private func deleteMessage(for account: Account) -> String {
        let count = account.expenses.count
        let expenses = count == 1 ? "1 expense" : "\(count) expenses"
        return "Its \(expenses), categories and payment methods will be removed from this iPhone. This cannot be undone."
    }
}
