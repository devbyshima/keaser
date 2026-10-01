import KeaserKit
import SwiftUI

/// The bundled legal texts in `Keaser/Resources/Legal/`.
enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms of Service"
        }
    }

    /// Parsed blocks, or nil if the file is missing from the bundle. What
    /// the privacy policy says about iCloud sync is kept only in builds that
    /// sync (`MarkdownConditions`).
    @MainActor
    var blocks: [MarkdownBlock]? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return MarkdownBlocks.parse(MarkdownConditions.resolve(text, flags: CloudSync.shared.documentFlags))
    }
}

/// A legal document pushed inside Settings, on the canvas of the other
/// settings pages.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        LegalDocumentBody(document: document)
            .background(Color.settingsCanvas.ignoresSafeArea())
            .settingsPage(document.title)
    }
}

/// A legal document in its own sheet, for the paywall's links. It draws no
/// canvas of its own, so the sheet's background shows.
struct LegalDocumentSheet: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalDocumentBody(document: document)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HeaderIconButton("xmark", label: "Close") { dismiss() }
                    }
                }
        }
        .keaserSheetChrome()
    }
}

private struct LegalDocumentBody: View {
    let document: LegalDocument

    var body: some View {
        if let blocks = document.blocks {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            MarkdownBlockView(block: block)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if DEBUG
                .onAppear {
                    // `-KeaserSettingsScroll <word>` starts at the first
                    // heading containing it, to screenshot a later section
                    // (once a launch, not on every return to the page).
                    guard let word = DebugLaunch.string("KeaserSettingsScroll"),
                          let index = blocks.firstIndex(where: { block in
                              if case .heading(_, let text) = block { return text.localizedCaseInsensitiveContains(word) }
                              return false
                          })
                    else { return }
                    guard DebugLaunch.firstTime("legalScroll") else { return }
                    proxy.scrollTo(index, anchor: .top)
                }
                #endif
            }
            .keaserReadableScrollContent()
        } else {
            EmptyStateView(symbol: "doc.text", title: "Not Available", message: "This document could not be loaded.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .keaserFont(level == 1 ? 28 : 19, weight: level == 1 ? .bold : .semibold, relativeTo: level == 1 ? .title : .title3)
                .foregroundStyle(Color.keaserPrimaryText)
                .padding(.top, level == 1 ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            list(items) { _ in "\u{2022}" }
        case .numbered(let items):
            list(items) { "\($0 + 1)." }
        case .rule:
            Rectangle()
                .fill(Color.keaserSeparator)
                .frame(height: 1)
                .padding(.vertical, 6)
        }
    }

    private func list(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(marker(index))
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(minWidth: 14, alignment: .leading)
                    Text(inline(item))
                        .foregroundStyle(Color.keaserPrimaryText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
        }
    }

    /// Bold, italics and links inside a block.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
