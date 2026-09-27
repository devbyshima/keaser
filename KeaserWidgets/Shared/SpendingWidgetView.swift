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
    /// The account name. It is smaller than the caption, so it sits further
    /// from the surface to stay readable (7.3:1 on the near-black, 5.7:1 on
    /// white).
    static let smallText = adaptive(light: Color(white: 0.4), dark: Color(white: 0.64))
    /// The tile behind the lock on the locked widget and behind category
    /// symbols on the large widgets.
    static let tile = adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.12))
    /// The empty part of a breakdown bar: the ink at the chart's inactive
    /// strength, a little firmer than the tile so a 4pt line still shows.
    static let track = adaptive(light: .black.opacity(0.09), dark: .white.opacity(0.16))
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

/// The home screen widgets' colours for the way the system is drawing them.
/// In full colour they are `WidgetPalette`'s measured shades. On a tinted or
/// clear home screen (accented) and in StandBy (vibrant) the system turns
/// every opaque colour into one white, so hierarchical styles keep the
/// caption and labels quieter than the total there, and the total and the
/// bars go in the accent group, which takes the home screen's tint.
struct WidgetInks {
    var mode: WidgetRenderingMode
    /// Stands in for that tint in the app's widget gallery, where
    /// `widgetAccentable()` does nothing. Nil inside WidgetKit.
    var previewAccent: Color?

    var isFullColor: Bool { mode == .fullColor }

    /// Titles, names and amounts.
    var primary: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.primaryText) : AnyShapeStyle(.primary) }
    /// Captions ("Spent This Month") and dates.
    var secondary: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.secondaryText) : AnyShapeStyle(.secondary) }
    /// The account name on the small widget.
    var small: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.smallText) : AnyShapeStyle(.secondary) }
    /// Symbol tiles.
    var tile: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.tile) : AnyShapeStyle(.primary.opacity(0.14)) }
    /// The empty part of a breakdown bar.
    var track: AnyShapeStyle { isFullColor ? AnyShapeStyle(WidgetPalette.track) : AnyShapeStyle(.primary.opacity(0.2)) }
    /// The total and the filled part of a bar; mark them `widgetAccentable()`.
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

    /// The families with the category breakdown: large, and iOS 27's extra
    /// large portrait.
    var hasBreakdown: Bool { self == .systemLarge || isExtraLargePortrait }
}

/// The Spending widget for one family. `inApp` swaps the system-provided
/// lock screen background, which only exists inside WidgetKit, for a drawn one.
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
        case .systemLarge: SpendingBreakdownView(snapshot: snapshot, inks: inks, showsLatest: false)
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default:
            if family.isExtraLargePortrait {
                SpendingBreakdownView(snapshot: snapshot, inks: inks, showsLatest: true)
            } else {
                small
            }
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            Text(snapshot.caption)
                .font(.subheadline)
                .foregroundStyle(inks.secondary)
                .lineLimit(1)
            total(size: 31)
            if let name = snapshot.accountName {
                Text(name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(inks.small)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The caption and the total, centred, and nothing else.
    private var medium: some View {
        SpendingHeadline(snapshot: snapshot, inks: inks)
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
            .foregroundStyle(inks.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .widgetAccentable()
    }
}

/// The medium widget's caption over its total, which the large widgets
/// also lead with.
private struct SpendingHeadline: View {
    let snapshot: SpendingSnapshot
    let inks: WidgetInks

    var body: some View {
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
    }
}

/// The large widgets: the medium widget's caption and total, then what each
/// category took in the period with a thin bar for its share of the total,
/// the largest first and the rest grouped as Other. The extra large portrait
/// widget adds the period's latest expenses under it.
private struct SpendingBreakdownView: View {
    let snapshot: SpendingSnapshot
    let inks: WidgetInks
    let showsLatest: Bool

    /// Category rows and latest expenses to try, most first: the first that
    /// fits the widget under the headline is shown, so larger text sizes
    /// drop rows instead of cutting one off.
    private var plans: [(categories: Int, latest: Int)] {
        showsLatest
            ? [(5, 5), (5, 4), (5, 3), (4, 3), (4, 2), (3, 2), (3, 1), (2, 1)]
            : [(6, 0), (5, 0), (4, 0), (3, 0), (2, 0), (1, 0)]
    }

    var body: some View {
        VStack(spacing: 0) {
            SpendingHeadline(snapshot: snapshot, inks: inks)
            if snapshot.categories.isEmpty {
                Text(snapshot.emptyText)
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach(plans.indices, id: \.self) { index in
                        rows(categories: plans[index].categories, latest: plans[index].latest)
                    }
                }
                .padding(.top, 20)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func rows(categories: Int, latest: Int) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ForEach(snapshot.categoryRows(maxRows: categories)) { row in
                    CategoryShareRow(
                        row: row,
                        amount: snapshot.formatted(row.amount),
                        share: snapshot.share(of: row.amount),
                        inks: inks
                    )
                }
            }
            if latest > 0, !snapshot.latest.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Latest")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(inks.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(snapshot.latest.prefix(latest)) { expense in
                        LatestExpenseRow(expense: expense, amount: snapshot.formatted(expense.amount), inks: inks)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
            }
        }
    }
}

