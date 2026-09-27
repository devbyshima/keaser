import KeaserKit
import SwiftUI
import UIKit
import WidgetKit

// Compiled into both the widget extension and the app, so onboarding and the
// debug gallery draw the real widget rather than a look-alike.
//
// Text uses the text style whose default size is the measured one, so it
// follows Dynamic Type; `SpendingWidgetView` caps how far, since a widget's
// frame never grows. The totals and the tiny chart and circular labels keep
// fixed sizes: they are fitted to that fixed frame and shrink to fit instead.

/// Widget colours. The app's Theme is not part of the extension, so the few
/// shades a widget needs live here. Home screen widgets follow the system
/// appearance like the system's own: charcoal with white type (measured from
/// the reference) in dark mode, white with black type in light mode.
/// Lock screen widgets use none of these; the system renders them vibrant.
enum WidgetPalette {
    static let background = adaptive(light: .white, dark: Color(red: 57 / 255, green: 56 / 255, blue: 59 / 255))
    /// The total, titles and glyphs, and today's bar and label.
    static let primaryText = adaptive(light: .black, dark: .white)
    /// The period caption ("This Month").
    static let secondaryText = adaptive(light: Color(white: 0.45), dark: Color(white: 0.53))
    /// The account name and chart labels. They are smaller than the caption,
    /// so they sit further from the surface to stay readable (4.6:1 on the
    /// charcoal, 5.7:1 on white).
    static let smallText = adaptive(light: Color(white: 0.4), dark: Color(white: 0.64))
    static let inactiveBar = adaptive(light: .black.opacity(0.14), dark: .white.opacity(0.2))
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

/// The Spending widget for one family. `inApp` swaps the system-provided
/// lock screen background, which only exists inside WidgetKit, for a drawn one.
struct SpendingWidgetView: View {
    let snapshot: SpendingSnapshot
    let family: WidgetFamily
    var inApp = false

    var body: some View {
        Group {
            switch snapshot.state {
            case .ready: ready
            case .locked: LockedWidgetView(family: family, inApp: inApp)
            case .noAccount: NoAccountWidgetView(family: family, inApp: inApp)
            }
        }
        // Beyond this the text no longer fits the widget's fixed frame.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder
    private var ready: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            Text(snapshot.caption)
                .font(.subheadline)
                .foregroundStyle(WidgetPalette.secondaryText)
                .lineLimit(1)
            total(size: 31)
            if let name = snapshot.accountName {
                Text(name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(WidgetPalette.smallText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.caption)
                    .font(.subheadline)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .lineLimit(1)
                total(size: 31)
                Spacer(minLength: 0)
                if let name = snapshot.accountName {
                    Text(name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(WidgetPalette.smallText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SpendingBars(bars: snapshot.bars)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.caption)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(snapshot.formattedTotal)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(snapshot.accountName ?? "Keaser")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryBackground(inApp: inApp)
            VStack(spacing: 0) {
                Text(snapshot.shortCaption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(snapshot.compactTotal())
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
            }
            .padding(6)
        }
    }

    private var inline: some View {
        Label(snapshot.inlineText, systemImage: "creditcard")
    }

    private func total(size: CGFloat) -> some View {
        Text(snapshot.formattedTotal)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(WidgetPalette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .widgetAccentable()
    }
}

/// The medium widget's chart: one bar per day or month, today's in full ink.
struct SpendingBars: View {
    let bars: [SpendingSnapshot.Bar]

    var body: some View {
        let peak = bars.map(\.amount.doubleValue).max() ?? 0
        // A month of days only has room for a label every week.
        let labelEvery = bars.count > 14 ? 7 : 1
        HStack(alignment: .bottom, spacing: bars.count > 14 ? 2 : 6) {
            ForEach(bars) { bar in
                VStack(spacing: 5) {
                    GeometryReader { proxy in
                        let fraction = peak > 0 ? bar.amount.doubleValue / peak : 0
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(bar.isCurrent ? WidgetPalette.primaryText : WidgetPalette.inactiveBar)
                                // Empty days keep a stub so the shape of the period shows.
                                .frame(height: max(4, proxy.size.height * fraction))
                        }
                    }
                    Text(bar.id % labelEvery == 0 ? bar.label : " ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(bar.isCurrent ? WidgetPalette.primaryText : WidgetPalette.smallText)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending chart")
    }
}

/// Shown once the Pro pass has run out. Tapping opens Settings, where Pro
/// can be bought.
struct LockedWidgetView: View {
    let family: WidgetFamily
    var inApp = false

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Keaser Pro", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Widgets are part of Keaser Pro.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            ZStack {
                AccessoryBackground(inApp: inApp)
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
        case .accessoryInline:
            Label("Keaser Pro needed", systemImage: "lock.fill")
        case .systemMedium:
            HStack(spacing: 14) {
                lockTile
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widgets are part of Keaser Pro")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.primaryText)
                    Text("Tap to open Settings and upgrade to keep your spending on the home screen.")
                        .font(.footnote)
                        .foregroundStyle(WidgetPalette.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(alignment: .leading, spacing: 4) {
                lockTile
                Spacer(minLength: 0)
                Text("Keaser Pro")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.primaryText)
                    .lineLimit(1)
                Text("Widgets are part of Keaser Pro. Tap to upgrade.")
                    .font(.footnote)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .lineLimit(3)
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var lockTile: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 17, weight: .semibold))
            .accessibilityHidden(true)
            .foregroundStyle(WidgetPalette.primaryText)
            .frame(width: 36, height: 36)
            .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Shown before the first account exists. Tapping opens the app.
struct NoAccountWidgetView: View {
    let family: WidgetFamily
    var inApp = false

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("No Account")
                    .font(.subheadline.weight(.semibold))
                Text("Add one in Keaser.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            ZStack {
                AccessoryBackground(inApp: inApp)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
            }
        case .accessoryInline:
            Text("Add an account in Keaser")
        default:
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(WidgetPalette.primaryText)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                Text("No Account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetPalette.primaryText)
                Text("Add an account in Keaser to see your spending.")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
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
