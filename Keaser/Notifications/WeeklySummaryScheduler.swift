import KeaserKit
import UIKit
import UserNotifications

/// Keeps the weekly spending summary notification scheduled with a current
/// total. Attached once at launch; reacts to store changes.
///
/// There is only ever one pending request (`WeeklySummary.identifier`), for
/// 7:00 pm on the last day of the user's week. Local notifications carry fixed
/// text, so the request is replaced after every change to keep the total
/// right, and again whenever the app becomes active in case a week rolled over
/// while it was closed.
@MainActor
final class WeeklySummaryScheduler {
    static let shared = WeeklySummaryScheduler()

    private weak var store: KeaserStore?
    private var pending: Task<Void, Never>?
    private var observesActivation = false

    /// Starts keeping the notification in step with `store`. Safe to call more
    /// than once (App Intents call it when they run without the app's UI).
    func attach(to store: KeaserStore) {
        guard self.store !== store else { return }
        self.store = store
        store.addObserver { [weak self] _ in self?.refresh() }
        if !observesActivation {
            observesActivation = true
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    /// Replaces the pending request with one computed from the store now.
    /// Bursts of edits collapse into a single reschedule.
    func refresh() {
        guard let store else { return }
        pending?.cancel()
        pending = Task { [weak store] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let store else { return }
            await Self.apply(WeeklySummary.plan(for: store.database, now: .now))
        }
    }

    /// Reschedules and waits for it, for App Intents that must finish their
    /// work before the system suspends them.
    func refreshNow() async {
        guard let store else { return }
        pending?.cancel()
        await Self.apply(WeeklySummary.plan(for: store.database, now: .now))
    }

    private static func apply(_ plan: WeeklySummaryPlan?) async {
        let center = UNUserNotificationCenter.current()
        guard let plan, await NotificationPermission.status() == .granted else {
            center.removePendingNotificationRequests(withIdentifiers: [WeeklySummary.identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.threadIdentifier = WeeklySummary.identifier
        // Wall-clock components, so 7:00 pm stays 7:00 pm if the user travels.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Adding a request with an existing identifier replaces it.
        let request = UNNotificationRequest(identifier: WeeklySummary.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

/// The system notification permission, in the terms onboarding and Settings
/// need.
enum NotificationPermission: Equatable, Sendable {
    /// Never asked; asking shows the system prompt.
    case notDetermined
    case granted
    /// Turned off; only the Settings app can change it.
    case denied

    static func status() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt if the user has never answered it, and returns
    /// the resulting permission. Once answered, the system does not ask again
    /// and this just reports the earlier answer.
    static func request() async -> NotificationPermission {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .granted : .denied
        } catch {
            return await status()
        }
    }
}
