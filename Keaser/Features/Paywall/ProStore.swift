import KeaserKit
import SwiftUI

// STUB (owner: settings-pro builder). The public surface below is a contract:
// other features call it, so keep these members and their meaning.

/// Pro status for the UI: the 7-day pass plus StoreKit purchases.
@MainActor
@Observable
final class ProStore {
    @ObservationIgnored private let store: KeaserStore

    init(store: KeaserStore) {
        self.store = store
    }

    /// True while the pass is live or after a purchase. Gate Pro features on this.
    var isPro: Bool { store.isPro() }

    /// Whole days left in the pass; nil if no pass was started, 0 once over.
    var trialDaysRemaining: Int? {
        ProEntitlement.trialDaysRemaining(trialStart: store.preferences.trialStartDate, now: .now)
    }

    /// True once the user has bought Pro (not merely trialling).
    var hasPurchased: Bool { store.preferences.hasProPurchase }

    /// Starts the 7-day pass if it has never been started. Called by
    /// onboarding when the user continues past the "7-Day Pro Pass" page.
    func startTrialIfNeeded(now: Date = .now) {
        guard store.preferences.trialStartDate == nil else { return }
        store.updatePreferences { $0.trialStartDate = now }
    }

    /// Called once at launch: loads products, listens for transactions and
    /// refreshes entitlements.
    func start() async {}
}
