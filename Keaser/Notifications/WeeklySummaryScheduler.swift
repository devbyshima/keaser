import KeaserKit
import UserNotifications

// STUB (owner: onboarding-platform builder).

/// Keeps the weekly spending summary notification scheduled with a current
/// total. Attached once at launch; reacts to store changes.
@MainActor
final class WeeklySummaryScheduler {
    static let shared = WeeklySummaryScheduler()

    func attach(to store: KeaserStore) {}
}
