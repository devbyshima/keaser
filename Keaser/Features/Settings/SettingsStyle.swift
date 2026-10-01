import SwiftUI
import UIKit

// Shared look for every page in the Settings tab: rounded cards on the
// settings canvas (white on grouped grey in light mode, as in the reference;
// Home's charcoal cards on its black canvas in dark mode), 68pt rows with a
// symbol, round glass header buttons. Sheets presented from Settings (the
// label editor, the legal documents) keep the sheet look instead.

extension Color {
    /// Cards on a settings page: white in light mode, Home's charcoal
    /// (`keaserCard`) in dark mode, where the page is black like Home.
    static var settingsCard: Color { .keaserCard }
    /// The tile behind row symbols and the account monogram. Light mode
    /// matches the reference's #EBEBEB on a white card, where the shared
    /// sheet tile would barely show. Dark mode is `keaserSheetTile`'s faint
    /// veil, which lifts the charcoal card by the same few levels it lifted
    /// the sheet's card (3 of 255, as the reference draws it).
    static let settingsTile = Color(light: .black.opacity(0.08), dark: .white.opacity(0.014))
    /// The label editor's preview tile, name field, icon grid and buttons:
    /// white cards on the grey sheet in light mode, as in the reference;
    /// `keaserSheetField` in dark mode.
    static let settingsField = Color(light: .white, dark: .white.opacity(0.03))
    /// Behind every settings page: the grouped grey in light mode, so white
    /// cards stand out; black in dark mode, Home's canvas
    /// (`keaserBackground`), under charcoal cards.
    static let settingsCanvas = Color(light: .init(red: 242 / 255, green: 242 / 255, blue: 247 / 255), dark: .black)
    /// Behind a sheet presented from Settings (the label editor): the same
    /// grey in light mode, and clear in dark mode, which keeps the sheet's
    /// own background.
    static let settingsSheetCanvas = Color(light: .init(red: 242 / 255, green: 242 / 255, blue: 247 / 255), dark: .clear)
}

/// Where a row sits in its card, so its background rounds the right corners.
enum CardPosition {
    case single, first, middle, last

    init(index: Int, count: Int) {
        switch (index, count) {
        case (_, ...1): self = .single
        case (0, _): self = .first
        case (count - 1, _): self = .last
        default: self = .middle
        }
    }

    var roundsTop: Bool { self == .single || self == .first }
    var roundsBottom: Bool { self == .single || self == .last }
}

/// One row's slice of a rounded card. Drawing the corners per row (instead
/// of relying on the list's section shape) gives the same 26pt corners on
/// iOS 18, whose inset-grouped sections are only slightly rounded.
struct CardRowBackground: View {
    let position: CardPosition
    var fill: Color = .settingsCard

    var body: some View {
        let top = position.roundsTop ? KeaserMetrics.cardRadius : 0
        let bottom = position.roundsBottom ? KeaserMetrics.cardRadius : 0
        UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
        .fill(fill)
    }
}

enum SettingsListInset {
    /// iOS 27 puts 4pt more between an inline navigation bar and a list's
    /// first row than iOS 26, where the reference was recorded, so every
    /// settings card sat 4pt low. Taking it back out of the margin puts the
    /// cards where the reference has them; earlier systems use the margin
    /// as it is.
    static func top(_ margin: CGFloat) -> CGFloat {
        if #available(iOS 27.0, *) {
            return max(margin - 4, 0)
        }
        return margin
    }
}

extension EdgeInsets {
    /// Rows with a leading symbol tile.
    static let settingsRow = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 16)
    /// Text-only rows.
    static let settingsTextRow = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
}

extension View {
    /// The list look shared by every settings page. `sectionSpacing` is the
    /// gap between cards; pages whose sections carry a `SettingsSectionTitle`
    /// use a tighter one, since the title row adds its own height.
    /// `topMargin` is the space under the navigation bar as iOS 26 lays it
    /// out (see `SettingsListInset`).
    func settingsListStyle(sectionSpacing: CGFloat = 35, topMargin: CGFloat = 39) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.settingsCanvas.ignoresSafeArea())
            .keaserReadableScrollContent(base: KeaserMetrics.screenPadding)
            .contentMargins(.top, SettingsListInset.top(topMargin), for: .scrollContent)
            .listSectionSpacing(sectionSpacing)
            // Card rows set their own heights (52, 68 or 74pt); this floor
            // is for title rows and for sections other features embed.
            .environment(\.defaultMinListRowHeight, 44)
    }

    /// Places a row in a card at `position`.
    func cardRow(_ position: CardPosition, insets: EdgeInsets = .settingsRow) -> some View {
        self
            .listRowInsets(insets)
            .listRowBackground(CardRowBackground(position: position))
            .listRowSeparatorTint(Color.keaserListSeparator)
    }

    /// Ends a row's separator 16pt short of the card's edge, as iOS 26 does
    /// (iOS 18 runs it to the edge). Apply to the row's full-width content;
    /// `overChevron` carries it past the chevron a `NavigationLink` adds.
    /// From iOS 26 the system already ends a chevron row's separator there,
    /// and the chevron's spacing differs between releases, so those rows
    /// keep the system's own end.
    @ViewBuilder
    func cardSeparatorTrailing(overChevron: Bool = false) -> some View {
        if #available(iOS 26.0, *), overChevron {
            self
        } else {
            alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + (overChevron ? 20 : 0) }
        }
    }

    /// A list row that is not a card: banners, footers, free text.
    func plainListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// An SF Symbol on the faint square tile the reference puts behind row icons.
