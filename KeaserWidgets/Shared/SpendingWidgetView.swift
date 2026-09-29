import KeaserKit
import SwiftUI
import UIKit
import WidgetKit

// Compiled into both the widget extension and the app, so onboarding and the
// debug gallery draw the real widget rather than a look-alike.
//
// Text uses the text style whose default size is the measured one, so it
// follows Dynamic Type; `SpendingWidgetView` caps how far, since a widget's
// frame never grows. The totals and the tiny circular labels keep fixed
// sizes: they are fitted to that fixed frame and shrink to fit instead.

/// Widget colours. The app's Theme is not part of the extension, so the few
/// shades a widget needs live here. Home screen widgets follow the system
/// appearance like the system's own: near-black with white type in dark mode,
/// white with black type in light mode (both measured from the reference).
/// Lock screen widgets use none of these; the system renders them vibrant.
enum WidgetPalette {
    static let background = adaptive(light: .white, dark: Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255))
    /// The total, titles and glyphs.
    static let primaryText = adaptive(light: .black, dark: .white)
    /// The period caption ("Spent This Month", "This Month").
    static let secondaryText = adaptive(light: Color(white: 0.46), dark: Color(white: 0.58))
    /// The tile behind the lock on the locked widget.
    static let tile = adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.12))
    /// The home screen widget corner, for drawing widgets inside the app.
    static let cornerRadius: CGFloat = 24

    /// One colour per appearance, resolved whenever the appearance changes.
    /// The same as the app's `Color(light:dark:)`, which lives in its Theme.
    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// The widget's colours for the way the system is drawing it. In full colour
/// they are `WidgetPalette`'s measured shades. On a tinted or clear home
/// screen (accented), in StandBy and on the lock screen (vibrant), it turns
/// every opaque colour into one white, so hierarchical styles keep the
/// caption quieter than the total there, and the total goes in the accent
/// group, which takes the home screen's tint.
struct WidgetInks {
    var mode: WidgetRenderingMode
    /// Stands in for that tint in the app's widget gallery, where
    /// `widgetAccentable()` does nothing. Nil inside WidgetKit.
    var previewAccent: Color?

    var isFullColor: Bool { mode == .fullColor }

    /// Titles and glyphs.
    var primary: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.primaryText) : AnyShapeStyle(.primary) }
    /// Captions ("Spent This Month").
    var secondary: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.secondaryText) : AnyShapeStyle(.secondary) }
    /// The lock's tile.
    var tile: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.tile) : AnyShapeStyle(.primary.opacity(0.14)) }
    /// The total; mark it `widgetAccentable()`.
    var accent: AnyShapeStyle {
        if isFullColor { return AnyShapeStyle(WidgetPalette.primaryText) }
        return previewAccent.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
    }
}

extension EnvironmentValues {
    /// The home screen tint the app's widget gallery pretends to have when
    /// it previews accented rendering. Never set inside WidgetKit.
    @Entry var widgetPreviewAccent: Color?
}

extension WidgetFamily {
    /// The lock screen families, which the system draws vibrant on the
    /// wallpaper with no container background.
    var isAccessory: Bool {
        self == .accessoryRectangular || self == .accessoryCircular || self == .accessoryInline
    }

    /// iOS 27's page-tall widget. Always false before iOS 27, where the case
    /// does not exist.
    var isExtraLargePortrait: Bool {
        if #available(iOS 27.0, *) { return self == .systemExtraLargePortrait }
        return false
    }
}

/// How large a home screen widget draws its caption and total. The medium
/// widget's sizes are measured from the reference; every other size is the
/// medium one sized up or down: its caption takes a text style a step or two
/// away from the footnote, and the total and the gap keep the medium's
/// proportion to it.
struct SpendingHeadlineMetrics {
    var caption: Font
    var total: CGFloat
    var spacing: CGFloat

    /// The medium widget's footnote (13pt) over a 30pt total, 7pt apart.
    /// The rectangular lock screen widget uses it too.
    static let medium = SpendingHeadlineMetrics(caption: .footnote, total: 30, spacing: 7)
    /// Caption 2 (11pt) over 25pt, 6pt apart.
    static let small = scaled(.caption2, points: 11)
    /// Title 3 (20pt) over 46pt, 11pt apart.
    static let large = scaled(.title3, points: 20)
    /// Title (28pt) over 65pt, 15pt apart.
    static let extraLargePortrait = scaled(.title, points: 28)

    static func of(_ family: WidgetFamily) -> SpendingHeadlineMetrics {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: family.isExtraLargePortrait ? .extraLargePortrait : .medium
        }
    }

    /// The medium's sizes scaled so the caption is `style`, whose default
    /// size is `points`.
    private static func scaled(_ style: Font, points: CGFloat) -> SpendingHeadlineMetrics {
        let scale = points / 13
        return SpendingHeadlineMetrics(caption: style, total: (30 * scale).rounded(), spacing: (7 * scale).rounded())
    }
}

