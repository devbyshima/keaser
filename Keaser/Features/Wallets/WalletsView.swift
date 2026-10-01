import SwiftUI

/// The Wallets tab. Empty until wallets get their screens (money tracking
/// phase 3): Home's empty state, centred as its No Account screen is.
struct WalletsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "wallet.bifold",
                title: "Wallets",
                message: "Your wallets and their balances will show here.",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.keaserBackground.ignoresSafeArea())
            .navigationTitle("Wallets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
