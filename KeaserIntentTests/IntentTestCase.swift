import AppIntents
import AppIntentsTesting
import Synchronization
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

    /// How long one Spotlight search may take. AppIntentsTesting's
    /// `spotlightQuery` can stall with no end on a freshly booted simulator;
    /// unbounded, one stalled search used up the test's whole execution
    /// time allowance and restarted the runner.
    static let spotlightQueryLimit: Duration = .seconds(15)

    /// `entity.spotlightQuery(text)`, or a `TimedOut` error after
    /// `spotlightQueryLimit`.
    func spotlight(_ entity: AppEntityDefinition, _ text: String) async throws -> [AnyAppEntity] {
        try await within(Self.spotlightQueryLimit, "Spotlight search for \"\(text)\"") {
            try await entity.spotlightQuery(text)
        }
    }

    /// Thrown by `within(_:_:_:)` when the work outlasts its limit.
    struct TimedOut: Error, CustomStringConvertible {
        let what: String
        let limit: Duration
        var description: String { "\(what) did not answer within \(limit)" }
    }

    /// What `body` returns, or `TimedOut` once `limit` passes, whichever
    /// comes first. The work is abandoned at the limit rather than awaited,
    /// since a stalled system call ignores cancellation.
    func within<T: Sendable>(_ limit: Duration, _ what: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let once = ResumeOnce<T>()
        return try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            Task {
                do { once.resume(with: .success(try await body())) } catch { once.resume(with: .failure(error)) }
            }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(with: .failure(TimedOut(what: what, limit: limit)))
            }
        }
    }

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

    /// Checks `condition` until it holds or `limit` passes. A check that
    /// times out (`TimedOut`) counts as not yet.
    func eventually(for limit: Duration = .seconds(20), _ message: String, _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + limit
        while true {
            var lastTimeout: TimedOut?
            do {
                if try await condition() { return }
            } catch let timeout as TimedOut {
                lastTimeout = timeout
            }
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out: \(message)" + (lastTimeout.map { " (\($0))" } ?? ""))
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

/// Resumes a continuation exactly once, from whichever of several tasks
/// gets there first.
private final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation = Mutex<CheckedContinuation<T, any Error>?>(nil)

    func set(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation.withLock { $0 = continuation }
    }

    func resume(with result: Result<T, any Error>) {
        let waiting = continuation.withLock { current -> CheckedContinuation<T, any Error>? in
            defer { current = nil }
            return current
        }
        waiting?.resume(with: result)
    }
}
