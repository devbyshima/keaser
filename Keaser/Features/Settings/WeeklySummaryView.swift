import KeaserKit
import SwiftUI

/// The weekly summary switch. Turning it on asks for notification permission
/// the first time. The switch is the user's choice and stays on if iOS says
/// no: the page then explains and links to the Settings app, and the summary
/// starts on its own once notifications are allowed there.
struct WeeklySummaryView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var permission: NotificationPermission?

    var body: some View {
        let isOn = Binding(
            get: { store.preferences.weeklySummaryEnabled },
            set: { setEnabled($0) }
        )
        let showsDenied = isOn.wrappedValue && permission == .denied
        List {
            Section {
                Toggle("Weekly Summary", isOn: isOn)
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    // The app's ink tint would turn the switch white on
                    // white in dark mode; keep the system green.
                    .tint(Color(uiColor: .systemGreen))
                    .frame(minHeight: 52)
                    .cardRow(showsDenied ? .first : .single, insets: .settingsTextRow)
                // Right under the switch, where it cannot be missed.
                if showsDenied {
                    InfoRow(
                        symbol: "bell.slash.fill",
                        title: "Notifications Are Off",
                        detail: "iOS is not letting Keaser send notifications, so the summary cannot arrive. Allow them for Keaser in the Settings app."
                    )
                    .cardRow(.middle)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        SettingsRow(symbol: "gear", title: "Open Settings", accessory: "arrow.up.right", hasDisclosure: false)
                    }
                    .cardRow(.last)
                }
            } footer: {
                SettingsFootnote("""
                Once a week, at \(Self.deliveryTime) on the last day of your week, Keaser sends one notification \
                with what you spent that week in the account you have open. Your week starts on the day chosen in \
                Start Week On. The total is added up and scheduled on this iPhone, and it stays up to date as you \
                log expenses.
                """)
            }
        }
        .settingsListStyle()
        .settingsPage("Weekly Summary")
        .animation(.snappy(duration: 0.2), value: permission)
        // Checked again on returning from the Settings app, where it may
        // have changed.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            permission = await currentPermission()
        }
    }

    private func setEnabled(_ enabled: Bool) {
        store.updatePreferences { $0.weeklySummaryEnabled = enabled }
        guard enabled else { return }
        Task { permission = await NotificationPermission.request() }
    }

    private func currentPermission() async -> NotificationPermission {
        #if DEBUG
        // `-KeaserNotifState denied` shows the page with the summary on and
        // notifications off, without a system prompt.
        if let forced = DebugLaunch.string("KeaserNotifState") {
            if forced == "denied" { store.updatePreferences { $0.weeklySummaryEnabled = true } }
            return forced == "denied" ? .denied : .granted
        }
        #endif
        return await NotificationPermission.status()
    }

    /// "7:00 PM", from the hour the scheduler uses.
    private static var deliveryTime: String {
        let time = Calendar.current.date(bySettingHour: WeeklySummary.hour, minute: 0, second: 0, of: .now) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }
}
