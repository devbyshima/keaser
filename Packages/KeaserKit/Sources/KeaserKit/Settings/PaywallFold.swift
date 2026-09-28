import Foundation

/// Where the paywall's plans panel meets the feature list scrolling under it.
///
/// In the reference, the panel's top edge falls just under the Multiple
/// Accounts heading, with that feature's line hidden under the panel. The
/// edge's place in the list depends on the sheet's height and the panel's
/// (a single sheet is taller than one over Settings; the purchased panel is
/// shorter, and one with a price problem taller), so at rest it can slice
/// through a line of text. `shift(panelTop:rows:limit:)` finds how far to
/// move the content so the edge falls between lines instead.
public enum PaywallFold {
    /// One feature's text, as line boxes in the content's coordinates
    /// (y growing downwards).
    public struct Row: Equatable, Sendable {
        /// The title's top and bottom.
        public var title: ClosedRange<Double>
        /// The line (or lines) under it.
        public var detail: ClosedRange<Double>

        public init(title: ClosedRange<Double>, detail: ClosedRange<Double>) {
            self.title = title
            self.detail = detail
        }
    }

    /// How far the edge may reach into the top of a line box: San
    /// Francisco's tallest letters start about 3pt below it at these sizes,
    /// while its descenders run to the bottom of the box, so the edge never
    /// covers any of that.
    public static let aboveGlyphs = 2.0

    /// The places the panel's top edge may rest without cutting a line: just
    /// under a title (as in the reference), between two features, or past
    /// the last one. Also above the first feature, where the list is not
    /// showing anyway.
    public static func gaps(between rows: [Row]) -> [ClosedRange<Double>] {
        let rows = rows.sorted { $0.title.lowerBound < $1.title.lowerBound }
        guard let first = rows.first, let last = rows.last else { return [] }
        var gaps = [-Double.infinity...(first.title.lowerBound + aboveGlyphs)]
        for (index, row) in rows.enumerated() {
            gaps.append(band(from: row.title.upperBound, to: row.detail.lowerBound))
            if index + 1 < rows.count {
                gaps.append(band(from: row.detail.upperBound, to: rows[index + 1].title.lowerBound))
            }
        }
        gaps.append(last.detail.upperBound...Double.infinity)
        return gaps
    }

    /// How far to move the content down (negative: up) so that an edge at
    /// `panelTop`, in the same coordinates as `rows` before any move, rests
    /// in one of `gaps(between:)`: 0 when it already does, otherwise the
    /// smallest move that gets it there, or 0 when that is more than
    /// `limit`.
    public static func shift(panelTop: Double, rows: [Row], limit: Double) -> Double {
        guard panelTop.isFinite, limit >= 0 else { return 0 }
        let gaps = gaps(between: rows)
        guard !gaps.isEmpty, !gaps.contains(where: { $0.contains(panelTop) }) else { return 0 }
        // Moving the content down by `s` puts the edge at `panelTop - s` in
        // the list; the nearest end of a gap is the smallest move.
        let moves = gaps.map { gap in panelTop - min(max(panelTop, gap.lowerBound), gap.upperBound) }
        guard let move = moves.min(by: { abs($0) < abs($1) }), abs(move) <= limit else { return 0 }
        return move
    }

    private static func band(from upper: Double, to lower: Double) -> ClosedRange<Double> {
        upper...max(upper, lower + aboveGlyphs)
    }
}
