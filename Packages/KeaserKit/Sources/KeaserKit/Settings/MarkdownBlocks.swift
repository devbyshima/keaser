import Foundation

/// A block of a small Markdown document (the bundled Privacy Policy and Terms
/// of Service). Inline markup (bold, links) is left in the text for the view
/// to render with `AttributedString(markdown:)`.
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case rule
}

/// Splits Markdown into blocks. Covers what the legal documents use:
/// `#` headings, paragraphs (consecutive lines joined), `-`/`*` bullets,
/// `1.` numbered items and `---` rules. Anything else is a paragraph.
public enum MarkdownBlocks {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)) }
            paragraph = []
            bullets = []
            numbered = []
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = heading(line) {
                flush()
                blocks.append(heading)
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else if let item = bulletItem(line) {
                if bullets.isEmpty { flush() }
                bullets.append(item)
            } else if let item = numberedItem(line) {
                if numbered.isEmpty { flush() }
                numbered.append(item)
            } else if !bullets.isEmpty || !numbered.isEmpty {
                // A wrapped line continues the current list item.
                if !bullets.isEmpty { bullets[bullets.count - 1] += " " + line }
                else { numbered[numbered.count - 1] += " " + line }
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
}

/// Keeps the parts of a bundled document that fit this build: lines
/// between `<!-- if <flag> -->` and `<!-- else -->` (or `<!-- end -->`) stay
/// only when `flag` is on, lines between `<!-- else -->` and `<!-- end -->`
/// only when it is off. The privacy policy words iCloud sync this way
/// (`icloud`), so what it says about sync shows only in builds that sync.
/// Any other comment line is dropped. Sections do not nest.
public enum MarkdownConditions {
    public static func resolve(_ source: String, flags: Set<String>) -> String {
        var kept: [String] = []
        var including = true
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else {
                if including { kept.append(line) }
                continue
            }
            let words = trimmed.dropFirst(4).dropLast(3).split(separator: " ").map(String.init)
            switch words.first {
            case "if": including = words.count > 1 && flags.contains(words[1])
            case "else": including.toggle()
            case "end": including = true
            default: break
            }
        }
        return kept.joined(separator: "\n")
    }
}
