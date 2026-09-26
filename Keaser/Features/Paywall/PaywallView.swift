import KeaserKit
import SwiftUI

// STUB (owner: settings-pro builder).

/// Keaser Pro upgrade sheet. Present it as a sheet from wherever a Pro feature
/// is gated; it dismisses itself after a successful purchase or restore.
struct PaywallView: View {
    /// The feature that triggered the paywall, if any, so it can lead with it.
    var highlighting: ProFeature? = nil

    var body: some View {
        Text("Keaser Pro")
    }
}
