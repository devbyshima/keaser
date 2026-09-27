import KeaserKit
import SwiftUI

/// "Add Account": name a new account. A compact sheet sized like the
/// reference's New Account form.
struct AddAccountSheet: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var paywallShown = false
    @State private var createdCount = 0

    /// Called instead of dismissing this sheet once the account exists, so
    /// a presenter (the Accounts sheet) can close itself and this sheet
    /// together and the user lands straight in the new account.
    var onCreated: (() -> Void)?

    /// 320pt tall on screen, as in the reference. Before iOS 26 the sheet
    /// is attached to the bottom edge and its detent also covers the home
    /// indicator area, so it asks for less to end up the same height.
    private static var sheetHeight: CGFloat {
        if #available(iOS 26.0, *) { return 320 }
        return 294
    }

    /// A second account needs Pro (Multiple Accounts). Callers gate before
    /// presenting; this is the last check.
    private var needsPro: Bool { !store.accounts.isEmpty && !pro.isPro }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        form
            .frame(maxHeight: .infinity, alignment: .top)
            // The measured height fits the default text sizes; accessibility
            // sizes get room to grow instead of being cut off.
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(Self.sheetHeight)])
            .presentationDragIndicator(.hidden)
            .keaserSheetChrome()
            .sensoryFeedback(.success, trigger: createdCount)
            .sheet(isPresented: $paywallShown) {
                PaywallView(highlighting: .multipleAccounts)
            }
    }

    // MARK: Name form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            KeaserSheetHeader(title: "New Account") {
                KeaserCircleButton("xmark", label: "Close") {
                    nameFocused = false
                    dismiss()
                }
                .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            } trailing: {
                KeaserConfirmButton("Create Account", isEnabled: !trimmedName.isEmpty, action: create)
            }
            .homeSheetHeader()
            // The field below carries the same name for VoiceOver.
            Text("Account name")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.keaserSecondaryText)
                .padding(.leading, 32)
                .padding(.top, 17)
                .accessibilityHidden(true)
            TextField("Account name", text: $name, prompt: Text("E.g. Personal, Business").foregroundStyle(Color.keaserTertiaryText))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .focused($nameFocused)
                .accessibilityLabel("Account name")
                .textInputAutocapitalization(.words)
                .onSubmit(create)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color.homeSheetCard, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        guard !needsPro else { paywallShown = true; return }
        store.createAccount(name: trimmedName)
        createdCount += 1
        nameFocused = false
        if let onCreated { onCreated() } else { dismiss() }
    }
}
