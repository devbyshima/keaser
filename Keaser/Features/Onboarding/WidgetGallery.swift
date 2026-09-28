#if DEBUG
import KeaserKit
import SwiftUI
import WidgetKit

/// The Spending widget at its real point size, drawn with the widget's own
/// view, so screenshots can check it without adding it to a home screen.
/// Opened with `-KeaserOnboardingPage widgetGallery` (demo data: Today, This
/// Week and This Month) or `widgetGalleryLocked` (the Pro-locked and
/// no-account states). `-KeaserGalleryRendering accented` draws the widgets
/// as a tinted or clear home screen would.
///
/// The widgets follow the current appearance, as on a real home screen.
struct WidgetGallery: View {
    let showsLockedStates: Bool

    // The medium widget on iPhone 16 Pro, and the home screen's side margin
    // there.
    private static let medium = CGSize(width: 338, height: 158)
    private static let margin: CGFloat = 32

    /// A plain home screen behind the widgets: the light grey and the black
    /// the reference widgets sit on, so the two compare side by side.
    private static let homeScreen = Color(light: Color(white: 239 / 255), dark: .black)

    /// A stand-in for the tint a tinted home screen gives the accent group
    /// (the total), in the accented preview.
    private static let previewTint = Color(red: 0.62, green: 0.84, blue: 1)

    private let now = Date.now
    private let isAccented = DebugLaunch.string("KeaserGalleryRendering") == "accented"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(isAccented ? Color.white : Color.keaserPrimaryText)
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
        section("Home Screen")
        // The three periods the reference stacks, with its spacing.
        VStack(spacing: 18) {
            widget(snapshot(demo, .today))
            widget(snapshot(demo, .thisWeek))
            widget(snapshot(demo, .thisMonth))
        }
    }

    @ViewBuilder
    private var lockedStates: some View {
        section("Pass over")
        widget(snapshot(expiredPass, .thisMonth))
        section("No account")
        widget(snapshot(DemoData.database(.onboarded, now: now), .thisMonth))
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
    private func widget(_ snapshot: SpendingSnapshot) -> some View {
        if isAccented {
            AccentedPreviewFrame(size: Self.medium) {
                SpendingWidgetView(snapshot: snapshot, family: .systemMedium, inApp: true)
            }
            .environment(\.widgetRenderingMode, .accented)
            .environment(\.widgetPreviewAccent, Self.previewTint)
        } else {
            WidgetPreviewFrame(size: Self.medium) {
                SpendingWidgetView(snapshot: snapshot, family: .systemMedium, inApp: true)
            }
        }
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
