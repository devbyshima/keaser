import KeaserKit
import SwiftUI

/// Everything after onboarding: the system tab bar with Home, Wallets,
/// Summary and Settings (Liquid Glass on iOS 26 and later, the standard bar
/// before), and Add Expense detached at its trailing end. The selection
/// lives in `AppRouter`, so routes can change it; each tab keeps its own
/// state while another one shows.
struct MainTabView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView(selection: selection) {
            Tab("Home", systemImage: "house", value: TabSlot.tab(.home)) {
                HomeView()
            }
            Tab("Wallets", systemImage: "wallet.bifold", value: TabSlot.tab(.wallets)) {
                WalletsView()
            }
            Tab("Summary", systemImage: "chart.bar.xaxis", value: TabSlot.tab(.summary)) {
                SummaryView()
            }
            Tab("Settings", systemImage: "gearshape", value: TabSlot.tab(.settings)) {
                SettingsView()
            }
            // Never selected: picking it opens New Expense on Home, as
            // `keaser://new-expense` does, so it never shows a page.
            Tab(value: TabSlot.addExpense, role: Self.addExpenseRole) {
                Color.keaserBackground.ignoresSafeArea()
            } label: {
                Label {
                    Text("Add Expense")
                } icon: {
                    Image(uiImage: AddExpenseIcon.image(for: colorScheme))
                        .renderingMode(.original)
                }
            }
        }
        // An account deleted from Home's Accounts sheet takes its pages in
        // Settings (Account Settings, its Categories) off the stack.
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            let path = router.settingsPath.keepingAccounts(Set(ids))
            if path != router.settingsPath { router.settingsPath = path }
        }
    }

    /// The tab showing, and Add Expense turned into the New Expense route
    /// instead of a selection.
    private var selection: Binding<TabSlot> {
        Binding(
            get: { .tab(router.selectedTab) },
            set: { slot in
                switch slot {
                case .tab(let tab): router.selectedTab = tab
                case .addExpense: router.open(.newExpense)
                }
            }
        )
    }

    /// The detached place at the trailing end of the bar: the prominent tab
    /// on iOS 27, the search tab's place on iOS 26 (the only tab the bar
    /// sets apart there), and a plain last tab before, where the bar has no
    /// detached place.
    private static var addExpenseRole: TabRole? {
        if #available(iOS 27.0, *) { return .prominent }
        if #available(iOS 26.0, *) { return .search }
        return nil
    }
}

/// Add Expense's icon: an ink disc with the + in `keaserOnInk`, the look of
/// Home's floating button before it moved into the bar. Drawn as an image
/// that keeps its own colours, since the bar tints a tab's glyph like the
/// others and leaves its detached glass plain.
@MainActor
private enum AddExpenseIcon {
    static func image(for scheme: ColorScheme) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let ink = UIColor(Color.keaserInk).resolvedColor(with: traits)
        let onInk = UIColor(Color.keaserOnInk).resolvedColor(with: traits)
        let side = diameter
        let size = CGSize(width: side, height: side)
        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
        let glyph = UIImage(systemName: "plus", withConfiguration: configuration)?
            .withTintColor(onInk, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { _ in
            ink.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            if let glyph {
                let g = glyph.size
                glyph.draw(in: CGRect(x: (side - g.width) / 2, y: (side - g.height) / 2, width: g.width, height: g.height))
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }

    private static var diameter: CGFloat {
        if #available(iOS 26.0, *) { 44 } else { 30 }
    }
}

/// A place in the tab bar: one of the four tabs, or Add Expense, which is
/// an action rather than a page.
private enum TabSlot: Hashable {
    case tab(AppTab)
    case addExpense
}
