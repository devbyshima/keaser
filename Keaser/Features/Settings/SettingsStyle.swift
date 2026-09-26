import SwiftUI
import UIKit

// Shared look for every page inside the Settings sheet: rounded charcoal
// cards on the sheet background, 68pt rows with a symbol, round glass header
// buttons.

extension Color {
    /// Card fill on settings pages. A light veil rather than a solid colour,
    /// so it reads the same on the iOS 18 charcoal sheet and on iOS 26 glass.
    static let settingsCard = Color.white.opacity(0.055)
    /// The barely visible tile behind row symbols and the account monogram.
    static let settingsTile = Color.white.opacity(0.014)
    /// Symbol tiles and text fields that sit on the sheet itself.
    static let settingsField = Color.white.opacity(0.03)
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
    func settingsListStyle(sectionSpacing: CGFloat = 35, topMargin: CGFloat = 39) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, KeaserMetrics.screenPadding, for: .scrollContent)
            .contentMargins(.top, topMargin, for: .scrollContent)
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
            .listRowSeparatorTint(Color.keaserSeparator)
    }

    /// Ends a row's separator 16pt short of the card's edge, as iOS 26 does
    /// (iOS 18 runs it to the edge). Apply to the row's full-width content;
    /// `overChevron` carries it past the chevron a `NavigationLink` adds.
    func cardSeparatorTrailing(overChevron: Bool = false) -> some View {
        alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + (overChevron ? 20 : 0) }
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
struct SettingsSymbol: View {
    let symbol: String
    var size: CGFloat = 38
    var pointSize: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: pointSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.settingsTile, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Symbol, title and an optional trailing value. Wrap it in a
/// `NavigationLink` for the chevron, or give it an `accessory` symbol.
struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var accessory: String? = nil
    /// Whether a `NavigationLink` chevron follows the row.
    var hasDisclosure = true

    var body: some View {
        HStack(spacing: 13) {
            SettingsSymbol(symbol: symbol)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(1)
            }
            if let accessory {
                Image(systemName: accessory)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
            }
        }
        .frame(minHeight: 68)
        .cardSeparatorTrailing(overChevron: hasDisclosure)
        .contentShape(Rectangle())
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
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.keaserSecondaryText)
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
        // A plain 13pt font keeps the tight leading of the reference; the
        // footnote text style adds several points between lines.
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.keaserSecondaryText)
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Header buttons

/// A round glass icon button for sheet and page headers (close, back, add).
/// iOS 26 toolbars put their buttons on glass themselves; earlier systems
/// get the look from `keaserCircleButton()`.
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
            // Left to the toolbar, which draws its own glass.
            Button(action: action) {
                Image(systemName: symbol)
            }
            .accessibilityLabel(label)
        } else {
            Button(action: action) {
                Image(systemName: symbol)
                    .keaserCircleButton()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(label)
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

/// iOS 26's own back button is already a round glass chevron. Earlier
/// systems get the same look from a custom button; hiding the system one
/// switches off swipe-to-go-back, so that is switched back on too.
private struct SettingsBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbarRole(.editor)
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
