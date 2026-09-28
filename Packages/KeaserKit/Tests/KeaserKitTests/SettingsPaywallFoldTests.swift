import Foundation
import Testing
@testable import KeaserKit

/// Where the paywall's plans panel meets the feature list. The rows are the
/// paywall's own, measured on an iPhone 16 Pro (iOS 27) in the sheet's
/// points: a 20.33pt title, 2pt, then a detail on 18pt lines, 21pt apart.
struct SettingsPaywallFoldTests {
    private typealias Row = PaywallFold.Row

    private let rows = [
        Row(title: 286.0...306.33, detail: 308.33...326.33), // Widgets
        Row(title: 347.33...367.67, detail: 369.67...407.67), // More Filters, two lines
        Row(title: 428.67...449.0, detail: 451.0...469.0), // Multiple Accounts
        Row(title: 490.0...510.33, detail: 512.33...550.33), // Long-term Insights, two lines
        Row(title: 571.33...591.67, detail: 593.67...611.67), // Support indie development
    ]

    @Test func anEdgeJustUnderAHeadingStaysAsInTheReference() {
        // Over Settings the edge falls just under Multiple Accounts.
        #expect(PaywallFold.shift(panelTop: 452, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: 449, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: 453, rows: rows, limit: 16) == 0)
    }

    @Test func anEdgeBetweenFeaturesStays() {
        #expect(PaywallFold.shift(panelTop: 480, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: 469, rows: rows, limit: 16) == 0)
    }

    @Test func anEdgeThroughADetailMovesToTheNearestGap() {
        // The single sheet is taller: the edge lands in "Remove the limit of
        // one free account." and the content moves up 7pt, so the edge
        // meets the list just under that line.
        #expect(PaywallFold.shift(panelTop: 462, rows: rows, limit: 16) == -7)
        // Nearer the top of the line, the content moves down instead and the
        // edge meets the list under the heading.
        #expect(PaywallFold.shift(panelTop: 456, rows: rows, limit: 16) == 3)
    }

    @Test func anEdgeThroughAHeadingMovesClearOfIt() {
        let move = PaywallFold.shift(panelTop: 440, rows: rows, limit: 16)
        #expect(move == -9)
        #expect(PaywallFold.gaps(between: rows).contains { $0.contains(440 - move) })
    }

    @Test func anEdgeInsideATwoLineDetailLeavesBothLinesWhole() {
        // Between "Filter by categories and" and "payment methods": 17.33pt
        // down to meet the list under More Filters, 18.67pt up to meet it
        // under the second line.
        #expect(PaywallFold.shift(panelTop: 389, rows: rows, limit: 16) == 0)
        let move = PaywallFold.shift(panelTop: 389, rows: rows, limit: 20)
        #expect(abs(move - 17.33) < 0.001)
        let edge = 389 - move
        for row in rows {
            #expect(!(row.title.lowerBound + PaywallFold.aboveGlyphs < edge && edge < row.title.upperBound))
            #expect(!(row.detail.lowerBound + PaywallFold.aboveGlyphs < edge && edge < row.detail.upperBound))
        }
    }

    @Test func aMoveLargerThanTheLimitIsNotMade() {
        #expect(PaywallFold.shift(panelTop: 462, rows: rows, limit: 5) == 0)
        #expect(PaywallFold.shift(panelTop: 462, rows: rows, limit: 7) == -7)
    }

    @Test func anEdgeOutsideTheListStays() {
        #expect(PaywallFold.shift(panelTop: 250, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: 640, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: 611.67, rows: rows, limit: 16) == 0)
    }

    @Test func nothingMovesWithoutMeasurements() {
        #expect(PaywallFold.shift(panelTop: 462, rows: [], limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: .nan, rows: rows, limit: 16) == 0)
        #expect(PaywallFold.shift(panelTop: .infinity, rows: rows, limit: 16) == 0)
    }

    @Test func rowsCanArriveInAnyOrder() {
        #expect(PaywallFold.shift(panelTop: 462, rows: rows.reversed(), limit: 16) == -7)
        #expect(PaywallFold.gaps(between: rows.shuffled()) == PaywallFold.gaps(between: rows))
    }

    @Test func gapsNeverCoverALinesLetters() {
        let gaps = PaywallFold.gaps(between: rows)
        // Above the list, under each title, between features, past the end.
        #expect(gaps.count == 1 + rows.count + (rows.count - 1) + 1)
        for gap in gaps {
            for line in rows.flatMap({ [$0.title, $0.detail] }) {
                let letters = (line.lowerBound + PaywallFold.aboveGlyphs)...line.upperBound
                // Touching at an end is fine; running into the letters is not.
                let overlap = min(gap.upperBound, letters.upperBound) - max(gap.lowerBound, letters.lowerBound)
                #expect(overlap <= 0)
            }
        }
    }
}
