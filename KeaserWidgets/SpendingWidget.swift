import AppIntents
import KeaserKit
import SwiftUI
import WidgetKit

/// Total spending for a period, on the home screen and the lock screen.
struct SpendingWidget: Widget {
    static let kind = "Spending"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SpendingWidgetIntent.self, provider: SpendingProvider()) { entry in
            SpendingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Spending")
        .description("See what you've spent today, this week, this month or this year.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct SpendingWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spending"
    static var description: IntentDescription { IntentDescription("Choose the account and period to show.") }

    @Parameter(title: "Account", description: "Leave empty to follow the account selected in Keaser.")
    var account: AccountEntity?

    @Parameter(title: "Period", default: .thisMonth)
    var period: WidgetPeriod

    init() {}
}

/// The periods a widget can show. All Time is left out: a lifetime total
/// barely moves and would crowd the menu.
enum WidgetPeriod: String, AppEnum {
    case today, thisWeek, thisMonth, thisYear

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Period" }
    static var caseDisplayRepresentations: [WidgetPeriod: DisplayRepresentation] {
        [
            .today: "Today",
            .thisWeek: "This Week",
            .thisMonth: "This Month",
            .thisYear: "This Year",
        ]
    }

    var period: Period {
        switch self {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .thisYear: .thisYear
        }
    }
}

struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: SpendingSnapshot
}

struct SpendingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry {
        SpendingEntry(date: .now, snapshot: .sample())
    }

    func snapshot(for configuration: SpendingWidgetIntent, in context: Context) async -> SpendingEntry {
        let entry = entry(for: configuration, now: .now)
        // The widget gallery should show what the widget does, even before
        // the first account exists. A locked widget stays locked there, so
        // nobody adds one expecting it to work.
        if context.isPreview, entry.snapshot.state == .noAccount {
            return SpendingEntry(date: entry.date, snapshot: .sample(currencyCode: entry.snapshot.currencyCode))
        }
        return entry
    }

    func timeline(for configuration: SpendingWidgetIntent, in context: Context) async -> Timeline<SpendingEntry> {
        let now = Date.now
        let database = DatabaseFile.shared.load()
        let entry = SpendingEntry(
            date: now,
            snapshot: SpendingSnapshot.make(database: database, accountID: configuration.account?.id, period: configuration.period.period, now: now)
        )
        // The app reloads timelines after every edit; this covers the day
        // (or the Pro pass) turning over while nobody touches the app.
        return Timeline(entries: [entry], policy: .after(SpendingSnapshot.nextRefresh(after: now, preferences: database.preferences)))
    }

    private func entry(for configuration: SpendingWidgetIntent, now: Date) -> SpendingEntry {
        let database = DatabaseFile.shared.load()
        return SpendingEntry(
            date: now,
            snapshot: SpendingSnapshot.make(database: database, accountID: configuration.account?.id, period: configuration.period.period, now: now)
        )
    }
}

struct SpendingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry

    var body: some View {
        SpendingWidgetView(snapshot: entry.snapshot, family: family)
            // Only the locked widget links somewhere specific (Settings, to
            // upgrade); otherwise a tap just opens the app.
            .widgetURL(entry.snapshot.state == .locked ? URL(string: "keaser://settings") : nil)
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    WidgetPalette.background
                } else {
                    Color.clear
                }
            }
    }
}
