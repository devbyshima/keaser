import AppIntents
import AppIntentsTesting
import XCTest

/// Keaser's Spotlight index, searched as the system searches it.
final class SpotlightTests: IntentTestCase {
    func testANewExpenseIsIndexed() async throws {
        let before = try await expenses.spotlightQuery("Zeppelin ride")
        XCTAssertTrue(before.isEmpty)

        let expense = try await addExpense("Zeppelin ride", amount: "250", category: "Travel")

        try await eventually("the new expense is in Spotlight") {
            try await !self.expenses.spotlightQuery("Zeppelin ride").isEmpty
        }
        let found = try await expenses.spotlightQuery("Zeppelin ride")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.identifier, expense.identifier)
        XCTAssertEqual(try found.first?.title as String?, "Zeppelin ride")
    }

    func testAccountsAreIndexed() async throws {
        try await eventually("Business is in Spotlight") {
            try await self.accounts.spotlightQuery("Business").contains { (try? $0.name as String) == "Business" }
        }
    }
}
