import KeaserKit
import SwiftUI
import UIKit
import WidgetKit

// Compiled into both the widget extension and the app, so onboarding and the
// debug gallery draw the real widget rather than a look-alike.
//
// Text uses the text style whose default size is the measured one, so it
// follows Dynamic Type; `SpendingWidgetView` caps how far, since a widget's
// frame never grows. The total keeps a fixed size: it is fitted to that fixed
// frame and shrinks to fit instead.

/// Widget colours. The app's Theme is not part of the extension, so the few
/// shades a widget needs live here. The widget follows the system appearance
/// like the system's own: near-black with white type in dark mode, white with
/// black type in light mode (both measured from the reference).
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
/// screen (accented), and wherever the system draws the widget vibrant, it
/// turns every opaque colour into one white, so hierarchical styles keep the
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

/// The Spending widget: the medium widget's caption over the total, or its
/// locked and no-account states. The widget offers only the medium size;
/// `.systemSmall` draws the small widget of the onboarding illustration.
/// `inApp` marks a widget the app draws (onboarding, the debug gallery, the
/// spending answer) rather than WidgetKit; both draw the same.
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
            case .locked: LockedWidgetView(inks: inks)
            case .noAccount: NoAccountWidgetView(inks: inks)
            }
        }
        // Beyond this the text no longer fits the widget's fixed frame.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder
    private var ready: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    /// The caption and the total, centred, and nothing else.
    private var medium: some View {
        VStack(spacing: 7) {
            Text(snapshot.spentCaption)
                .font(.footnote)
                .foregroundStyle(inks.secondary)
                .lineLimit(1)
            Text(snapshot.formattedTotal)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(inks.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The onboarding illustration's small widget: the period over the total.
    private var small: some View {
        VStack(spacing: 6) {
            Text(snapshot.caption)
                .font(.subheadline)
                .foregroundStyle(inks.secondary)
                .lineLimit(1)
            Text(snapshot.formattedTotal)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(inks.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .widgetAccentable()
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown once the Pro pass has run out. Tapping opens Settings, where Pro
/// can be bought.
private struct LockedWidgetView: View {
    let inks: WidgetInks

    var body: some View {
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
    }
}

/// The lock on its tile.
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
    let inks: WidgetInks

    var body: some View {
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
