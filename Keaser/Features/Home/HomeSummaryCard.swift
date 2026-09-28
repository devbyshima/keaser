import Charts
import KeaserKit
import SwiftUI
import UIKit

/// The card at the top of Home: what was spent in the chosen period and a
/// bar chart of how it was spread over that period.
struct HomeSummaryCard: View {
    let caption: String
    let total: Decimal
    let currencyCode: String
    let period: Period
    let calendar: Calendar
    let buckets: [SpendingChart.Bucket]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the total and the chart are in the card, so the chart's
    /// callout can keep clear of the total.
    @State private var totalFrame = CGRect.zero
    @State private var chartFrame = CGRect.zero

    private nonisolated static let space = "HomeSummaryCard"

    /// The total's frame in the chart's coordinates, once both are laid out.
    private var totalInChart: SpendingChart.Area? {
        guard !chartFrame.isEmpty, !totalFrame.isEmpty else { return nil }
        return SpendingChart.Area(
            x: totalFrame.minX - chartFrame.minX,
            y: totalFrame.minY - chartFrame.minY,
            width: totalFrame.width,
            height: totalFrame.height
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(caption)
                    .keaserFont(17, relativeTo: .body)
                    .foregroundStyle(Color.keaserSecondaryText)
                Text(MoneyFormat.string(total, currencyCode: currencyCode))
                    .keaserFont(40, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // The digits roll to a new total (switching accounts,
                    // adding an expense), or fade with Reduce Motion.
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: total.doubleValue))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { totalFrame = $0 }
                    .padding(.top, 8.5)
            }
            .accessibilityElement(children: .combine)
            HomeSpendingChart(
                buckets: buckets,
                period: period,
                calendar: calendar,
                currencyCode: currencyCode,
                keepClear: totalInChart
            )
            .frame(height: 200)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { chartFrame = $0 }
            .padding(.top, 40)
        }
        .coordinateSpace(.named(Self.space))
        .padding(.top, 22.5)
        .padding(.bottom, 27)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.keaserCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }
}

/// Ink bars with rounded tops over horizontal grid lines, values on the
/// trailing edge, as in the reference. VoiceOver reads each bar as its day,
/// month or hours and the amount spent.
///
/// Pressing and holding a bar raises a small glass callout out of it with
/// its period and amount; sliding the finger carries the callout from bar
/// to bar until the finger lifts and it sinks back. The callout never
/// covers `keepClear`, the total printed above the chart.
struct HomeSpendingChart: View {
    let buckets: [SpendingChart.Bucket]
    let period: Period
    let calendar: Calendar
    let currencyCode: String
    /// The total's frame in the chart's coordinates, or nil.
    var keepClear: SpendingChart.Area?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The width of the bar area, measured once the chart is laid out.
    @State private var plotWidth: CGFloat = 0
    /// The bar under a pressing finger, if any.
    @State private var selectedIndex: Int?
    /// The last bar that had the callout, so it sinks back into that bar
    /// after the finger lifts.
    @State private var lastCalloutIndex: Int?
    /// The callout's size when it last showed (at first, a typical one), for
    /// how far it rises as it appears; its placement uses the size it has.
    @State private var calloutSize = CGSize(width: 86, height: 46)

    /// The chart's text stops growing here: it has a fixed height and
    /// unwrapped axis labels, and VoiceOver reads the bar values.
    private static let largestTextSize = DynamicTypeSize.xxxLarge
    /// The share of its slot a bar is drawn across.
    private static let barWidthRatio = 0.7