/// The Spending widget for one family: the period's caption ("Spent This
/// Month") over the total, centred, and nothing else, in every size, or its
/// locked and no-account states. `inApp` marks a widget the app draws
/// (onboarding, the debug gallery, the spending answer) rather than
/// WidgetKit; it swaps the circular lock screen backdrop, which only exists
/// inside WidgetKit, for a drawn one.
struct SpendingWidgetView: View {
    let snapshot: SpendingSnapshot
    let family: WidgetFamily
    var inApp = false

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetPreviewAccent) private var previewAccent

    private var inks: WidgetInks { WidgetInks(mode: renderingMode, previewAccent: previewAccent) }

    var body: some View {
        Group {
            switch snapshot.state {
            case .ready: ready
            case .locked: LockedWidgetView(family: family, inks: inks, inApp: inApp)
            case .noAccount: NoAccountWidgetView(family: family, inks: inks, inApp: inApp)
            }
        }
        // Beyond this the text no longer fits the widget's fixed frame.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder
    private var ready: some View {
        switch family {
        case .accessoryRectangular: SpendingHeadline(snapshot: snapshot, inks: inks, metrics: .medium)
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: SpendingHeadline(snapshot: snapshot, inks: inks, metrics: .of(family))
        }
    }

    /// "Month" over a compact total ("$271", "$1.4K") on the system's disc.
    private var circular: some View {
        ZStack {
            AccessoryBackground(inApp: inApp)
            VStack(spacing: 0) {
                Text(snapshot.shortCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(inks.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(snapshot.compactTotal())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(inks.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
            }
            .padding(.horizontal, 7)
        }
    }

    /// "Spent This Month: $271.37", or "Month: $271" where that does not fit.
    private var inline: some View {
        ViewThatFits(in: .horizontal) {
            Text(snapshot.inlineText())
            Text(snapshot.shortInlineText())
        }
    }
}

/// The caption over the total, centred in the widget.
private struct SpendingHeadline: View {
    let snapshot: SpendingSnapshot
    let inks: WidgetInks
    let metrics: SpendingHeadlineMetrics

    var body: some View {
        VStack(spacing: metrics.spacing) {
            Text(snapshot.spentCaption)
                .font(metrics.caption)
                .foregroundStyle(inks.secondary)
                .lineLimit(1)
            Text(snapshot.formattedTotal)
                .font(.system(size: metrics.total, weight: .bold))
                .foregroundStyle(inks.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown once the Pro pass has run out. Tapping opens Settings, where Pro
/// can be bought.
private struct LockedWidgetView: View {
    let family: WidgetFamily
    let inks: WidgetInks
    let inApp: Bool

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(spacing: 2) {
                Label("Keaser Pro", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(inks.primary)
                    .lineLimit(1)
                Text("Tap to upgrade")
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .accessoryCircular:
            ZStack {
                AccessoryBackground(inApp: inApp)
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(inks.primary)
                    .accessibilityLabel("Keaser Pro needed")
            }
        case .accessoryInline:
            Label("Keaser Pro needed", systemImage: "lock.fill")
        case .systemMedium:
            HStack(spacing: 14) {
                WidgetLockTile(inks: inks)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widgets are part of Keaser Pro")
                        .font(.headline)
                        .foregroundStyle(inks.primary)
                    Text("Tap to open Settings and upgrade to keep your spending on the home screen.")
                        .font(.footnote)
                        .foregroundStyle(inks.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .systemSmall:
            VStack(spacing: 4) {
                WidgetLockTile(inks: inks)
                    .padding(.bottom, 4)
                Text("Keaser Pro")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(inks.primary)
                    .lineLimit(1)
                Text("Tap to upgrade and see your spending.")
                    .font(.caption)
                    .foregroundStyle(inks.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            // Large and extra large portrait: the medium's lock and words,
            // stacked in the middle like the total they stand in for.
            VStack(spacing: 4) {
                WidgetLockTile(inks: inks)
                    .padding(.bottom, 8)
                Text("Widgets are part of Keaser Pro")
                    .font(.headline)
                    .foregroundStyle(inks.primary)
                Text("Tap to open Settings and upgrade to keep your spending on the home screen.")
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The lock on its tile, on every locked home screen widget.
private struct WidgetLockTile: View {
    let inks: WidgetInks

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 17, weight: .semibold))
            .accessibilityHidden(true)
            .foregroundStyle(inks.primary)
            .frame(width: 36, height: 36)
            .background(inks.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Shown before the first account exists. Tapping opens the app.
private struct NoAccountWidgetView: View {
    let family: WidgetFamily
    let inks: WidgetInks
    let inApp: Bool

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(spacing: 2) {
                Text("No Account")
                    .font(.headline)
                    .foregroundStyle(inks.primary)
                    .lineLimit(1)
                Text("Add one in Keaser")
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .accessoryCircular:
            ZStack {
                AccessoryBackground(inApp: inApp)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(inks.primary)
                    .accessibilityLabel("No account")
            }
        case .accessoryInline:
            Text("Add an account in Keaser")
        case .systemSmall, .systemMedium:
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(inks.primary)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                Text("No Account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(inks.primary)
                Text("Add an account in Keaser to see your spending.")
                    .font(.caption)
                    .foregroundStyle(inks.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(inks.primary)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text("No Account")
                    .font(.headline)
                    .foregroundStyle(inks.primary)
                Text("Add an account in Keaser to see your spending.")
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The circular lock screen backdrop: the system's inside WidgetKit, a drawn
/// stand-in inside the app. The lock screen draws it as a light veil over the
/// wallpaper whatever the appearance, so the stand-in is fixed too.
private struct AccessoryBackground: View {
    let inApp: Bool

    var body: some View {
        if inApp {
            Circle().fill(Color.white.opacity(0.16))
        } else {
            AccessoryWidgetBackground()
        }
    }
}

/// A home screen widget drawn inside the app at its real size, with the
/// surface and corners WidgetKit would give it, in the current appearance.
struct WidgetPreviewFrame<Content: View>: View {
    var size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetPalette.background, in: RoundedRectangle(cornerRadius: WidgetPalette.cornerRadius, style: .continuous))
    }
}
