import SwiftUI

/// The Summary tab. Empty until the summary is built (money tracking phase
/// 7): Home's empty state, centred as its No Account screen is.
struct SummaryView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "chart.bar.xaxis",
                title: "Summary",
                message: "Your income, spending and savings will show here.",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.keaserBackground.ignoresSafeArea())
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
