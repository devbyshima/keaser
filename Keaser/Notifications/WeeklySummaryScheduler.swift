import AppIntents
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
///
/// A summary is scheduled only while both switches are on: the user's choice
/// (`Preferences.weeklySummaryEnabled`, a store change) and the system
/// permission. Permission is read again on every refresh, and refreshes run
/// when the app becomes active (back from the Settings app) and when the
/// permission prompt is answered.
@MainActor
final class WeeklySummaryScheduler {
    static let shared = WeeklySummaryScheduler()

    /// How long an App Intent that changed data waits for the reschedule
    /// before it returns. The reschedule finishes on its own if it takes
    /// longer, so a slow notification service never makes Add Expense, Log
    /// Wallet Transaction or Delete Expense time out.
    static let intentWait: Duration = .seconds(3)
    /// How long a reschedule waits for the notification service to say
    /// whether notifications are allowed. Without an answer the pending
    /// request is left as it is until the next change or launch.
    static let permissionWait: Duration = .seconds(10)

    private weak var store: KeaserStore?
    private var pending: Task<Void, Never>?
    private var observesActivation = false
    /// Reschedules, one at a time, so a slow one is never overtaken by a
    /// later one with an older plan. Each reads the store when it begins, so
    /// requests made while one waits share it.
    private let work = SerialWork()

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
        guard store != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.work.startOrJoin { [weak self] in await self?.reschedule() }
        }
    }

    /// Reschedules and waits for it, for App Intents that must finish their
    /// work before the system suspends them, and for the permission prompt.
    /// Waits `intentWait` at most.
    func refreshNow() async {
        guard store != nil else { return }
        pending?.cancel()
        await work.runOrJoin(within: Self.intentWait) { [weak self] in await self?.reschedule() }
    }

    /// Reads the permission, works out the plan from the store as it is
    /// then, and hands it to the notification queue.
    private func reschedule() async {
        guard store != nil,
              let permission = await Deadline.value(within: Self.permissionWait, of: { await NotificationPermission.status() }),
              let store
        else { return }
        Self.submit(permission == .granted ? WeeklySummary.plan(for: store.database, now: .now) : nil)
    }

    /// The notification service's own queue in this app. Replacing or
    /// removing the request calls into the system's notification service
    /// synchronously, and when that service is slow or stuck (a freshly
    /// booted simulator, a busy phone) the call can block for a long time.
    /// On this serial queue it holds neither the main actor nor one of
    /// Swift's few cooperative threads, and the requests still reach the
    /// service in the order they were made.
    private nonisolated static let queue = DispatchQueue(label: "com.fulltimestudio.keaser.weekly-summary", qos: .utility)

    /// Schedules `plan`, or removes the pending summary for nil, without
    /// waiting for the notification service.
    private nonisolated static func submit(_ plan: WeeklySummaryPlan?) {
        queue.async {
            let center = UNUserNotificationCenter.current()
            guard let plan else {
                center.removePendingNotificationRequests(withIdentifiers: [WeeklySummary.identifier])
                return
            }
            // Adding a request with an existing identifier replaces it.
            center.add(request(for: plan), withCompletionHandler: nil)
        }
    }

    private nonisolated static func request(for plan: WeeklySummaryPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.threadIdentifier = WeeklySummary.identifier
        if #available(iOS 27.0, *) {
            // Which account the total is for, so Siri can act on the
            // summary ("open it", "how much on food?") when it is read out.
            content.appEntityIdentifiers = [EntityIdentifier(for: AccountEntity.self, identifier: plan.accountID)]
        }
        // Wall-clock components, so 7:00 pm stays 7:00 pm if the user travels.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: WeeklySummary.identifier, content: content, trigger: trigger)
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
    /// and this just reports the earlier answer. The weekly summary is brought
    /// in line with the answer before this returns.
    static func request() async -> NotificationPermission {
        let permission: NotificationPermission
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            permission = granted ? .granted : .denied
        } catch {
            permission = await status()
        }
        await WeeklySummaryScheduler.shared.refreshNow()
        return permission
    }
}
