import AppIntents
import AppIntentsTesting
import XCTest

/// The entity queries Siri, Shortcuts and Spotlight resolve names and IDs
/// with.
final class EntityQueryTests: IntentTestCase {
    func testExpenseStringQueryMatchesTitlesNewestFirst() async throws {
        let found = try await expenses.entities(matching: "coffee")
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThanOrEqual(found.count, 50, "capped")
        var previous = Date.distantFuture
        for expense in found {
            let title: String = try expense.title
            XCTAssertTrue(title.localizedCaseInsensitiveContains("coffee"), title)
            let date: Date = try expense.date
            XCTAssertLessThanOrEqual(date, previous, "newest first")
            previous = date
        }
    }

    func testExpenseIDsResolveInEveryAccount() async throws {
        let business = try await addExpense("Printer ink", amount: "22")
        let personal = try await expenses.entities(matching: "Groceries").first
        let ids = [business.identifier.instanceIdentifier, try XCTUnwrap(personal).identifier.instanceIdentifier]
        let found = try await expenses.entities(identifiers: ids + [UUID().uuidString])
        XCTAssertEqual(found.count, 2, "both accounts, and nothing for an unknown ID")
        XCTAssertEqual(Set(try found.map { try $0.accountName as String }), ["Business", "Personal"])
    }

    func testExpenseSuggestionsAreTheNewest() async throws {
        let added = try await addExpense("Just now", amount: "1", date: .now.addingTimeInterval(60))
        let suggested = try await expenses.suggestedEntities()
        XCTAssertEqual(suggested.count, 20)
        XCTAssertEqual(suggested.first?.identifier, added.identifier, "the newest first, from any account")
    }

    func testAccounts() async throws {
        let suggested = try await accounts.suggestedEntities()
        XCTAssertEqual(try suggested.map { try $0.name as String }, ["Personal", "Business"])
        let matched = try await accounts.entities(matching: "busi")
        XCTAssertEqual(try matched.map { try $0.name as String }, ["Business"])
        let byID = try await accounts.entities(identifiers: [try XCTUnwrap(matched.first).identifier.instanceIdentifier])
        XCTAssertEqual(try byID.first?.name as String?, "Business")
    }

    func testCategoriesAndPaymentMethods() async throws {
        let categories = try await self.categories.entities(matching: "food")
        XCTAssertEqual(try categories.map { try $0.name as String }, ["Food & Drinks"], "one per name, across accounts")
        let suggestedCategories = try await self.categories.suggestedEntities()
        XCTAssertTrue(try suggestedCategories.contains { try $0.name as String == "Transportation" })

        let methods = try await paymentMethods.entities(matching: "card")
        XCTAssertEqual(Set(try methods.map { try $0.name as String }), ["Credit Card", "Debit Card"])
        let suggestedMethods = try await paymentMethods.suggestedEntities()
        XCTAssertEqual(suggestedMethods.count, 5)
    }
}
