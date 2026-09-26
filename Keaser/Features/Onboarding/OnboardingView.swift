import KeaserKit
import SwiftUI

// STUB (owner: onboarding-platform builder).

/// The six-page first-run flow. Calls `onFinish` after the last page.
struct OnboardingView: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            KeaserLogo(size: 110)
            Text("Welcome to Keaser").font(.keaserTitle)
            Spacer()
            Button("Get Started", action: onFinish).buttonStyle(.keaserPrimary)
        }
        .padding(KeaserMetrics.screenPadding)
    }
}