    var body: some View {
        let narrow = usesNarrowLabels
        let scale = valueScale
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", key(bucket.index)),
                    y: .value("Spent", scale.position(of: bucket.total.doubleValue)),
                    width: .ratio(Self.barWidthRatio)
                )
                // The pressed bar keeps full ink; the rest step back.
                .foregroundStyle(Color.keaserInk.opacity(selectedIndex == nil || selectedIndex == bucket.index ? 1 : 0.35))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: barRadius, topTrailingRadius: barRadius, style: .continuous))
                .accessibilityLabel(SpendingChart.spokenName(of: bucket, period: period, calendar: calendar))
                .accessibilityValue(MoneyFormat.string(bucket.total, currencyCode: currencyCode))
            }
        }
        .chartXAxis {
            AxisMarks(values: buckets.filter(\.showsLabel).map { key($0.index) }) { value in
                AxisValueLabel(centered: true, verticalSpacing: 4) {
                    // On iOS 27 Charts asks for a label under every category,
                    // whatever `values` lists, so each label checks itself.
                    if let key = value.as(String.self), let bucket = bucket(for: key),
                       let label = SpendingChart.axisLabel(of: bucket, narrow: narrow) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(Color.keaserSecondaryText)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.tickPositions) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 2 / 3))
                    .foregroundStyle(Color.keaserInk.opacity(0.17))
                AxisValueLabel {
                    if let amount = value.as(Double.self).flatMap(scale.tick(at:)) {
                        Text(amount, format: .number.notation(.compactName))
                            .font(.caption2)
                            .foregroundStyle(Color.keaserSecondaryText)
                    }
                }
            }
        }
        // A fixed domain: an animated domain change (a new tallest bar)
        // makes Charts lay the axis labels out with invalid frames.
        .chartYScale(domain: SpendingChart.ValueScale.domain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(PressAndScrubGesture { location in
                        select(at: location, in: plot, proxy: proxy)
                    })
                    .onChange(of: proxy.plotSize.width, initial: true) { _, width in plotWidth = width }
                    .accessibilityHidden(true)
                    // Drawn here rather than as a chart annotation so its
                    // entrance, exit and glide are ours to animate.
                    .overlay(alignment: .topLeading) {
                        callout(proxy: proxy, plot: plot, chartWidth: geometry.size.width)
                    }
            }
        }
        .dynamicTypeSize(...Self.largestTextSize)
        .animation(.smooth(duration: 0.35), value: buckets)
        .sensoryFeedback(trigger: selectedIndex) { _, new in new == nil ? nil : .selection }
        .onChange(of: buckets.map(\.interval)) { _, _ in selectedIndex = nil; lastCalloutIndex = nil }
        .onChange(of: selectedIndex) { _, index in
            if let index { lastCalloutIndex = index }
        }
        #if DEBUG
        .task {
            // `-KeaserChartSelection last` (or a bar index) shows the callout
            // without a long press, for screenshots. It waits for Home to
            // apply `-KeaserPeriod`, which would otherwise clear it.
            try? await Task.sleep(for: .milliseconds(800))
            switch DebugLaunch.string("KeaserChartSelection") {
            case "last": selectedIndex = buckets.last?.index
            case let value?: selectedIndex = Int(value)
            case nil: break
            }
        }
        #endif
    }

    /// The pressed bar's callout, sitting on top of the bar and kept inside
    /// the chart, or beside it where it would cover the total
    /// (`SpendingChart.calloutPlacement`). It rises out of the bar's top as
    /// it appears and sinks back into it as it goes.
    ///
    /// The placement lives on a container that stays put while the callout
    /// inside it comes and goes, so the exit plays where the callout was and
    /// the entrance scales from the callout's own bottom edge.
    private func callout(proxy: ChartProxy, plot: CGRect, chartWidth: CGFloat) -> some View {
        let anchored = (selectedIndex ?? lastCalloutIndex).flatMap { index in buckets.first { $0.index == index } }
        let barCenter = anchored.flatMap { proxy.position(forX: key($0.index)) }.map { plot.minX + $0 } ?? plot.midX
        let barTop = anchored.flatMap { proxy.position(forY: valueScale.position(of: $0.total.doubleValue)) }.map { plot.minY + $0 } ?? plot.maxY
        let barWidth = buckets.isEmpty ? 0 : plot.width / CGFloat(buckets.count) * Self.barWidthRatio
        let keepClear = keepClear
        let placement: @Sendable (_ width: CGFloat, _ height: CGFloat) -> SpendingChart.CalloutPlacement = { width, height in
            SpendingChart.calloutPlacement(
                barCenter: barCenter,
                barWidth: barWidth,
                barTop: barTop,
                calloutWidth: width,
                calloutHeight: height,
                chartWidth: chartWidth,
                plotTop: plot.minY,
                keepClear: keepClear
            )
        }
        let rise = SpendingChart.calloutRise(barTop: barTop, calloutBottom: placement(calloutSize.width, calloutSize.height).bottom)
        return ZStack(alignment: .bottomLeading) {
            if let selected = selectedBucket {
                ChartCallout(
                    title: SpendingChart.calloutTitle(of: selected, period: period, calendar: calendar),
                    amount: MoneyFormat.string(selected.total, currencyCode: currencyCode),
                    rollsDigits: !reduceMotion
                )
                .onGeometryChange(for: CGSize.self) { $0.size } action: { calloutSize = $0 }
                // One callout that glides between bars; with Reduce Motion, a
                // new one per bar, so it only cross-fades in place.
                .id(reduceMotion ? selected.index : -1)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.asymmetric(
                    insertion: AnyTransition(CalloutEmergence(rise: rise)).animation(.spring(duration: 0.42, bounce: 0.3)),
                    removal: AnyTransition(CalloutEmergence(rise: rise)).animation(.smooth(duration: 0.24))
                ))
            }
        }
        .alignmentGuide(.leading) { size in -placement(size.width, size.height).leading }
        .alignmentGuide(.top) { size in size.height - placement(size.width, size.height).bottom }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: barCenter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedBucket: SpendingChart.Bucket? {
        selectedIndex.flatMap { index in buckets.first { $0.index == index } }
    }

    /// Picks the bar under `location`, clamped to the plot so a finger that
    /// drifts past either end keeps the end bar; nil clears the selection.
    private func select(at location: CGPoint?, in plot: CGRect, proxy: ChartProxy) {
        guard let location, plot.width > 0 else {
            withAnimation(.easeOut(duration: 0.2)) { selectedIndex = nil }
            return
        }
        let x = min(max(location.x - plot.minX, 0), plot.width - 1)
        guard let key = proxy.value(atX: x, as: String.self), let bucket = bucket(for: key),
              bucket.index != selectedIndex
        else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.28)) {
            selectedIndex = bucket.index
        }
    }

    /// Charts treats strings as categories, which keeps every bar in its own
    /// slot even when labels repeat.
    private func key(_ index: Int) -> String { "b\(index)" }

    private func bucket(for key: String) -> SpendingChart.Bucket? {
        Int(key.dropFirst()).flatMap { index in buckets.first { $0.index == index } }
    }

    /// Twelve months fit as "Jan Feb Mar" at the default text size but
    /// collide at larger ones, so they drop to "J F M" when the measured
    /// labels would touch.
    private var usesNarrowLabels: Bool {
        let size = min(dynamicTypeSize, Self.largestTextSize)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits)
        return !SpendingChart.labelsFit(buckets, plotWidth: plotWidth) { label in
            (label as NSString).size(withAttributes: [.font: font]).width
        }
    }

    /// Narrow bars (a month of days) get smaller corners so they stay bars.
    private var barRadius: CGFloat {
        switch buckets.count {
        case ...7: 8
        case ...12: 5
        default: 2.5
        }
    }

    private var valueScale: SpendingChart.ValueScale {
        SpendingChart.ValueScale(highest: buckets.map(\.total.doubleValue).max() ?? 0)
    }
}

