import Foundation
import Testing
@testable import KeaserKit

struct HomeSmartSuggesterTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func expense(_ title: String, _ amount: Decimal, daysAgo: Double) -> Expense {
        let date = base.addingTimeInterval(-daysAgo * 86_400)
        return Expense(title: title, amount: amount, date: date, createdAt: date)
    }

    private var history: [Expense] {
        [
            expense("Groceries", 80, daysAgo: 1),
            expense("Gas", 45, daysAgo: 2),
            expense("Groceries", 60, daysAgo: 5),
            expense("Big grocery run", 150, daysAgo: 3),
            expense("Gym membership", 40, daysAgo: 10),
            expense("Café Gris", 6, daysAgo: 4),
            expense("Outing", 20, daysAgo: 0),
        ]
    }

    @Test func prefixMatchesComeBeforeContainsMatches() {
        let result = SmartSuggester.suggestions(for: "gr", in: history)
        #expect(result.map(\.title) == ["Groceries", "Big grocery run", "Café Gris"])
    }

    @Test func eachTitleAppearsOnceWithItsMostRecentAmount() {
        let result = SmartSuggester.suggestions(for: "groc", in: history)
        #expect(result.map(\.title) == ["Groceries", "Big grocery run"])
        #expect(result.first?.amount == 80)
    }

    @Test func limitsToThreeByDefault() {
        let result = SmartSuggester.suggestions(for: "g", in: history)
        #expect(result.count == 3)
        #expect(result.map(\.title) == ["Groceries", "Gas", "Gym membership"])
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(SmartSuggester.suggestions(for: "CAFE", in: history).map(\.title) == ["Café Gris"])
        #expect(SmartSuggester.suggestions(for: "gris", in: history).map(\.title) == ["Café Gris"])
    }

    @Test func emptyQueryOrNoMatchSuggestsNothing() {
        #expect(SmartSuggester.suggestions(for: "", in: history).isEmpty)
        #expect(SmartSuggester.suggestions(for: "   ", in: history).isEmpty)
        #expect(SmartSuggester.suggestions(for: "xyz", in: history).isEmpty)
    }

    @Test func leavesOutTheExpenseBeingEdited() {
        let items = history
        let outing = items.first { $0.title == "Outing" }!
        #expect(SmartSuggester.suggestions(for: "out", in: items, excluding: outing.id).isEmpty)
        #expect(SmartSuggester.suggestions(for: "out", in: items).count == 1)
    }
}
