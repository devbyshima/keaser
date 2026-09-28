import AppIntents
import AppIntentsTesting
import XCTest

/// Keaser's Spotlight index, searched as the system searches it.
final class SpotlightTests: IntentTestCase {
    override var searchesSpotlight: Bool { true }

    func testANewExpenseIsIndexed() async throws {
        let before = try await spotlight(expenses, "Zeppelin ride")
        XCTAssertTrue(before.isEmpty)

        let expense = try await addExpense("Zeppelin ride", amount: "250", category: "Travel")

        var found: [AnyAppEntity] = []
        try await eventually(for: Self.spotlightChangeLimit, "the new expense is in Spotlight") {
            found = try await self.spotlight(self.expenses, "Zeppelin ride")
            return !found.isEmpty
        }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.identifier, expense.identifier)
        XCTAssertEqual(try found.first?.title as String?, "Zeppelin ride")
    }

    func testAccountsAreIndexed() async throws {
        try await eventually(for: Self.spotlightChangeLimit, "Business is in Spotlight") {
            try await self.spotlight(self.accounts, "Business").contains { (try? $0.name as String) == "Business" }
        }
    }
}
