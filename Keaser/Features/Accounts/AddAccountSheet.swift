import KeaserKit
import SwiftUI
import UIKit

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

    /// With the keyboard up (the name field is focused as the sheet opens)
    /// this puts the sheet's top edge where the reference's is, 951 pixels
    /// above the keyboard. Before iOS 26 the sheet is attached to the bottom
    /// edge and its detent also covers the home indicator area, so it asks
    /// for less to end up the same height.
    private static var sheetHeight: CGFloat {
        if #available(iOS 26.0, *) { return 300 }
        return 274
    }

    /// A second account needs Pro (Multiple Accounts). Callers gate before
    /// presenting; this is the last check.
    private var needsPro: Bool { !store.accounts.isEmpty && !pro.isPro }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        form
            .frame(maxHeight: .infinity, alignment: .top)
            .background { NewAccountMetrics.veil.ignoresSafeArea() }
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
                .font(.body.weight(.semibold))
                .foregroundStyle(NewAccountMetrics.label)
                .padding(.leading, 32)
                .padding(.top, NewAccountMetrics.labelTop)
                .accessibilityHidden(true)
            TextField("Account name", text: $name, prompt: Text("E.g. Personal, Business").foregroundStyle(NewAccountMetrics.placeholder))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .focused($nameFocused)
                .accessibilityLabel("Account name")
                .textInputAutocapitalization(.words)
                // A name, not prose: no corrections, and no suggestions bar
                // on the keyboard, as in the reference, which keeps the
                // sheet as low above it.
                .autocorrectionDisabled()
                .background(SpellCheckingDisabler())
                .onSubmit(create)
                .padding(.horizontal, 16)
                .frame(minHeight: NewAccountMetrics.fieldHeight)
                .background(Color.homeSheetCard, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .keaserReadableWidth()
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

/// Turns off spell checking on the text field it sits behind. With
/// autocorrection already off, that hides the keyboard's suggestions bar,
/// which SwiftUI has no modifier for. The field is the first one found
/// around this view; if there is none, the keyboard keeps its bar.
private struct SpellCheckingDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The field may join the window in the same pass; look once the
            // pass is done.
            DispatchQueue.main.async { [weak self] in self?.disableSpellChecking() }
        }

        private func disableSpellChecking() {
            var ancestor = superview
            while let view = ancestor, !(view is UIWindow) {
                if let field = Self.textField(in: view) {
                    guard field.spellCheckingType != .no else { return }
                    field.spellCheckingType = .no
                    if field.isFirstResponder { field.reloadInputViews() }
                    return
                }
                ancestor = view.superview
            }
        }

        private static func textField(in view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            for subview in view.subviews {
                if let field = textField(in: subview) { return field }
            }
            return nil
        }
    }
}

/// The New Account form. On iOS 26 and later it is the reference's,
/// measured in the sheet's own points (a floating sheet is drawn at 96%):
/// the label 20pt under the header, a 52pt field, the label semibold and
/// lighter, the prompt the expense editor's, the page a little lighter
/// than the other sheets in dark mode. Before iOS 26 the attached sheet
/// keeps the recording's pixels at 3 a point and the shared greys.
private enum NewAccountMetrics {
    private static var isFloatingSheet: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    static var labelTop: CGFloat { isFloatingSheet ? 20 : 19 }
    static var fieldHeight: CGFloat { isFloatingSheet ? 52 : 50 }
    static var label: Color { isFloatingSheet ? .homeSheetFieldLabel : .keaserSecondaryText }
    static var placeholder: Color { isFloatingSheet ? .homeSheetPlaceholder : .keaserTertiaryText }
    static var veil: Color { isFloatingSheet ? .homeSheetFormVeil : .clear }
}
