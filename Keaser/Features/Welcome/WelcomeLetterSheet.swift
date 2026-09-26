import KeaserKit
import SwiftUI

// STUB (owner: onboarding-platform builder).

/// The note from the makers shown once, over Home, right after onboarding.
/// Dismissing it (Continue on the last page, the close button, or a swipe)
/// marks it seen; RootView owns that flag.
struct WelcomeLetterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Welcome to Keaser")
            Button("Continue") { dismiss() }.buttonStyle(.keaserPrimary)
        }
        .padding()
    }
}
