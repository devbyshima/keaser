import KeaserKit
import SwiftUI

// STUB (owner: home-expenses builder).

/// The main screen: account switcher, search, filters, settings, the spending
/// summary with its chart, the latest expenses and the add button.
struct HomeView: View {
    @Environment(KeaserStore.self) private var store

    var body: some View {
        EmptyStateView(symbol: "creditcard", title: "No Expenses", message: "Add your first expense by tapping the + button")
    }
}
