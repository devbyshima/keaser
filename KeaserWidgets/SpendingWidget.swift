import AppIntents
import KeaserKit
import StoreKit
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
        .supportedFamilies(Self.families)
        // It shows personal finances, which do not belong on a car's shared
        // screen, and nothing a driver needs.
        .disfavoredLocations(Self.disfavoredLocations, for: [.systemSmall])
    }

    /// The large widgets carry the category breakdown; the extra large
    /// portrait one exists from iOS 27.
    static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }

    /// CarPlay (iOS 26) offers every small widget unless it is disfavoured.
    static var disfavoredLocations: [WidgetLocation] {
        if #available(iOS 26.0, *) {
            return [.carPlay]
        }
        return []
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
        let now = Date.now
        let entry = entry(for: configuration, database: await WidgetDatabase.load(now: now), now: now)
        // The widget gallery should show what the widget does, even before
        // the first account exists. A locked widget stays locked there, so
        // nobody adds one expecting it to work: once Pro is over, the
        // snapshot is locked with or without an account.
        if context.isPreview, entry.snapshot.state == .noAccount {
            return SpendingEntry(date: entry.date, snapshot: .sample(currencyCode: entry.snapshot.currencyCode))
        }
        return entry
    }

    func timeline(for configuration: SpendingWidgetIntent, in context: Context) async -> Timeline<SpendingEntry> {
        let now = Date.now
        let database = await WidgetDatabase.load(now: now)
        // The app reloads timelines after every edit; this covers the day
        // (or the Pro pass) turning over while nobody touches the app.
        return Timeline(
            entries: [entry(for: configuration, database: database, now: now)],
            policy: .after(SpendingSnapshot.nextRefresh(after: now, preferences: database.preferences))
        )
    }

    private func entry(for configuration: SpendingWidgetIntent, database: Database, now: Date) -> SpendingEntry {
        SpendingEntry(
            date: now,
            snapshot: SpendingSnapshot.make(database: database, accountID: configuration.account?.id, period: configuration.period.period, now: now)
        )
    }
}

/// The database the app wrote, with its Pro cache confirmed by StoreKit when
/// it says a subscription has run out. Only the app writes the cache, so a
/// renewal (or a billing grace period) that began while Keaser was closed
/// would otherwise lock a paying subscriber's widget until they open the
/// app. The confirmed status is used for this redraw only; the app still
/// owns the file.
enum WidgetDatabase {
    static func load(now: Date) async -> Database {
        var database = DatabaseFile.shared.load()
        guard ProEntitlement.needsStoreKitCheck(database.preferences, now: now) else { return database }
        var grant = ProGrant.none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            grant = grant.combined(with: ProProduct.grant(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                renewal: await renewal(of: transaction),
                now: now
            ))
        }
        grant.cache(in: &database.preferences)
        return database
    }

    /// The same reading of the renewal info as `ProStore` in the app.
    private static func renewal(of transaction: StoreKit.Transaction) async -> ProRenewal? {
        guard transaction.productType == .autoRenewable,
              let status = await transaction.subscriptionStatus,
              case .verified(let info) = status.renewalInfo
        else { return nil }
        return ProRenewal(
            willAutoRenew: info.willAutoRenew,
            isInBillingRetry: info.isInBillingRetry,
            gracePeriodEnd: status.state == .inGracePeriod ? info.gracePeriodExpirationDate : nil
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
                if family.isAccessory {
                    Color.clear
                } else {
                    WidgetPalette.background
                }
            }
    }
}
