import Charts
import KeaserKit
import SwiftUI
import UIKit

/// The charcoal card at the top of Home: what was spent in the chosen period
/// and a bar chart of how it was spread over that period.
struct HomeSummaryCard: View {
    let caption: String
    let total: Decimal
    let currencyCode: String
    let period: Period
    let calendar: Calendar
    let buckets: [SpendingChart.Bucket]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .padding(.top, 8.5)
            }
            .accessibilityElement(children: .combine)
            HomeSpendingChart(buckets: buckets, period: period, calendar: calendar, currencyCode: currencyCode)
                .frame(height: 200)
                .padding(.top, 40)
        }
        .padding(.top, 22.5)
        .padding(.bottom, 27)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.keaserCard, in: RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous))
    }
}

/// White bars with rounded tops over horizontal grid lines, values on the
/// trailing edge, as in the reference. VoiceOver reads each bar as its day,
/// month or hours and the amount spent.
///
/// Pressing and holding a bar shows a callout with its period and amount;
/// sliding the finger moves it from bar to bar until the finger lifts.
struct HomeSpendingChart: View {
    let buckets: [SpendingChart.Bucket]
    let period: Period
    let calendar: Calendar
    let currencyCode: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width of the bar area, measured once the chart is laid out.
    @State private var plotWidth: CGFloat = 0
    /// The bar under a pressing finger, if any.
    @State private var selectedIndex: Int?

    /// The chart's text stops growing here: it has a fixed height and
    /// unwrapped axis labels, and VoiceOver reads the bar values.
    private static let largestTextSize = DynamicTypeSize.xxxLarge

    var body: some View {
        let narrow = usesNarrowLabels
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", key(bucket.index)),
                    y: .value("Spent", bucket.total.doubleValue),
                    width: .ratio(0.7)
                )
                // The pressed bar stays white; the rest step back.
                .foregroundStyle(Color.white.opacity(selectedIndex == nil || selectedIndex == bucket.index ? 1 : 0.35))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: barRadius, topTrailingRadius: barRadius, style: .continuous))
                .accessibilityLabel(SpendingChart.spokenName(of: bucket, period: period, calendar: calendar))
                .accessibilityValue(MoneyFormat.string(bucket.total, currencyCode: currencyCode))
            }
            if let selected = selectedBucket {
                // An invisible rule over the bar carries the callout above
                // the plot, where the reference draws it.
                RuleMark(x: .value("Period", key(selected.index)))
                    .foregroundStyle(Color.clear)
                    .annotation(
                        position: .top,
                        spacing: 12,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ChartCallout(
                            title: SpendingChart.calloutTitle(of: selected, period: period, calendar: calendar),
                            amount: MoneyFormat.string(selected.total, currencyCode: currencyCode)
                        )
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis {
            AxisMarks(values: buckets.filter(\.showsLabel).map { key($0.index) }) { value in
                AxisValueLabel(centered: true, verticalSpacing: 4) {
                    if let key = value.as(String.self), let bucket = bucket(for: key) {
                        Text(narrow ? bucket.narrowLabel : bucket.label)
                            .font(.caption2)
                            .foregroundStyle(Color.keaserSecondaryText)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 2 / 3))
                    .foregroundStyle(Color.white.opacity(0.17))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .number.notation(.compactName))
                            .font(.caption2)
                            .foregroundStyle(Color.keaserSecondaryText)
                    }
                }
            }
        }
        .chartYScale(domain: 0...(ticks.last ?? 20))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(PressAndScrubGesture { location in
                        select(at: location, proxy: proxy, geometry: geometry)
                    })
                    .onChange(of: proxy.plotSize.width, initial: true) { _, width in plotWidth = width }
                    .accessibilityHidden(true)
            }
        }
        .dynamicTypeSize(...Self.largestTextSize)
        .animation(.smooth(duration: 0.35), value: buckets)
        .sensoryFeedback(trigger: selectedIndex) { _, new in new == nil ? nil : .selection }
        .onChange(of: buckets.map(\.interval)) { _, _ in selectedIndex = nil }
        #if DEBUG
        .onAppear {
            // `-KeaserChartSelection last` (or a bar index) shows the callout
            // without a long press, for screenshots.
            switch DebugLaunch.string("KeaserChartSelection") {
            case "last": selectedIndex = buckets.last?.index
            case let value?: selectedIndex = Int(value)
            case nil: break
            }
        }
        #endif
    }

    private var selectedBucket: SpendingChart.Bucket? {
        selectedIndex.flatMap { index in buckets.first { $0.index == index } }
    }

    /// Picks the bar under `location`, clamped to the plot so a finger that
    /// drifts past either end keeps the end bar; nil clears the selection.
    private func select(at location: CGPoint?, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let location, let anchor = proxy.plotFrame else {
            withAnimation(.easeOut(duration: 0.15)) { selectedIndex = nil }
            return
        }
        let plot = geometry[anchor]
        let x = min(max(location.x - plot.minX, 0), max(plot.width - 1, 0))
        guard let key = proxy.value(atX: x, as: String.self), let bucket = bucket(for: key),
              bucket.index != selectedIndex
        else { return }
        withAnimation(.snappy(duration: 0.2)) { selectedIndex = bucket.index }
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

    private var ticks: [Double] {
        SpendingChart.axisTicks(for: buckets.map(\.total.doubleValue).max() ?? 0)
    }
}

/// The card a long press shows over a bar: the period in grey, the amount
/// in white, on near-black with a hairline edge, as in the reference.
private struct ChartCallout: View {
    let title: String
    let amount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .keaserFont(15, relativeTo: .subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
            Text(amount)
                .keaserFont(20, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(Color.keaserPrimaryText)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.keaserCallout, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
        .transition(.opacity)
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
