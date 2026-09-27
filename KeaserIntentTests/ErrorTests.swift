import AppIntents
import AppIntentsTesting
import XCTest

/// What the intents say when they cannot do what was asked.
final class NoAccountTests: IntentTestCase {
    override var startsWithAccounts: Bool { false }

    func testAddExpenseAsksForAnAccountFirst() async throws {
        let message = await failure {
            try await self.definitions.intents["AddExpenseIntent"].makeIntent(
                amount: IntentCurrencyAmount(amount: 5, currencyCode: "USD"),
                expenseTitle: "Coffee",
                date: Date.now
            ).run()
        }
        assertAccountSetup(message)
    }

    func testSpendingAsksForAnAccountFirst() async throws {
        let message = await failure { _ = try await self.spent("thisWeek", account: nil) }
        assertAccountSetup(message)
    }

    func testWalletAsksForAnAccountFirst() async throws {
        let message = await failure {
            try await self.definitions.intents["LogWalletTransactionIntent"].makeIntent(merchant: "Cafe", amount: "$3").run()
        }
        assertAccountSetup(message)
    }

    /// Keaser's sentence, carried as the system's own "account setup
    /// needed" error (iOS 27's CustomAppIntentErrorConvertible), which the
    /// system reports as an intervention the person has to make.
    private func assertAccountSetup(_ message: String?, file: StaticString = #filePath, line: UInt = #line) {
        let message = message ?? "no error"
        XCTAssertTrue(message.contains("Create an account in Keaser first."), message, file: file, line: line)
        XCTAssertTrue(message.contains("AccountSetup"), "the system's account setup kind: \(message)", file: file, line: line)
    }
}
