#if DEBUG
import KeaserKit
import SwiftUI
import WidgetKit

/// Every Spending widget family at its real point size, drawn with the
/// widget's own views, so screenshots can check them without adding widgets to
/// a home screen. Opened with `-KeaserOnboardingPage widgetGallery` (demo data)
/// or `widgetGalleryLocked` (the Pro-locked and no-account states).
/// `-KeaserGalleryScroll bottom` starts at the small and lock screen widgets,
/// `large` at the large widgets and `extraLarge` at iOS 27's extra large
/// portrait one. The sections before the start are left out rather than
/// scrolled past, so a screenshot starts at the section's heading instead of
/// with the end of the widget before it under the status bar.
/// `-KeaserGalleryRendering accented` draws the home screen widgets as a
/// tinted or clear home screen would.
///
/// Home screen widgets follow the current appearance, as on a real home
/// screen; lock screen widgets look the same in both, as the system draws
/// them.
struct WidgetGallery: View {
    let showsLockedStates: Bool

    // iPhone 16 Pro sizes, and the home screen's side margin on it.
    private static let small = CGSize(width: 158, height: 158)
    private static let medium = CGSize(width: 338, height: 158)
    private static let large = CGSize(width: 338, height: 354)
    /// Four columns by six rows of the same grid: three rows of small
    /// widgets and the two gaps between them (large is two rows and a gap).
    private static let extraLargePortrait = CGSize(width: 338, height: 158 * 3 + (354 - 158 * 2) * 2)
    private static let rectangular = CGSize(width: 172, height: 76)
    private static let circular = CGSize(width: 72, height: 72)
    private static let inline = CGSize(width: 250, height: 26)
    private static let margin: CGFloat = 32

    /// A plain home screen behind the widgets: the light grey and the black
    /// the reference widgets sit on, so the two compare side by side.
    private static let homeScreen = Color(light: Color(white: 239 / 255), dark: .black)

    /// A stand-in for the tint a tinted home screen gives the accent group
    /// (the total and the bars), in the accented preview.
    private static let previewTint = Color(red: 0.62, green: 0.84, blue: 1)

    private let now = Date.now
    private let start = DebugLaunch.string("KeaserGalleryScroll").flatMap(Section.init(rawValue:)) ?? .top
    private let isAccented = DebugLaunch.string("KeaserGalleryRendering") == "accented"

    /// The gallery's sections in order; `-KeaserGalleryScroll` names the one
    /// it starts at (all but `top`).
    private enum Section: String, CaseIterable {
        case top, bottom, large, extraLarge
    }

    /// Whether `section` is on the page: it is the start or comes after it.
    private func shows(_ section: Section) -> Bool {
        let order = Section.allCases
        return order.firstIndex(of: section)! >= order.firstIndex(of: start)!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if start == .top {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(isAccented ? Color.white : Color.keaserPrimaryText)
                }
                if showsLockedStates { lockedStates } else { readyStates }
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(background.ignoresSafeArea())
    }

    private var title: String {
        let base = showsLockedStates ? "Widgets: locked and empty" : "Widgets"
        return isAccented ? "\(base), accented" : base
    }

    @ViewBuilder
    private var background: some View {
        if isAccented {
            // A wallpaper for the glass to sit on.
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.16, blue: 0.3), Color(red: 0.26, green: 0.12, blue: 0.3), Color(red: 0.06, green: 0.06, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Self.homeScreen
        }
    }

    @ViewBuilder
    private var readyStates: some View {
        let demo = DemoData.database(.demo, now: now)
        if shows(.top) {
            section("Home Screen")
            // The three periods the reference stacks, with its spacing.
            VStack(spacing: 18) {
                home(snapshot(demo, .today), .systemMedium)
                home(snapshot(demo, .thisWeek), .systemMedium)
                home(snapshot(demo, .thisMonth), .systemMedium)
            }
        }
        if shows(.bottom) {
            if start == .bottom { section("Home Screen") }
            // Two small widgets span a medium one, as on the home screen.
            HStack(spacing: Self.medium.width - Self.small.width * 2) {
                home(snapshot(demo, .thisMonth), .systemSmall)
                home(snapshot(demo, .thisWeek), .systemSmall)
            }
            section("Lock Screen")
            lockScreen(
                rectangular: snapshot(demo, .today),
                circular: snapshot(demo, .thisMonth),
                inline: snapshot(demo, .thisMonth)
            )
        }
        if shows(.large) {
            section("Large")
            home(snapshot(demo, .thisMonth), .systemLarge)
            home(snapshot(demo, .today), .systemLarge)
        }
        // The last section, so always on the page.
        if #available(iOS 27.0, *) {
            section("Extra Large Portrait")
            home(snapshot(demo, .thisMonth), .systemExtraLargePortrait)
        }
    }

    @ViewBuilder
    private var lockedStates: some View {
        let locked = snapshot(expiredPass, .thisMonth)
        let empty = snapshot(DemoData.database(.onboarded, now: now), .thisMonth)
        if shows(.top) {
            section("Pass over")
            HStack(spacing: Self.medium.width - Self.small.width * 2) {
                home(locked, .systemSmall)
                home(empty, .systemSmall)
            }
            home(locked, .systemMedium)
        }
        if shows(.bottom) {
            section("Lock Screen, pass over")
            lockScreen(rectangular: locked, circular: locked, inline: locked)
            section("Lock Screen, no account")
            lockScreen(rectangular: empty, circular: empty, inline: empty)
        }
        if shows(.large) {
            section("Large, pass over")
            home(locked, .systemLarge)
            section("Large, no account")
            home(empty, .systemLarge)
        }
        // The last section, so always on the page.
        if #available(iOS 27.0, *) {
            section("Extra Large Portrait, pass over")
            home(locked, .systemExtraLargePortrait)
        }
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
            .foregroundStyle(isAccented ? Color.white.opacity(0.6) : Color.keaserSecondaryText)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func home(_ snapshot: SpendingSnapshot, _ family: WidgetFamily) -> some View {
        let size = size(of: family)
        if isAccented {
            AccentedPreviewFrame(size: size) {
                SpendingWidgetView(snapshot: snapshot, family: family, inApp: true)
            }
            .environment(\.widgetRenderingMode, .accented)
            .environment(\.widgetPreviewAccent, Self.previewTint)
        } else {
            WidgetPreviewFrame(size: size) {
                SpendingWidgetView(snapshot: snapshot, family: family, inApp: true)
            }
        }
    }

    private func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: Self.medium
        case .systemLarge: Self.large
        default: family.isExtraLargePortrait ? Self.extraLargePortrait : Self.small
        }
    }

    /// Accessory widgets on a lock-screen-like backdrop, in the white the
    /// system renders them in. The system draws them vibrant white over the
    /// wallpaper in either appearance, so this backdrop and its dark scheme
    /// are fixed on purpose.
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

/// A home screen widget as a tinted or clear home screen draws it: the
/// widget's own surface replaced by glass over the wallpaper, and its content
/// white, with the accent group in the tint. An approximation for checking
/// hierarchy; the system's own rendering is the reference.
private struct AccentedPreviewFrame<Content: View>: View {
    var size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous)
        content
            .foregroundStyle(.white)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Color.white.opacity(0.06), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .environment(\.colorScheme, .dark)
    }
}
#endif
