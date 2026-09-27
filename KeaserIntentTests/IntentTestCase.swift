import AppIntents
import AppIntentsTesting
import XCTest

/// Runs Keaser's App Intents and entity queries through the system, as Siri
/// and Shortcuts do (AppIntentsTesting, iOS 27). Nothing here imports the
/// app: intents, entities and enums are named as the app declares them, and
/// every test starts from `IntentTestFixture` (Personal, selected and full of
/// demo expenses; Business, empty), written by the Debug-only
/// `ResetTestDataIntent`.
///
/// The app is launched before each test (which also installs it on the first
/// run), and only read through accessibility afterwards: no test taps.
class IntentTestCase: XCTestCase {
    static let bundleIdentifier = "com.fulltimestudio.keaser"
    let definitions = IntentDefinitions(bundleIdentifier: IntentTestCase.bundleIdentifier)

    /// Keaser Pro in the data the test starts from.
    var startsWithPro: Bool { true }
    /// False starts with no account at all.
    var startsWithAccounts: Bool { true }

    var expenses: AppEntityDefinition { definitions.entities["ExpenseEntity"] }
    var accounts: AppEntityDefinition { definitions.entities["AccountEntity"] }
    var categories: AppEntityDefinition { definitions.entities["CategoryEntity"] }
    var paymentMethods: AppEntityDefinition { definitions.entities["PaymentMethodEntity"] }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await Self.launchApp()
        // Straight after the first install the system may not have read the
        // app's intents yet.
        _ = try await retrying(for: .seconds(60)) {
            try await self.definitions.intents["ResetTestDataIntent"]
                .makeIntent(pro: self.startsWithPro, confirmsDetails: false, accounts: self.startsWithAccounts)
                .run()
        }
    }

    @MainActor
    private static func launchApp() {
        XCUIApplication().launch()
    }

    // MARK: Helpers

    /// "Add Expense" with every parameter supplied, so nothing is asked.
    /// Returns the Expense it adds.
    @discardableResult
    func addExpense(
        _ title: String,
        amount: String,
        account: String = "Business",
        category: String = "Food & Drinks",
        paymentMethod: String = "Credit Card",
        date: Date = .now
    ) async throws -> AnyAppEntity {
        let result = try await definitions.intents["AddExpenseIntent"].makeIntent(
            amount: IntentCurrencyAmount(amount: Decimal(string: amount)!, currencyCode: "USD"),
            expenseTitle: title,
            category: category,
            paymentMethod: paymentMethod,
            account: account,
            date: date
        ).run()
        return try result.value.as(AnyAppEntity.self)
    }

    /// "How Much Did I Spend": the amount it returns.
    func spent(
        _ period: String,
        account: String? = "Business",
        category: String? = nil,
        paymentMethod: String? = nil
    ) async throws -> Decimal {
        let result = try await definitions.intents["GetSpendingIntent"].makeIntent(
            period: period,
            account: account,
            category: category,
            paymentMethod: paymentMethod
        ).run()
        let amount = try result.value.as(IntentCurrencyAmount.self)
        XCTAssertEqual(amount.currencyCode, "USD")
        return amount.amount
    }

    func money(_ text: String) -> Decimal { Decimal(string: text)! }

    /// Repeats `body` until it stops throwing, for work the system finishes
    /// a moment later (Spotlight, reading a new install's intents).
    func retrying<T>(for limit: Duration = .seconds(20), _ body: () async throws -> T) async throws -> T {
        let deadline = ContinuousClock.now + limit
        while true {
            do {
                return try await body()
            } catch {
                if ContinuousClock.now >= deadline { throw error }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Checks `condition` until it holds or `limit` passes.
    func eventually(for limit: Duration = .seconds(20), _ message: String, _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + limit
        while try await !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out: \(message)")
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// The error an intent run ends with, as the system reports it.
    func failure(of run: () async throws -> Void) async -> String? {
        do {
            try await run()
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
