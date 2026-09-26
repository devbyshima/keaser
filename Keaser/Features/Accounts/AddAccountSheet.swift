import KeaserKit
import SwiftUI

/// "Add Account": link a Notion database or create a local account, then
/// name it. One compact sheet whose content slides from the choice to the
/// name form, like the reference.
struct AddAccountSheet: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsForm = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var isConnectingNotion = false
    @State private var paywallShown = false
    @State private var createdCount = 0
    /// The Notion tile grows with the row text.
    @ScaledMetric(relativeTo: .body) private var notionMarkSize: CGFloat = 24

    /// `startsWithForm` opens straight on the name form (the `newAccount`
    /// debug sheet).
    init(startsWithForm: Bool = false) {
        _showsForm = State(initialValue: startsWithForm)
    }

    /// 320pt tall on screen, as in the reference. Before iOS 26 the sheet
    /// is attached to the bottom edge and its detent also covers the home
    /// indicator area, so it asks for less to end up the same height.
    private static var sheetHeight: CGFloat {
        if #available(iOS 26.0, *) { return 320 }
        return 294
    }

    /// A second account needs Pro (Multiple Accounts).
    private var needsPro: Bool { !store.accounts.isEmpty && !pro.isPro }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack(alignment: .top) {
            if showsForm {
                form
                    .transition(slide(from: .trailing))
            } else {
                choices
                    .transition(slide(from: .leading))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        // The measured height fits the default text sizes; accessibility
        // sizes get room to grow instead of being cut off.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(Self.sheetHeight)])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
        .sensoryFeedback(.success, trigger: createdCount)
        .sheet(isPresented: $isConnectingNotion) {
            NotionConnectView { accountID in
                if accountID != nil {
                    // Closing this sheet closes the Notion flow above it too.
                    dismiss()
                } else {
                    isConnectingNotion = false
                }
            }
        }
        .sheet(isPresented: $paywallShown) {
            PaywallView(highlighting: .multipleAccounts)
        }
    }

    /// The choice and the form slide sideways, or only fade with Reduce
    /// Motion.
    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    // MARK: Choice

    private var choices: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Add Account")
                .homeSheetHeader()
            KeaserCard(fill: .keaserSheetCard) {
                AddAccountChoiceRow(title: "Connect to Notion") {
                    NotionMark(size: notionMarkSize, style: .outlined)
                } action: {
                    guard !needsPro else { paywallShown = true; return }
                    isConnectingNotion = true
                }
                .overlay(alignment: .bottom) { KeaserRowSeparator(leading: 62) }
                AddAccountChoiceRow(title: "Create new account") {
                    Image(systemName: "iphone")
                        .keaserFont(20, relativeTo: .body)
                        .foregroundStyle(Color.keaserPrimaryText)
                } action: {
                    guard !needsPro else { paywallShown = true; return }
                    withAnimation(.smooth(duration: 0.35)) { showsForm = true }
                    nameFocused = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, HomeSheetMetrics.contentTop)
        }
    }

    // MARK: Name form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            KeaserSheetHeader(title: "New Account") {
                KeaserCircleButton("chevron.left", label: "Back") {
                    nameFocused = false
                    withAnimation(.smooth(duration: 0.35)) { showsForm = false }
                }
                .accessibilityShowsLargeContentViewer { Label("Back", systemImage: "chevron.left") }
            } trailing: {
                confirmButton
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
                .background(Color.keaserSheetCard, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .onAppear { nameFocused = true }
    }

    private var confirmButton: some View {
        let valid = !trimmedName.isEmpty
        return Button(action: create) {
            // A glyph in a fixed 44pt circle, like KeaserCircleButton, but
            // filled white once the name is valid.
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(valid ? Color.black : Color.white.opacity(0.55))
                .frame(width: 44, height: 44)
                .background {
                    if valid {
                        Circle().fill(Color.white)
                    } else {
                        Circle().fill(Color.white.opacity(0.14))
                    }
                }
                .contentShape(Circle())
                .animation(.smooth(duration: 0.2), value: valid)
        }
        .buttonStyle(HomePressStyle())
        .disabled(!valid)
        .accessibilityLabel("Create Account")
        .accessibilityShowsLargeContentViewer { Label("Create Account", systemImage: "checkmark") }
        // The checkmark glyph would otherwise make VoiceOver say "selected".
        .accessibilityRemoveTraits(.isSelected)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        guard !needsPro else { paywallShown = true; return }
        store.createAccount(name: trimmedName)
        createdCount += 1
        nameFocused = false
        dismiss()
    }
}

/// A row in the Add Account card: icon, title, chevron.
private struct AddAccountChoiceRow<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                icon
                    .frame(minWidth: 28)
                    .padding(.leading, 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 73)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowButtonStyle())
    }
}
