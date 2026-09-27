import KeaserKit
import SwiftUI

// The pieces of a tutorial article (`TutorialDetailView`): free text sits on
// the sheet, aligned with the text inside the cards; steps, notes and
// illustrations sit on the same rounded cards as every other settings page.

/// Headline and intro at the top of the article.
struct TutorialHeader: View {
    let tutorial: Tutorial

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tutorial.headline)
                .keaserFont(28, weight: .bold, relativeTo: .title)
                .foregroundStyle(Color.keaserPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h1)
            TutorialParagraph(text: tutorial.intro)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A heading and its blocks.
struct TutorialSectionView: View {
    let section: TutorialSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { index, block in
                TutorialBlockView(block: block, firstStepNumber: section.firstStepNumber(ofBlockAt: index))
            }
        }
        .padding(.top, section.level == .section ? 36 : 26)
    }

    @ViewBuilder
    private var heading: some View {
        let isSection = section.level == .section
        Text(section.title)
            .keaserFont(isSection ? 22 : 19, weight: isSection ? .bold : .semibold, relativeTo: isSection ? .title2 : .title3)
            .foregroundStyle(Color.keaserPrimaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(isSection ? .h2 : .h3)
    }
}

private struct TutorialBlockView: View {
    let block: TutorialBlock
    /// The number of the block's first step, if it is a step list.
    let firstStepNumber: Int

    var body: some View {
        switch block {
        case .paragraph(let text):
            TutorialParagraph(text: text)
                .padding(.horizontal, 16)
        case .steps(let steps):
            TutorialSteps(steps: steps, firstNumber: firstStepNumber)
        case .note(let note):
            TutorialNoteCard(note: note)
        case .illustration(let illustration):
            TutorialIllustrationCard(illustration: illustration)
                .id(illustration.rawValue)
        }
    }
}

/// Body text, with the names of things to tap in bold.
private struct TutorialParagraph: View {
    let text: String

    var body: some View {
        Text(TutorialMarkdown.attributed(text))
            .font(.body)
            .foregroundStyle(Color.keaserPrimaryText.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Numbered steps on one card, a hairline between each.
private struct TutorialSteps: View {
    let steps: [String]
    let firstNumber: Int

    /// The number's circle grows with the text beside it.
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 28
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(Color.keaserSeparator)
                        .frame(height: 1 / displayScale)
                        .padding(.leading, 16 + badge + 14)
                        .padding(.trailing, 16)
                }
                row(number: firstNumber + index, text: step)
            }
        }
        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }

    private func row(number: Int, text: String) -> some View {
        let badge = badge
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .keaserFont(15, weight: .semibold, design: .rounded, relativeTo: .body)
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color.keaserInk.opacity(0.1)))
                // Centred on the first line of the step rather than sitting
                // on its baseline.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + badge * 0.2 }
            Text(TutorialMarkdown.attributed(text))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(Tutorials.plain(text))")
    }
}

/// A remark set apart on its own card: symbol, title and a few lines. At
/// accessibility sizes the symbol moves above the text, which then has the
/// card's full width.
private struct TutorialNoteCard: View {
    let note: TutorialNote

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 13))
        layout {
            SettingsSymbol(symbol: note.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .keaserFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(Color.keaserPrimaryText)
                Text(TutorialMarkdown.attributed(note.text))
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, isLarge ? 0 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An illustration on its card. Drawings are decorative (the copy says the
/// same in words), so VoiceOver skips them, and they step aside at the
/// largest text sizes, where the words need the room.
private struct TutorialIllustrationCard: View {
    let illustration: TutorialIllustration

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize < .accessibility3 {
            TutorialIllustrationView(illustration: illustration)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The way out to the Shortcuts app at the end of an article: a one-row
/// card like the link rows on Help & Feedback. At accessibility sizes the
/// symbol steps aside so the title keeps whole words.
struct TutorialShortcutsButton: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            openURL(Tutorials.shortcutsURL)
        } label: {
            HStack(spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "square.stack.3d.up.fill")
                        .keaserFont(19, weight: .medium, relativeTo: .body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                Text("Open Shortcuts")
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .padding(.vertical, 12)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .keaserFont(13, weight: .semibold, relativeTo: .footnote)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(TutorialCardButtonStyle())
        .accessibilityHint("Opens the Shortcuts app.")
    }
}

/// A button drawn as a one-row card, dimmed while pressed like a list row.
private struct TutorialCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous)
                    .fill(Color.settingsCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous)
                            .fill(Color.keaserInk.opacity(configuration.isPressed ? 0.08 : 0))
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }
}

private enum TutorialMarkdown {
    /// The copy's inline Markdown (bold names) as styled text.
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(Tutorials.plain(text))
    }
}
