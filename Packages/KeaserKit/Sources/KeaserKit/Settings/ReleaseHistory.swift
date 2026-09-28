import Foundation

/// One shipped version, for the What's New list and its detail page.
public struct Release: Identifiable, Hashable, Sendable {
    public struct Highlight: Hashable, Sendable {
        public let symbol: String
        public let title: String
        public let detail: String

        public init(symbol: String, title: String, detail: String) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    /// Marketing version without the "v": "1.0.0".
    public let version: String
    /// Release day as "yyyy-MM-dd", shown as is under the version.
    public let date: String
    public let summary: String
    public let highlights: [Highlight]

    public init(version: String, date: String, summary: String, highlights: [Highlight]) {
        self.version = version
        self.date = date
        self.summary = summary
        self.highlights = highlights
    }

    public var id: String { version }

    /// "v1.0.0".
    public var title: String { "v\(version)" }
}

public enum ReleaseHistory {
    /// Newest first. Add a release at the top when shipping an update.
    public static let releases: [Release] = [
        Release(
            version: "1.0.0",
            date: "2026-09-26",
            summary: "The first release of Keaser: a quick, private way to keep track of what you spend.",
            highlights: [
                .init(symbol: "plus.circle.fill", title: "Log in seconds",
                      detail: "Add an expense with a title, amount, category, payment method and date. Smart Suggestions fill in the rest from expenses you have logged before."),
                .init(symbol: "chart.bar.fill", title: "See where it goes",
                      detail: "Totals and a chart for today, this week, this month, this year or all time, with search and filters by category and payment method."),
                .init(symbol: "person.2.fill", title: "Separate accounts",
                      detail: "Keep personal, work or shared spending apart, each with its own categories and payment methods."),
                .init(symbol: "command", title: "Shortcuts and Apple Wallet",
                      detail: "Log expenses from Siri, the Action button or Control Center, and record Apple Pay purchases automatically with a Wallet automation."),
                .init(symbol: "plus.square.fill", title: "Widgets",
                      detail: "Your spending on the Home Screen, always in your currency and week settings."),
                .init(symbol: "bell.badge.fill", title: "Weekly summary",
                      detail: "An optional notification each week with what you spent."),
                .init(symbol: "lock.fill", title: "Private by design",
                      detail: "No sign-up, no analytics and no tracking. Your data stays on your iPhone."),
            ]
        ),
    ]
}
