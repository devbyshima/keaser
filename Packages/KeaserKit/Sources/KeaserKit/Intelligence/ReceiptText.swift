import Foundation

/// Turns the pieces of text found on a receipt photo back into the receipt's
/// printed lines. Text recognition reads a receipt's label and amount
/// ("TOTAL" and "$12.50") as separate pieces, often far apart; the parser
/// needs them on one line, top to bottom.
public enum ReceiptText {
    /// One piece of recognized text and its corners, in image points with
    /// the origin at the bottom left (Vision's convention, scaled by the
    /// image's size so a tilted line keeps its real slope).
    public struct Fragment: Sendable {
        public var text: String
        public var topLeft: CGPoint
        public var topRight: CGPoint
        public var bottomRight: CGPoint
        public var bottomLeft: CGPoint

        public init(text: String, topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
            self.text = text
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomRight = bottomRight
            self.bottomLeft = bottomLeft
        }

        /// An upright box, for tests and simple sources.
        public init(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            self.init(
                text: text,
                topLeft: CGPoint(x: x, y: y + height),
                topRight: CGPoint(x: x + width, y: y + height),
                bottomRight: CGPoint(x: x + width, y: y),
                bottomLeft: CGPoint(x: x, y: y)
            )
        }

        var center: CGPoint {
            CGPoint(
                x: (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4,
                y: (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
            )
        }

        var height: CGFloat {
            max(((topLeft.y - bottomLeft.y) + (topRight.y - bottomRight.y)) / 2, 0)
        }

        var width: CGFloat { topRight.x - topLeft.x }

        var slope: CGFloat? {
            guard width > 0 else { return nil }
            return (topRight.y - topLeft.y) / width
        }
    }

    /// Steeper than this is not a receipt photographed at a slight angle,
    /// so the slope is ignored.
    static let maximumSlope: CGFloat = 0.3

    /// The receipt's lines, top to bottom, each made of the fragments that
    /// sit side by side, left to right. A photo taken at a slight angle
    /// still keeps a label and its amount together: the page's slope is
    /// taken out first.
    public static func lines(from fragments: [Fragment]) -> [String] {
        let pieces = fragments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pieces.isEmpty else { return [] }
        let slope = pageSlope(pieces)

        struct Placed {
            let text: String
            let x: CGFloat
            let y: CGFloat
            let height: CGFloat
        }
        let placed = pieces.map { piece in
            let center = piece.center
            return Placed(text: piece.text, x: center.x, y: center.y - slope * center.x, height: piece.height)
        }
        .sorted { $0.y > $1.y }

        var rows: [[Placed]] = []
        for piece in placed {
            if let first = rows.last?.first,
               abs(first.y - piece.y) <= max(first.height, piece.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.compactMap { row in
            let line = row.sorted { $0.x < $1.x }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            return line.isEmpty ? nil : line
        }
    }

    /// The median slope of the wider fragments, which follow the printed
    /// lines; zero when there are none or the page is turned too far.
    static func pageSlope(_ fragments: [Fragment]) -> CGFloat {
        let slopes = fragments
            .filter { $0.width > $0.height * 2 }
            .compactMap(\.slope)
            .sorted()
        guard !slopes.isEmpty else { return 0 }
        let median = slopes[slopes.count / 2]
        return abs(median) <= maximumSlope ? median : 0
    }
}
