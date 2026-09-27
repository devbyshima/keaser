import KeaserKit
import SwiftUI
import WidgetKit

@main
struct KeaserApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let store = AppEnvironment.store
    private let router = AppEnvironment.router
    private let pro = AppEnvironment.pro

    init() {
        let store = AppEnvironment.store
        // Widgets show totals, currency, week start and Pro state, so any
        // change can move them. WidgetKit coalesces reload requests.
        store.addObserver { _ in WidgetCenter.shared.reloadAllTimelines() }
        WeeklySummaryScheduler.shared.attach(to: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(pro)
                .tint(Color.keaserInk)
                .onOpenURL { router.handle($0) }
                .task { await pro.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            // An App Intent or the widget's control may have written while we
            // were in the background.
            if phase == .active { store.reloadFromDisk() }
        }
    }
}
