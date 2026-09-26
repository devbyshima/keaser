#if DEBUG
import KeaserKit
import SwiftUI
import WidgetKit

/// Every Spending widget family at its real point size, drawn with the
/// widget's own views, so screenshots can check them without adding widgets to
/// a home screen. Opened with `-KeaserOnboardingPage widgetGallery` (demo data)
/// or `widgetGalleryLocked` (the Pro-locked and no-account states).
struct WidgetGallery: View {
    let showsLockedStates: Bool

    // iPhone 16 Pro sizes.
    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)
    private static let rectangular = CGSize(width: 172, height: 76)
    private static let circular = CGSize(width: 72, height: 72)
    private static let inline = CGSize(width: 250, height: 26)

    private let now = Date.now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(showsLockedStates ? "Widgets: locked and empty" : "Widgets")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if showsLockedStates { lockedStates } else { readyStates }
            }
            .padding(.horizontal, 19)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var readyStates: some View {
        let demo = DemoData.database(.demo, now: now)
        section("Home Screen")
        HStack(spacing: 24) {
            home(snapshot(demo, .thisMonth), .systemSmall)
            home(snapshot(demo, .thisWeek), .systemSmall)
        }
        home(snapshot(demo, .thisMonth), .systemMedium)
        home(snapshot(demo, .thisYear), .systemMedium)
        section("Lock Screen")
        lockScreen(
            rectangular: snapshot(demo, .today),
            circular: snapshot(demo, .thisMonth),
            inline: snapshot(demo, .thisMonth)
        )
    }

    @ViewBuilder
    private var lockedStates: some View {
        let locked = snapshot(expiredPass, .thisMonth)
        let empty = snapshot(DemoData.database(.onboarded, now: now), .thisMonth)
        section("Pass over")
        HStack(spacing: 24) {
            home(locked, .systemSmall)
            home(empty, .systemSmall)
        }
        home(locked, .systemMedium)
        section("Lock Screen, pass over")
        lockScreen(rectangular: locked, circular: locked, inline: locked)
        section("Lock Screen, no account")
        lockScreen(rectangular: empty, circular: empty, inline: empty)
    }

    /// Demo data whose 7-day pass ended weeks ago.
    private var expiredPass: Database {
        var database = DemoData.database(.demo, now: now)
        database.preferences.trialStartDate = now.addingTimeInterval(-86_400 * 30)
        return database
    }

    private func snapshot(_ database: Database, _ period: Period) -> SpendingSnapshot {
        SpendingSnapshot.make(database: database, accountID: nil, period: period, now: now)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.keaserSecondaryText)
            .padding(.top, 4)
    }

    private func home(_ snapshot: SpendingSnapshot, _ family: WidgetFamily) -> some View {
        WidgetPreviewFrame(size: family == .systemMedium ? Self.medium : Self.small) {
            SpendingWidgetView(snapshot: snapshot, family: family, inApp: true)
        }
    }

    /// Accessory widgets on a lock-screen-like backdrop, in the white the
    /// system renders them in.
    private func lockScreen(rectangular: SpendingSnapshot, circular: SpendingSnapshot, inline: SpendingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                SpendingWidgetView(snapshot: rectangular, family: .accessoryRectangular, inApp: true)
                    .frame(width: Self.rectangular.width, height: Self.rectangular.height)
                SpendingWidgetView(snapshot: circular, family: .accessoryCircular, inApp: true)
                    .frame(width: Self.circular.width, height: Self.circular.height)
            }
            SpendingWidgetView(snapshot: inline, family: .accessoryInline, inApp: true)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .frame(width: Self.inline.width, height: Self.inline.height, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
    }
}
#endif
