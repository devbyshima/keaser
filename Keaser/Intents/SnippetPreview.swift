#if DEBUG
import KeaserKit
import SwiftUI

/// `-KeaserSnippet confirm|confirmPlain|result|wallet`: the real
/// `ExpenseCardView` inside a stand-in of the system's card (dialog, hairline,
/// Cancel and Continue or Done) over a plain lock screen, so the cards can be
/// screenshotted headlessly; the system's own chrome cannot be. Measurements
/// follow the reference recording (iOS 26).
///
/// `confirm` is the interactive card of iOS 26, `confirmPlain` the one of iOS
/// 18 to 25 (no chevrons), `result` the Add Expense card when confirmation is
/// off, `wallet` the Wallet automation's. `-KeaserSnippetLong 1` gives the
/// expense a long title and its account a long name.
struct SnippetPreview: View {
    enum Kind: String {
        case confirm, confirmPlain, result, wallet

        var dialog: String {
            switch self {
            case .confirm, .confirmPlain: "Confirm expense details:"
            case .result, .wallet: "Successfully added expense"
            }
        }

        /// The expenses in the reference frames.
        var sample: (title: String, amount: Decimal, category: String, paymentMethod: String) {
            switch self {
            case .confirm, .confirmPlain: ("Uniqlo", Decimal(string: "19.90")!, "Shopping", "Credit Card")
            case .result: ("Coffee", 5, "Food & Drinks", "Credit Card")
            case .wallet: ("Watsons", Decimal(string: "1.60")!, "Shopping", "Credit Card")
            }
        }
    }

    let kind: Kind
    @Environment(KeaserStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .top) {
            LockScreenBackdrop()
            if let card {
                platter(card)
                    .padding(.horizontal, 8)
                    .padding(.top, 56)
            }
        }
        .ignoresSafeArea()
    }

    private var card: ShortcutCard? {
        guard var account = store.selectedAccount else { return nil }
        let long = DebugLaunch.int("KeaserSnippetLong") == 1
        if long { account.name = "Shared household expenses" }
        let sample = kind.sample
        let expense = Expense(
            title: long ? "Weekly groceries and household supplies" : sample.title,
            amount: sample.amount,
            categoryID: account.categories.first { $0.name == sample.category }?.id,
            paymentMethodID: account.paymentMethods.first { $0.name == sample.paymentMethod }?.id
        )
        return ShortcutCard(expense: expense, in: account, currencyCode: store.preferences.currencyCode)
    }

    private func platter(_ card: ShortcutCard) -> some View {
        VStack(spacing: 0) {
            Text(kind.dialog)
                .keaserFont(18, weight: .medium, relativeTo: .body)
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 15)
            Rectangle()
                .fill(Color.snippetHairline)
                .frame(height: 1 / displayScale)
            ExpenseCardView(card: card, session: kind == .confirm ? "preview" : nil)
            buttons
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .padding(.bottom, 15.5)
        }
        .background(Color.snippetPlatter, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color.snippetShadow, radius: 24, y: 8)
    }

    @ViewBuilder
    private var buttons: some View {
        switch kind {
        case .confirm, .confirmPlain:
            HStack(spacing: 11) {
                SystemButton(title: "Cancel", fill: .snippetSecondaryButton, text: .keaserPrimaryText)
                SystemButton(title: "Continue", fill: Color(uiColor: .systemBlue), text: .snippetOnBlue)
            }
        case .result, .wallet:
            SystemButton(title: "Done", fill: Color(uiColor: .systemBlue), text: .snippetOnBlue)
        }
    }
}

/// One of the system's capsule buttons under a card.
private struct SystemButton: View {
    let title: String
    let fill: Color
    let text: Color

    var body: some View {
        Text(title)
            .keaserFont(17, weight: .semibold, relativeTo: .body)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 51)
            .background(fill, in: Capsule())
    }
}

/// A plain wallpaper with the lock screen's clock and its two bottom
/// buttons: the Add Expense control on the left, as in the reference, and
/// the camera on the right.
private struct LockScreenBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.snippetWallpaperTop, .snippetWallpaperBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .keaserFont(20, weight: .semibold, relativeTo: .title3)
                    .padding(.top, 70)
                Text("9:41")
                    .keaserFont(110, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
                Spacer()
                HStack {
                    lockButton("creditcard.fill")
                    Spacer()
                    lockButton("camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 44)
            }
            .foregroundStyle(Color.snippetOnWallpaper)
        }
    }

    private func lockButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .keaserFont(20, relativeTo: .title3)
            .frame(width: 50, height: 50)
            .background(Color.snippetLockButton, in: Circle())
    }
}

// Stand-in colours of the system card and lock screen, per appearance.
private extension Color {
    static let snippetPlatter = Color(light: .init(white: 0.97), dark: .init(red: 0.14, green: 0.14, blue: 0.15))
    static let snippetHairline = Color(light: .black.opacity(0.2), dark: .white.opacity(0.18))
    static let snippetShadow = Color(light: .black.opacity(0.12), dark: .black.opacity(0.4))
    static let snippetSecondaryButton = Color(light: .init(white: 226 / 255), dark: .white.opacity(0.14))
    static let snippetOnBlue = Color(light: .white, dark: .white)
    static let snippetWallpaperTop = Color(light: .init(white: 0.93), dark: .init(white: 0.2))
    static let snippetWallpaperBottom = Color(light: .init(white: 0.7), dark: .init(white: 0.06))
    static let snippetOnWallpaper = Color(light: .white.opacity(0.9), dark: .white.opacity(0.85))
    static let snippetLockButton = Color(light: .black.opacity(0.25), dark: .white.opacity(0.14))
}
#endif
