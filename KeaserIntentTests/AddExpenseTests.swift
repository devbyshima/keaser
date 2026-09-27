import AppIntents
import AppIntentsTesting
import XCTest

/// "Add Expense" and "Log Wallet Transaction".
final class AddExpenseTests: IntentTestCase {
    func testEveryParameterSuppliedAddsWithoutAsking() async throws {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: .now))!.addingTimeInterval(12 * 3600)
        let expense = try await addExpense("Team lunch", amount: "42.80", category: "Food & Drinks", paymentMethod: "Cash", date: day)

        XCTAssertEqual(try expense.title, "Team lunch")
        XCTAssertEqual(try expense.amount.as(IntentCurrencyAmount.self).amount, money("42.80"))
        XCTAssertEqual(try expense.amount.as(IntentCurrencyAmount.self).currencyCode, "USD")
        XCTAssertEqual(try expense.accountName, "Business")
        // Named after Personal's labels (the string query finds those
        // first), filed under Business's own.
        XCTAssertEqual(try expense.categoryName, Optional("Food & Drinks"))
        XCTAssertEqual(try expense.paymentMethodName, Optional("Cash"))
        let date: Date = try expense.date
        XCTAssertTrue(calendar.isDate(date, inSameDayAs: day), "dated the day supplied, not today")

        // It is in Keaser: found by its ID in a fresh query.
        let found = try await expenses.entities(identifiers: [expense.identifier.instanceIdentifier])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(try found.first?.title, "Team lunch")
    }

    func testTheReturnedExpenseCanBePassedOn() async throws {
        let expense = try await addExpense("Parking", amount: "6")
        // Chained into Open Expense, as a shortcut would.
        try await definitions.intents["OpenExpenseIntent"].makeIntent(target: expense).run()
    }

    func testAnAmountOfNothingIsRefused() async throws {
        let message = await failure {
            _ = try await self.addExpense("Nothing", amount: "0")
        }
        XCTAssertNotNil(message, "a zero amount must not be saved")
        let spent = try await spent("allTime")
        XCTAssertEqual(spent, 0)
    }

    func testWalletTransactionIsFiledLikeTheLastOneThere() async throws {
        let earlier = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        try await addExpense("Blue Bottle Coffee", amount: "5.20", account: "Personal", category: "Food & Drinks", paymentMethod: "Credit Card", date: earlier)

        // A Wallet automation passes the amount as text and the card's name.
        try await definitions.intents["LogWalletTransactionIntent"].makeIntent(
            merchant: "Blue Bottle Coffee",
            amount: "$4.50",
            card: "Cash"
        ).run()

        // Newest first.
        let found = try await expenses.entities(matching: "Blue Bottle")
        XCTAssertEqual(found.count, 2)
        let expense = try XCTUnwrap(found.first)
        XCTAssertEqual(try expense.amount.as(IntentCurrencyAmount.self).amount, money("4.50"))
        // Into the selected account, under the category of the last visit,
        // paid with the card Wallet named.
        XCTAssertEqual(try expense.accountName, "Personal")
        XCTAssertEqual(try expense.categoryName, Optional("Food & Drinks"))
        XCTAssertEqual(try expense.paymentMethodName, Optional("Cash"))
    }
}
