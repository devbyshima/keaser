import SwiftUI

// STUB (owner: onboarding-platform builder). Replace with the real Keaser mark.

/// The Keaser mark, drawn in code so it stays sharp at every size.
struct KeaserLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: size * 0.08)
            .overlay(Text("K").font(.system(size: size * 0.5, weight: .black)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}