/// Tile and symbol grow with the text beside them, up to half as big again,
/// so they keep their proportion at large sizes without crowding the row.
struct SettingsSymbol: View {
    let symbol: String
    var size: CGFloat
    var pointSize: CGFloat

    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    init(symbol: String, size: CGFloat = 38, pointSize: CGFloat = 18) {
        self.symbol = symbol
        self.size = size
        self.pointSize = pointSize
    }

    var body: some View {
        let scale = min(textScale, 1.5)
        Image(systemName: symbol)
            .font(.system(size: pointSize * scale, weight: .medium))
            .foregroundStyle(Color.keaserPrimaryText)
            .frame(width: size * scale, height: size * scale)
            .background(Color.settingsTile, in: RoundedRectangle(cornerRadius: size * scale * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Symbol, title and an optional trailing value. Wrap it in a
/// `NavigationLink` for the chevron, or give it an `accessory` symbol. At
/// accessibility sizes the value moves under the title instead of cutting
/// both short.
struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String?
    var accessory: String?
    /// Whether a `NavigationLink` chevron follows the row.
    var hasDisclosure: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(symbol: String, title: String, value: String? = nil, accessory: String? = nil, hasDisclosure: Bool = true) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.accessory = accessory
        self.hasDisclosure = hasDisclosure
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsSymbol(symbol: symbol)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let value { valueText(value) }
                }
                .padding(.vertical, 12)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
            } else {
                titleText
                    .lineLimit(1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                if let value {
                    valueText(value)
                        .lineLimit(1)
                }
            }
            if let accessory {
                Image(systemName: accessory)
                    .keaserFont(14, weight: .semibold, relativeTo: .footnote)
                    .foregroundStyle(Color.keaserTertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 68)
        .cardSeparatorTrailing(overChevron: hasDisclosure)
        .contentShape(Rectangle())
    }

    /// Medium, as in the reference; the value stays regular.
    private var titleText: some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.keaserPrimaryText)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
    }
}

/// Section title in the iOS 26 style (sentence case, grey, semibold), as
/// the first row of its section. A row rather than a `Section` header so it
/// sits the same distance from the cards on iOS 18 and iOS 26.
struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .keaserFont(17, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(Color.keaserCaptionText)
            .padding(.leading, 16)
            .padding(.top, 13)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .accessibilityAddTraits(.isHeader)
            .plainListRow()
    }
}

/// Small print under a card.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // An exact 13pt font on a 16pt line keeps the tight leading of the
        // reference; the footnote text style adds several points between
        // lines.
        Text(text)
            .keaserFont(13, relativeTo: .footnote)
            .lineSpacing(0.5)
            .foregroundStyle(Color.keaserCaptionText)
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Header buttons

/// A round glass icon button for toolbar headers (close, back, add, done).
/// iOS 26 toolbars put their buttons on glass themselves; earlier systems
/// get a `KeaserCircleButton`.
struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            // Left to the toolbar, which draws its own glass. The close glyph
            // gets the same grey, lighter look as KeaserCircleButton's.
            Button(action: action) {
                if symbol == "xmark" {
                    Image(systemName: symbol)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.keaserCloseGlyph)
                } else {
                    Image(systemName: symbol)
                }
            }
            .accessibilityLabel(label)
            // A checkmark glyph would otherwise make VoiceOver say "selected".
            .accessibilityRemoveTraits(.isSelected)
        } else {
            KeaserCircleButton(symbol, label: label, action: action)
        }
    }
}

extension View {
    /// Title and back button for a page pushed inside Settings.
    func settingsPage(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SettingsBackButton())
    }
}

/// iOS 26's own back button is already a round glass chevron with no title.
/// It keeps the default toolbar role: the editor role would also move the
/// page title next to the back button (iOS 27 does that on iPhone), where
/// the reference centres it. Earlier systems get the same look from a custom
/// button; hiding the system one switches off swipe-to-go-back, so that is
/// switched back on too.
private struct SettingsBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HeaderIconButton("chevron.left", label: "Back") { dismiss() }
                    }
                }
                .background(PopGestureRestorer().frame(width: 0, height: 0))
        }
    }
}

/// Re-enables the edge swipe on the navigation controller hosting a page
/// whose back button is custom.
private struct PopGestureRestorer: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController, let navigation = controller.navigationController {
                    navigation.interactivePopGestureRecognizer?.delegate = PopGestureDelegate.shared
                    navigation.interactivePopGestureRecognizer?.isEnabled = true
                    return
                }
                responder = current.next
            }
        }
    }
}

/// Allows the swipe only when there is a page to go back to; beginning it on
/// a root page would wedge the navigation controller.
@MainActor
private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation = gestureRecognizer.view?.next as? UINavigationController else { return false }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}
