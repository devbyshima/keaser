import AppIntents
import AppIntentsTesting
import XCTest

/// "How Much Did I Spend", with Keaser Pro.
final class SpendingTests: IntentTestCase {
    /// Business starts empty, so after two expenses every period's total is
    /// known: today's in every period, the one from over a year ago only in
    /// All Time.
    func testEveryPeriod() async throws {
        let longAgo = Calendar.current.date(byAdding: .day, value: -400, to: .now)!
        try await addExpense("Taxi", amount: "12.50", category: "Transportation", paymentMethod: "Cash")
        try await addExpense("Old invoice", amount: "100", category: "Services", paymentMethod: "Bank Transfer", date: longAgo)

        let today = try await spent("today")
        let thisWeek = try await spent("thisWeek")
        let thisMonth = try await spent("thisMonth")
        let thisYear = try await spent("thisYear")
        let allTime = try await spent("allTime")
        XCTAssertEqual(today, money("12.50"))
        XCTAssertEqual(thisWeek, money("12.50"))
        XCTAssertEqual(thisMonth, money("12.50"))
        XCTAssertEqual(thisYear, money("12.50"))
        XCTAssertEqual(allTime, money("112.50"))
    }

    func testTheSelectedAccountWhenNoneIsNamed() async throws {
        // Personal is selected and full: each period holds the one before.
        let today = try await spent("today", account: nil)
        let thisWeek = try await spent("thisWeek", account: nil)
        let thisMonth = try await spent("thisMonth", account: nil)
        let thisYear = try await spent("thisYear", account: nil)
        let allTime = try await spent("allTime", account: nil)
        XCTAssertLessThanOrEqual(today, thisWeek)
        XCTAssertLessThanOrEqual(thisMonth, thisYear)
        XCTAssertLessThanOrEqual(thisYear, allTime)
        XCTAssertGreaterThan(allTime, 0)
        // And it is Personal's, not Business's.
        let personal = try await spent("allTime", account: "Personal")
        XCTAssertEqual(allTime, personal)
    }

    func testCategoryAndPaymentFilters() async throws {
        try await addExpense("Lunch", amount: "15", category: "Food & Drinks", paymentMethod: "Cash")
        try await addExpense("Dinner", amount: "40", category: "Food & Drinks", paymentMethod: "Credit Card")
        try await addExpense("Bus", amount: "3", category: "Transportation", paymentMethod: "Cash")

        let food = try await spent("thisWeek", category: "Food & Drinks")
        let cash = try await spent("thisWeek", paymentMethod: "Cash")
        let foodInCash = try await spent("thisWeek", category: "Food & Drinks", paymentMethod: "Cash")
        let all = try await spent("thisWeek")
        XCTAssertEqual(food, money("55"))
        XCTAssertEqual(cash, money("18"))
        XCTAssertEqual(foodInCash, money("15"))
        XCTAssertEqual(all, money("58"))
    }

    func testDefaultsToThisWeek() async throws {
        try await addExpense("Taxi", amount: "9.90")
        let result = try await definitions.intents["GetSpendingIntent"].makeIntent(account: "Business").run()
        XCTAssertEqual(try result.value.as(IntentCurrencyAmount.self).amount, money("9.90"))
    }
}

/// "How Much Did I Spend" once the 7-day pass is over and nothing was bought.
final class SpendingWithoutProTests: IntentTestCase {
    override var startsWithPro: Bool { false }

    func testLongTermPeriodsAndFiltersAreRefused() async throws {
        for period in ["thisYear", "allTime"] {
            let message = await failure { _ = try await self.spent(period) }
            XCTAssertNotNil(message, "\(period) needs Pro")
            XCTAssertTrue(message?.contains("Keaser Pro") ?? false, "says why: \(message ?? "")")
            // In Keaser's words only: the system has no kind for it.
            XCTAssertFalse(message?.contains("Prebuilt") ?? true, message ?? "")
        }
        let filtered = await failure { _ = try await self.spent("thisWeek", category: "Food & Drinks") }
        XCTAssertTrue(filtered?.contains("Keaser Pro") ?? false, "the category filter needs Pro: \(filtered ?? "")")
    }

    func testShortPeriodsStillAnswer() async throws {
        let today = try await spent("today", account: nil)
        let thisWeek = try await spent("thisWeek", account: nil)
        let thisMonth = try await spent("thisMonth", account: nil)
        XCTAssertLessThanOrEqual(today, thisWeek)
        XCTAssertGreaterThanOrEqual(thisMonth, 0)
    }
}
