import KeaserKit
import SwiftUI
import UIKit

/// "Add Account": link a Notion database or create a local account, then
/// name it. One compact sheet whose content slides from the choice to the
/// name form, like the reference.
struct AddAccountSheet: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var showsForm = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var isConnectingNotion = false
    @State private var paywallShown = false

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
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                choices
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.hidden)
        .keaserSheetChrome()
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

    // MARK: Choice

    private var choices: some View {
        VStack(spacing: 0) {
            HomeSheetHeader(title: "Add Account")
            VStack(spacing: 0) {
                AddAccountChoiceRow(title: "Connect to Notion") {
                    NeutralNotionTile()
                } action: {
                    guard !needsPro else { paywallShown = true; return }
                    isConnectingNotion = true
                }
                .overlay(alignment: .bottom) { HomeRowSeparator(leading: 62) }
                AddAccountChoiceRow(title: "Create new account") {
                    Image(systemName: "iphone")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.keaserPrimaryText)
                } action: {
                    guard !needsPro else { paywallShown = true; return }
                    withAnimation(.smooth(duration: 0.35)) { showsForm = true }
                    nameFocused = true
                }
            }
            .background(Color.keaserCardRaised)
            .clipShape(RoundedRectangle(cornerRadius: HomeSheetMetrics.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, HomeSheetMetrics.contentTop)
        }
    }

    // MARK: Name form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSheetHeader(title: "New Account") {
                HomeCircleButton(symbol: "chevron.left", accessibilityLabel: "Back") {
                    nameFocused = false
                    withAnimation(.smooth(duration: 0.35)) { showsForm = false }
                }
            } trailing: {
                confirmButton
            }
            Text("Account name")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.keaserSecondaryText)
                .padding(.leading, 32)
                .padding(.top, 17)
            TextField("", text: $name, prompt: Text("E.g. Personal, Business").foregroundStyle(Color.keaserTertiaryText))
                .font(.system(size: 17))
                .foregroundStyle(Color.keaserPrimaryText)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .onSubmit(create)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.keaserCardRaised, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .onAppear { nameFocused = true }
    }

    private var confirmButton: some View {
        let valid = !trimmedName.isEmpty
        return Button(action: create) {
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
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        guard !needsPro else { paywallShown = true; return }
        store.createAccount(name: trimmedName)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                    .frame(width: 28)
                    .padding(.leading, 18)
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.keaserPrimaryText)
                    .padding(.leading, 16)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
                    .padding(.trailing, 16)
            }
            .frame(height: 73)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeHighlightRowStyle())
    }
}

/// Stands in for a Notion mark: a plain outlined tile with an "N".
private struct NeutralNotionTile: View {
    var body: some View {
        Text("N")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.keaserPrimaryText)
            .frame(width: 24, height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.keaserPrimaryText, lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

/// Row highlight while pressed, like a list cell.
struct HomeHighlightRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
