import KeaserKit
import SwiftUI

/// Name, labels and deletion for one account.
struct AccountSettingsView: View {
    let accountID: UUID

    @Environment(KeaserStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmsDelete = false
    /// Counts renames and the deletion, for the same success haptic as
    /// deleting an expense.
    @State private var committedChanges = 0

    var body: some View {
        Group {
            if let account = store.account(id: accountID) {
                content(for: account)
            } else {
                // Deleted (from Home's Accounts sheet, or on another device):
                // nothing left to show, and the Settings tab pops the page.
                Color.clear
            }
        }
        .settingsPage("Account Settings")
        .sensoryFeedback(.success, trigger: committedChanges)
        // A route (a widget, Siri, Spotlight) closes the rename alert and
        // the delete dialog, which would hide the tab it selects.
        .onChange(of: router.modalReset) {
            isRenaming = false
            confirmsDelete = false
        }
        #if DEBUG
        // `-KeaserSettingsAlert rename` opens the rename alert, for
        // screenshots (once a launch, not on every return to the page).
        .task {
            guard DebugLaunch.string("KeaserSettingsAlert") == "rename",
                  let account = store.account(id: accountID),
                  DebugLaunch.firstTime("renameAlert")
            else { return }
            try? await Task.sleep(for: .milliseconds(600))
            draftName = account.name
            isRenaming = true
        }
        #endif
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
        .alert("Rename Account", isPresented: $isRenaming) {
            TextField("Account Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                store.renameAccount(account.id, to: draftName)
                if store.account(id: account.id)?.name != account.name { committedChanges += 1 }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a display name for this account.")
        }
        .confirmationDialog("Delete \u{201C}\(account.name)\u{201D}?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                committedChanges += 1
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
