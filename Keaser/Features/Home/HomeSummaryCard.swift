import Charts
import KeaserKit
import SwiftUI

/// The charcoal card at the top of Home: what was spent in the chosen period
/// and a bar chart of how it was spread over that period.
struct HomeSummaryCard: View {
    let caption: String
    let total: Decimal
    let currencyCode: String
    let period: Period
    let calendar: Calendar
    let buckets: [SpendingChart.Bucket]

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
                    .contentTransition(.numericText(value: total.doubleValue))
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
struct HomeSpendingChart: View {
    let buckets: [SpendingChart.Bucket]
    let period: Period
    let calendar: Calendar
    let currencyCode: String

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Period", key(bucket.index)),
                y: .value("Spent", bucket.total.doubleValue),
                width: .ratio(0.7)
            )
            .foregroundStyle(Color.white)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: barRadius, topTrailingRadius: barRadius, style: .continuous))
            .accessibilityLabel(SpendingChart.spokenName(of: bucket, period: period, calendar: calendar))
            .accessibilityValue(MoneyFormat.string(bucket.total, currencyCode: currencyCode))
        }
        .chartXAxis {
            AxisMarks(values: buckets.filter(\.showsLabel).map { key($0.index) }) { value in
                AxisValueLabel(centered: true, verticalSpacing: 4) {
                    if let key = value.as(String.self), let bucket = bucket(for: key) {
                        Text(bucket.label)
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
        // The chart has a fixed height and unwrapped axis labels, so its
        // text stops growing where labels would start to collide; bar values
        // are read by VoiceOver.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(.smooth(duration: 0.35), value: buckets)
    }

    /// Charts treats strings as categories, which keeps every bar in its own
    /// slot even when labels repeat.
    private func key(_ index: Int) -> String { "b\(index)" }

    private func bucket(for key: String) -> SpendingChart.Bucket? {
        Int(key.dropFirst()).flatMap { index in buckets.first { $0.index == index } }
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
