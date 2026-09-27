import KeaserKit
import SwiftUI

/// Onboarding until it is finished, then Home. The welcome letter slides up
/// over Home the first time it appears.
struct RootView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let problem = storageProblem {
                StorageBanner(message: problem)
                    // Slides down from the status bar, or only fades with
                    // Reduce Motion.
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: storageProblem)
        // The file is unreadable until the first unlock after a restart; try
        // again the moment it becomes readable.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            store.reloadFromDisk()
        }
        #if DEBUG
        .sheet(item: $debugSheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .paywall: PaywallView()
            }
        }
        #endif
        .sheet(isPresented: welcomeLetterPresented) {
            WelcomeLetterSheet()
        }
        #if DEBUG
        .overlay {
            if let kind = SnippetPreview.Kind(rawValue: DebugLaunch.snippet ?? "") {
                SnippetPreview(kind: kind)
            }
        }
        #endif
    }

    /// Said out loud whenever the store cannot reach its file, so a change is
    /// never lost silently.
    private var storageProblem: String? {
        if store.loadError != nil {
            return "Keaser can't open your data right now. Unlock your iPhone, then reopen Keaser."
        }
        if store.lastSaveError != nil {
            return "Keaser couldn't save your latest changes. They're kept and will be saved when there's room."
        }
        return nil
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

/// A compact warning under the status bar.
private struct StorageBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.keaserDestructive)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.keaserPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .keaserGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, KeaserMetrics.screenPadding)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// Sheets owned by features that Home does not present at launch, opened
/// directly from `-KeaserSheet` so they can be screenshotted in isolation.
/// Home's own sheets (`newExpense`, `accounts`...) are handled by HomeView.
private enum DebugSheet: String, Identifiable {
    case settings, paywall
    var id: String { rawValue }
}
#endif
