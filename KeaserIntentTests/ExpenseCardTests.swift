import AppIntents
import AppIntentsTesting
import XCTest

/// The confirmation card's own intents. The card only exists while Add
/// Expense waits for Continue, which a test cannot answer, so these check
/// that each tap intent is registered, takes its parameters and leaves an
/// unknown session alone.
final class ExpenseCardTests: IntentTestCase {
    func testTapIntentsIgnoreAnUnknownCard() async throws {
        let session = UUID().uuidString
        try await definitions.intents["ShowExpenseCardOptionsIntent"].makeIntent(session: session, detail: "category").run()
        try await definitions.intents["PageExpenseCardOptionsIntent"].makeIntent(session: session, page: 2).run()
        try await definitions.intents["PickExpenseCardOptionIntent"].makeIntent(session: session, detail: "category", option: UUID().uuidString).run()
        try await definitions.intents["CloseExpenseCardOptionsIntent"].makeIntent(session: session).run()
        // Nothing was added.
        let total = try await spent("allTime")
        XCTAssertEqual(total, 0)
    }
}
