import KeaserKit
import SwiftUI

/// Everything after onboarding: the system tab bar with Home, Wallets,
/// Summary and Settings (Liquid Glass on iOS 26 and later, the standard bar
/// before). The selection lives in `AppRouter`, so routes can change it;
/// each tab keeps its own state while another one shows.
struct MainTabView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Wallets", systemImage: "wallet.bifold", value: AppTab.wallets) {
                WalletsView()
            }
            Tab("Summary", systemImage: "chart.bar.xaxis", value: AppTab.summary) {
                SummaryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // An account deleted from Home's Accounts sheet takes its pages in
        // Settings (Account Settings, its Categories) off the stack.
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            let path = router.settingsPath.keepingAccounts(Set(ids))
            if path != router.settingsPath { router.settingsPath = path }
        }
    }
}
