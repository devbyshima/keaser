import SwiftUI

// Pieces only the Notion sheets use. Headers, cards, hairlines and pressed
// rows come from Keaser/Design/SheetChrome.swift.

extension View {
    /// Spaces a `KeaserSheetHeader` at the top of a Notion step.
    func notionHeaderPadding() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }
}

/// Holds the empty side of a `KeaserSheetHeader`. Its layout places
/// exactly three views, and an `EmptyView` side is not one, which drops the
/// title.
struct NotionHeaderSpacer: View {
    var body: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }
}

/// A card row: icon column, title and optional subtitle, trailing content.
/// The icon column grows with the text.
struct NotionRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// Draws the hairline above the row, from where the text starts. Every
    /// row of a card but the first.
    var separated = false
    /// The trailing view is a control (a menu) that names itself to
    /// VoiceOver. Otherwise the row reads as one element.
    var hasControl = false
    /// The trailing view is a value (a property name) rather than a
    /// chevron or mark. At accessibility sizes, where the title and value
    /// do not fit side by side, it moves under the title.
    var trailingIsValue = false
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            if separated {
                KeaserRowSeparator(leading: 16 + iconSize + 12)
            }
            content
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: hasControl ? .contain : .combine)
    }

    private var content: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: iconSize, height: iconSize)
            if trailingIsValue && typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    labels
                    trailing
                }
                Spacer(minLength: 0)
            } else {
                labels
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
        }
        .accessibilityHidden(hasControl)
    }
}

extension NotionRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, separated: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, subtitle: subtitle, separated: separated, icon: icon) { EmptyView() }
    }
}

/// A white SF Symbol in the row icon column. Decorative: the row's title
/// says what it is.
struct NotionRowSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .keaserFont(19, weight: .semibold, relativeTo: .title3)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

/// A database or page icon: its emoji, or a symbol when it has none.
struct NotionEmojiTile: View {
    let emoji: String?
    var fallback: String = "tablecells"

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 36

    var body: some View {
        Group {
            // Sized from the tile, which already follows Dynamic Type.
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.6))
            } else {
                Image(systemName: fallback)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The disclosure chevron at the end of a tappable row.
struct NotionChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .keaserFont(14, weight: .semibold)
            .foregroundStyle(Color.keaserTertiaryText)
            .accessibilityHidden(true)
    }
}

/// Grey title above a card ("Shared with Keaser"), lined up with the
/// card's row content like the section titles in Settings.
struct NotionSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Grey explanation under a card.
struct NotionFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 10)
    }
}

/// An error message in red with a warning symbol.
struct NotionErrorText: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(Color.keaserDestructive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .transition(.opacity)
    }
}

/// The white capsule pinned to the bottom of a step, with a spinner while
/// it works. Attach it with `notionBottomBar`.
struct NotionPrimaryButton: View {
    let title: String
    var isWorking = false
    var isEnabled = true
    /// An error shown just above the button, where it cannot scroll away.
    var error: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                NotionErrorText(message: error)
                    .padding(.horizontal, -16)
            }
            Button(action: action) {
                ZStack {
                    Text(title).opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView().tint(.black) }
                }
            }
            .buttonStyle(.keaserPrimary)
            .disabled(!isEnabled || isWorking)
        }
        .animation(.snappy, value: error)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            if #available(iOS 26.0, *) {
                // Over the glass sheet the bar stays clear; the scroll edge
                // effect of `notionBottomBar` softens what passes under it.
                EmptyView()
            } else {
                // Solid behind the button (the disabled capsule is
                // translucent), with content fading out just above it.
                Color.keaserCard
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Color.keaserCard.opacity(0), Color.keaserCard], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .offset(y: -24)
                    }
            }
        }
    }
}

extension View {
    /// The sheet page background before iOS 26; the system glass sheet shows
    /// through on iOS 26.
    @ViewBuilder
    func notionPageBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(Color.keaserCard.ignoresSafeArea())
        }
    }

    /// Pins `content` (a `NotionPrimaryButton`) below the page. On iOS 26 a
    /// safe area bar, so scrolling content gets the system's edge effect
    /// instead of an opaque slab over the glass; before that, an inset.
    @ViewBuilder
    func notionBottomBar<Bar: View>(@ViewBuilder _ content: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, content: content)
        } else {
            self.safeAreaInset(edge: .bottom, content: content)
        }
    }
}
