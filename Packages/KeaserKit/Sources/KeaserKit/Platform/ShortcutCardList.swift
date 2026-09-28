import Foundation

/// The list a detail of the Add Expense confirmation card opens into when it
/// is tapped (iOS 26 and later): the options as rows inside the card, names
/// only, the chosen one checked, then More when they do not all fit and Go
/// Back when Settings > Shortcut has it on.
///
/// The system's card does not scroll and should stay under 340 points
/// (WWDC25, "Design interactive snippets"), so the list never takes more
/// lines under the detail's own row than fit at the person's text size
/// (`lines(forLineHeight:)`: `maxLines` at the default size, fewer at larger
/// ones). Up to that many options run down one column; up to twice as many
/// go in two columns when every name is short; longer lists are split into
/// pages that More steps through.
public struct ShortcutCardList: Hashable, Sendable {
    public struct Option: Hashable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let isCurrent: Bool

        public init(id: UUID, name: String, isCurrent: Bool) {
            self.id = id
            self.name = name
            self.isCurrent = isCurrent
        }
    }

    /// Lines the list may take under the detail's row, More and Go Back
    /// included, at the default text size and smaller. With the row above,
    /// the card stays under 340 points.
    public static let maxLines = 7
    /// The fewest lines a list is given, at the largest text sizes: one
    /// option, More and Go Back.
    public static let minLines = 3

    /// The tallest the card may be (WWDC25, "Design interactive snippets").
    public static let cardHeightLimit = 340.0
    /// What each line adds to its text: 8.75 points above and below.
    public static let linePadding = 17.5
    /// What the card takes besides its lines and the detail's row: 19
    /// points above the row, 14 under it, the hairline, and what is left of
    /// the lines' padding at the top (14 - 8.75) and bottom (12 - 8.75).
    public static let cardChrome = 19 + 14 + 1.0 / 3 + (14 - 8.75) + (12 - 8.75)

    /// How many lines fit under the detail's row when a line of the card's
    /// text (callout) is `lineHeight` points tall: 21 at the default text
    /// size, 28 at the largest standard one, over 60 at the largest
    /// accessibility size. Never more than `maxLines`, never fewer than
    /// `minLines`.
    public static func lines(forLineHeight lineHeight: Double) -> Int {
        let room = cardHeightLimit - cardChrome - lineHeight
        let fitting = Int((room / (lineHeight + linePadding)).rounded(.down))
        return min(maxLines, max(minLines, fitting))
    }
    /// A longer name keeps the list in one column, so none is squeezed.
    public static let twoColumnNameLimit = 16

    public let field: ShortcutFlow.Field
    /// One, or two for a long list of short names.
    public let columnCount: Int
    /// This page's options in reading order: down the first column, then
    /// down the second.
    public let options: [Option]
    /// Zero-based.
    public let page: Int
    public let pageCount: Int
    /// Whether the list ends with Go Back, which closes it unchanged.
    public let offersGoBack: Bool
    /// The lines it was fitted to (`lines(forLineHeight:)`).
    public let lineBudget: Int

    /// `page` nil opens the list on the page with the current option; any
    /// other page wraps around, so More after the last page shows the first.
    /// `lines` is how many lines it may take, More and Go Back included
    /// (at least `minLines`).
    public init(
        field: ShortcutFlow.Field,
        options all: [ShortcutFlow.Label],
        current: UUID?,
        offersGoBack: Bool,
        page: Int? = nil,
        lines budget: Int = maxLines
    ) {
        self.field = field
        self.offersGoBack = offersGoBack
        lineBudget = max(Self.minLines, budget)
        let lines = lineBudget - (offersGoBack ? 1 : 0)
        let short = all.allSatisfy { $0.name.count <= Self.twoColumnNameLimit }
        let perPage: Int
        if all.count <= lines {
            columnCount = 1
            perPage = max(all.count, 1)
        } else if short && all.count <= 2 * lines {
            columnCount = 2
            perPage = all.count
        } else {
            // One line goes to More.
            columnCount = short ? 2 : 1
            perPage = (lines - 1) * columnCount
        }
        pageCount = max(1, (all.count + perPage - 1) / perPage)
        let start = page ?? all.firstIndex { $0.id == current }.map { $0 / perPage } ?? 0
        self.page = (start % pageCount + pageCount) % pageCount
        options = all.dropFirst(self.page * perPage).prefix(perPage).map {
            Option(id: $0.id, name: $0.name, isCurrent: $0.id == current)
        }
    }

    /// The list for `field` of the flow's current account.
    public init(flow: ShortcutFlow, field: ShortcutFlow.Field, page: Int? = nil, lines: Int = maxLines) {
        self = Source(flow: flow, field: field, page: page).list(lines: lines)
    }

    /// A detail's options before they are fitted to the card: the card
    /// makes the list once it knows the text size, and so how many lines
    /// fit.
    public struct Source: Hashable, Sendable {
        public var field: ShortcutFlow.Field
        public var options: [ShortcutFlow.Label]
        public var current: UUID?
        public var offersGoBack: Bool
        /// Nil for the page with the current option.
        public var page: Int?

        public init(field: ShortcutFlow.Field, options: [ShortcutFlow.Label], current: UUID?, offersGoBack: Bool, page: Int? = nil) {
            self.field = field
            self.options = options
            self.current = current
            self.offersGoBack = offersGoBack
            self.page = page
        }

        /// The options of `field` in the flow's current account.
        public init(flow: ShortcutFlow, field: ShortcutFlow.Field, page: Int? = nil) {
            let choice = flow.options(for: field)
            self.init(field: field, options: choice.options, current: choice.current, offersGoBack: flow.goBackEnabled, page: page)
        }

        public func list(lines: Int = ShortcutCardList.maxLines) -> ShortcutCardList {
            ShortcutCardList(field: field, options: options, current: current, offersGoBack: offersGoBack, page: page, lines: lines)
        }
    }

    /// Whether the list ends with More, which shows the next page.
    public var offersMore: Bool { pageCount > 1 }

    /// The options column by column; the first column is the longer one.
    public var columns: [[Option]] {
        guard columnCount == 2 else { return [options] }
        let first = (options.count + 1) / 2
        return [Array(options.prefix(first)), Array(options.dropFirst(first))]
    }

    /// Lines the list takes: the option rows, More and Go Back.
    public var lineCount: Int {
        let rows = columnCount == 2 ? (options.count + 1) / 2 : options.count
        return max(rows, options.isEmpty ? 1 : 0) + (offersMore ? 1 : 0) + (offersGoBack ? 1 : 0)
    }

    /// "1 of 3", beside More.
    public var pageText: String { "\(page + 1) of \(pageCount)" }

    /// Said in place of the options when there are none (an account can
    /// have no categories or payment methods).
    public var emptyText: String? {
        guard options.isEmpty else { return nil }
        switch field {
        case .account: return "No accounts."
        case .category: return "No categories in this account."
        case .paymentMethod: return "No payment methods in this account."
        }
    }
}
