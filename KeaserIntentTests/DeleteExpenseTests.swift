import AppIntents
import AppIntentsTesting
import XCTest

/// "Delete Expense".
final class DeleteExpenseTests: IntentTestCase {
    func testDeletesTheExpenseEverywhere() async throws {
        let kept = try await addExpense("Stays", amount: "8")
        let expense = try await addExpense("Wrong entry", amount: "27.35")
        let id = expense.identifier.instanceIdentifier
        let before = try await spent("today")
        XCTAssertEqual(before, money("35.35"))

        try await definitions.intents["DeleteExpenseIntent"].makeIntent(entities: [expense]).run()

        let found = try await expenses.entities(identifiers: [id])
        XCTAssertTrue(found.isEmpty, "the expense is gone")
        let after = try await spent("today")
        XCTAssertEqual(after, money("8"))
        let others = try await expenses.entities(identifiers: [kept.identifier.instanceIdentifier])
        XCTAssertEqual(others.count, 1, "nothing else is deleted")
        // And from Spotlight (the intent waits for the index).
        try await eventually("the deleted expense leaves Spotlight") {
            try await self.expenses.spotlightQuery("Wrong entry").isEmpty
        }
    }

    func testDeletesSeveralAtOnce() async throws {
        let first = try await addExpense("First", amount: "1")
        let second = try await addExpense("Second", amount: "2")
        try await definitions.intents["DeleteExpenseIntent"].makeIntent(entities: [first, second]).run()
        let total = try await spent("allTime")
        XCTAssertEqual(total, 0)
    }
}
