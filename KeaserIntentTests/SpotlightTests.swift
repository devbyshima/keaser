import AppIntents
import AppIntentsTesting
import XCTest

/// Keaser's Spotlight index, searched as the system searches it.
final class SpotlightTests: IntentTestCase {
    func testANewExpenseIsIndexed() async throws {
        let before = try await spotlight(expenses, "Zeppelin ride")
        XCTAssertTrue(before.isEmpty)

        let expense = try await addExpense("Zeppelin ride", amount: "250", category: "Travel")

        try await eventually("the new expense is in Spotlight") {
            try await !self.spotlight(self.expenses, "Zeppelin ride").isEmpty
        }
        let found = try await spotlight(expenses, "Zeppelin ride")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.identifier, expense.identifier)
        XCTAssertEqual(try found.first?.title as String?, "Zeppelin ride")
    }

    func testAccountsAreIndexed() async throws {
        try await eventually("Business is in Spotlight") {
            try await self.spotlight(self.accounts, "Business").contains { (try? $0.name as String) == "Business" }
        }
    }
}