/// A category's symbol on its tile, its name and amount, and under them a
/// bar filled to its share of the period's total.
private struct CategoryShareRow: View {
    let row: SpendingSnapshot.CategoryTotal
    let amount: String
    let share: Double
    let inks: WidgetInks

    var body: some View {
        HStack(spacing: 10) {
            WidgetSymbolTile(symbol: row.symbol, inks: inks)
            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(inks.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(amount)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(inks.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                ShareBar(share: share, inks: inks)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue("\(amount), \(share.formatted(.percent.precision(.fractionLength(0))))")
    }
}

/// A thin capsule in the track tone, filled from the leading edge to
/// `share` of its width in the accent. Any spending shows at least a dot.
private struct ShareBar: View {
    let share: Double
    let inks: WidgetInks

    private static let height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(inks.track)
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(inks.accent)
                        .frame(width: share > 0 ? max(Self.height, geometry.size.width * share) : 0)
                        .widgetAccentable()
                }
            }
            .accessibilityHidden(true)
    }
}

/// One of the latest expenses: category symbol, title over its date, and
/// the amount.
private struct LatestExpenseRow: View {
    let expense: SpendingSnapshot.LatestExpense
    let amount: String
    let inks: WidgetInks

    var body: some View {
        HStack(spacing: 10) {
            WidgetSymbolTile(symbol: expense.symbol, inks: inks)
            VStack(alignment: .leading, spacing: 0) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(inks.primary)
                    .lineLimit(1)
                Text(expense.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(inks.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(inks.primary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An SF Symbol on the widget's faint rounded tile, like the symbol tiles
/// of the app's expense rows.
private struct WidgetSymbolTile: View {
    let symbol: String
    let inks: WidgetInks

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(inks.primary)
            .frame(width: size, height: size)
            .background(inks.tile, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The large widgets once the Pro pass is over: the lock and the message,
/// over the outline of a breakdown in the faintest tones, so it is clear
/// what upgrading brings back.
private struct LockedBreakdownView: View {
    let inks: WidgetInks
    let rows: Int

    /// The bars' fill in each outline row, largest first.
    private static let shares: [CGFloat] = [0.82, 0.6, 0.44, 0.32, 0.24, 0.17, 0.12, 0.08, 0.05]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                WidgetLockTile(inks: inks)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Widgets are part of Keaser Pro")
                        .font(.headline)
                        .foregroundStyle(inks.primary)
                    Text("Tap to open Settings and upgrade to see where your money goes.")
                        .font(.footnote)
                        .foregroundStyle(inks.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                ForEach(0..<rows, id: \.self) { index in
                    outlineRow(share: Self.shares[index % Self.shares.count])
                }
            }
            .padding(.top, 26)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func outlineRow(share: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(inks.tile)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 7) {
                Capsule()
                    .fill(inks.tile)
                    .frame(width: 70 + 60 * share, height: 8)
                Capsule()
                    .fill(inks.track)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(inks.track)
                                .frame(width: geometry.size.width * share)
                        }
                    }
            }
        }
    }
}

/// Shown once the Pro pass has run out. Tapping opens Settings, where Pro
/// can be bought.
struct LockedWidgetView: View {
    let family: WidgetFamily
    var inApp = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var inks: WidgetInks { WidgetInks(mode: renderingMode) }

    var body: some View {
        if family.hasBreakdown {
            LockedBreakdownView(inks: inks, rows: family.isExtraLargePortrait ? 9 : 5)
        } else {
            compact
        }
    }

    @ViewBuilder
    private var compact: some View {
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
                        .foregroundStyle(inks.primary)
                    Text("Tap to open Settings and upgrade to keep your spending on the home screen.")
                        .font(.footnote)
                        .foregroundStyle(inks.secondary)
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
                    .foregroundStyle(inks.primary)
                    .lineLimit(1)
                Text("Widgets are part of Keaser Pro. Tap to upgrade.")
                    .font(.footnote)
                    .foregroundStyle(inks.secondary)
                    .lineLimit(3)
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var lockTile: some View {
        WidgetLockTile(inks: inks)
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
struct NoAccountWidgetView: View {
    let family: WidgetFamily
    var inApp = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var inks: WidgetInks { WidgetInks(mode: renderingMode) }

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
                    .font(.system(size: family.hasBreakdown ? 32 : 24))
                    .foregroundStyle(inks.primary)
                    .padding(.bottom, family.hasBreakdown ? 8 : 4)
                    .accessibilityHidden(true)
                Text("No Account")
                    .font(family.hasBreakdown ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(inks.primary)
                Text("Add an account in Keaser to see your spending.")
                    .font(family.hasBreakdown ? .footnote : .caption)
                    .foregroundStyle(inks.secondary)
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
