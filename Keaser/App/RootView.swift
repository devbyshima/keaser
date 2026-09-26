import KeaserKit
import SwiftUI

/// Onboarding until it is finished, then Home. The welcome letter slides up
/// over Home the first time it appears.
struct RootView: View {
    @Environment(KeaserStore.self) private var store

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