/// The small glass tag a long press raises over a bar: the period in grey
/// over the amount, on Liquid Glass tinted with a breath of ink.
private struct ChartCallout: View {
    let title: String
    let amount: String
    /// Digits roll to the next bar's amount while scrubbing, unless Reduce
    /// Motion is on.
    let rollsDigits: Bool

    private static let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .keaserFont(11, relativeTo: .caption2)
                .foregroundStyle(Color.keaserSecondaryText)
            Text(amount)
                .keaserFont(15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(Color.keaserPrimaryText)
                .contentTransition(rollsDigits ? .numericText() : .opacity)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .keaserGlass(in: Self.shape, tint: Color.keaserInk.opacity(0.1))
    }
}

/// The callout growing out of its bar: from half size, anchored at its
/// bottom edge and `rise` points lower (the bar's top), up to its place.
private struct CalloutEmergence: Transition {
    let rise: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.5, anchor: .bottom)
            .offset(y: phase.isIdentity ? 0 : rise)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// A long press that keeps reporting where the finger is as it slides, and
/// nil once it lifts or is cancelled. UIKit's recogniser only takes over
/// after the press, so a swipe that starts on the chart still scrolls Home.
private struct PressAndScrubGesture: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onChange(context.converter.localLocation)
        default: onChange(nil)
        }
    }
}
