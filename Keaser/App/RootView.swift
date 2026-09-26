import KeaserKit
import SwiftUI

/// Onboarding until it is finished, then Home. The welcome letter slides up
/// over Home the first time it appears.
struct RootView: View {
    @Environment(KeaserStore.self) private var store
    #if DEBUG
    @State private var debugSheet: DebugSheet? = DebugSheet(rawValue: DebugLaunch.sheet ?? "")
    #endif

    var body: some View {
        ZStack {
            Color.keaserBackground.ignoresSafeArea()
            if store.preferences.hasCompletedOnboarding {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    store.updatePreferences { $0.hasCompletedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: store.preferences.hasCompletedOnboarding)
        #if DEBUG
        .sheet(item: $debugSheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .paywall: PaywallView()
            case .notion: NotionConnectView { _ in debugSheet = nil }
            }
        }
        #endif
        .sheet(isPresented: welcomeLetterPresented) {
            WelcomeLetterSheet()
        }
    }

    private var welcomeLetterPresented: Binding<Bool> {
        Binding(
            get: {
                let prefs = store.preferences
                return prefs.hasCompletedOnboarding && !prefs.hasSeenWelcomeLetter
            },
            set: { presented in
                if !presented { store.updatePreferences { $0.hasSeenWelcomeLetter = true } }
            }
        )
    }
}

#if DEBUG
/// Sheets owned by features that Home does not present at launch, opened
/// directly from `-KeaserSheet` so they can be screenshotted in isolation.
/// Home's own sheets (`newExpense`, `accounts`...) are handled by HomeView.
private enum DebugSheet: String, Identifiable {
    case settings, paywall, notion
    var id: String { rawValue }
}
#endif
