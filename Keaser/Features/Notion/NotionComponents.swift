import SwiftUI

// Building blocks for the Notion sheets, drawn to match the app's other
// sheets: a round glass button either side of a centred title, charcoal
// cards with 26pt corners, 68pt rows with an icon column, hairlines inset to
// the text.

/// The neutral stand-in for a Notion mark: a rounded tile with a plain "N".
struct NotionMark: View {
    var size: CGFloat = 36

    var body: some View {
        Text("N")
            .font(.system(size: size * 0.52, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityLabel("Notion")
    }
}

/// Header of a Notion sheet page: round glass buttons and a centred title.
struct NotionSheetHeader<Trailing: View>: View {
    enum Leading {
        case close, back, none
    }

    let title: String
    var leading: Leading = .none
    var action: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            switch leading {
            case .close: headerButton("xmark", label: "Close")
            case .back: headerButton("chevron.left", label: "Back")
            case .none: Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 8)
            trailing.frame(minWidth: 44, minHeight: 44)
        }
        .overlay {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 60)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func headerButton(_ symbol: String, label: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .keaserCircleButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension NotionSheetHeader where Trailing == EmptyView {
    init(title: String, leading: Leading = .none, action: @escaping () -> Void = {}) {
        self.init(title: title, leading: leading, action: action) { EmptyView() }
    }
}

/// A charcoal card holding rows separated by inset hairlines.
struct NotionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.keaserCardRaised, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }
}

/// Hairline between rows, starting where the row text starts.
struct NotionRowDivider: View {
    var inset: CGFloat = 64

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 0.5)
            .padding(.leading, inset)
            .padding(.trailing, 16)
    }
}

/// A card row: icon column, title and optional subtitle, trailing content.
struct NotionRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

extension NotionRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

/// A white SF Symbol in the row icon column.
struct NotionRowSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
    }
}

/// A database or page icon: its emoji, or a symbol when it has none.
struct NotionEmojiTile: View {
    let emoji: String?
    var fallback: String = "tablecells"
    var size: CGFloat = 36

    var body: some View {
        Group {
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
    }
}

/// The disclosure chevron at the end of a tappable row.
struct NotionChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.keaserTertiaryText)
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
/// it works.
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
            // Solid behind the button (the disabled capsule is translucent),
            // with content fading out just above it.
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
}
