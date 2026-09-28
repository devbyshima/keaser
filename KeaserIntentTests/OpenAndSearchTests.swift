import AppIntents
import AppIntentsTesting
import XCTest

/// "Open Expense", "Open Account", "Search Expenses" and the iOS 27
/// assistant search. Each leaves a route for Home; the app's screen is then
/// read through accessibility (never tapped) and through the entities it
/// says are on screen.
final class OpenAndSearchTests: IntentTestCase {
    func testOpenExpenseShowsItInEditExpense() async throws {
        let expense = try await addExpense("Museum tickets", amount: "31")
        try await definitions.intents["OpenExpenseIntent"].makeIntent(target: expense).run()

        try await Self.onScreen { app in
            XCTAssertTrue(app.staticTexts["Edit Expense"].waitForExistence(timeout: 15), "Edit Expense is showing")
            XCTAssertEqual(app.textFields["Title"].value as? String, "Museum tickets")
        }
        // The editor tells Siri which expense is open.
        try await eventually("Edit Expense is annotated with the expense") {
            try await self.expenses.viewAnnotations().contains { $0.entity.identifier == expense.identifier }
        }
        // Its account, Business, is selected.
        try await eventually("Home switched to Business") {
            try await self.accounts.viewAnnotations().contains { (try? $0.entity.name as String) == "Business" }
        }
    }

    /// As when a Spotlight result is tapped with Keaser closed.
    func testOpenExpenseFromAColdStart() async throws {
        let expense = try await addExpense("Late train", amount: "19")
        await Self.quitApp()
        try await definitions.intents["OpenExpenseIntent"].makeIntent(target: expense).run()
        try await Self.onScreen { app in
            XCTAssertTrue(app.staticTexts["Edit Expense"].waitForExistence(timeout: 20), "Edit Expense is showing")
            XCTAssertEqual(app.textFields["Title"].value as? String, "Late train")
        }
    }

    func testOpenExpenseByName() async throws {
        try await addExpense("Concert", amount: "64")
        // A name is resolved through the expense string query, as Siri does.
        try await definitions.intents["OpenExpenseIntent"].makeIntent(target: "Concert").run()
        try await Self.onScreen { app in
            XCTAssertTrue(app.staticTexts["Edit Expense"].waitForExistence(timeout: 15))
            XCTAssertEqual(app.textFields["Title"].value as? String, "Concert")
        }
    }

    func testOpenAccountSwitchesHome() async throws {
        try await definitions.intents["OpenAccountIntent"].makeIntent(target: "Business").run()
        try await Self.onScreen { app in
            let bar = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Account: Business")).firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 15), "Home shows Business")
        }
        try await eventually("Home's top bar is annotated with Business") {
            try await self.accounts.viewAnnotations().contains { (try? $0.entity.name as String) == "Business" }
        }
    }

    func testSearchOpensWithTheTerm() async throws {
        try await definitions.intents["SearchExpensesIntent"].makeIntent(criteria: StringSearchCriteria(term: "Coffee")).run()
        try await Self.onScreen { app in
            let field = app.textFields["Search expenses"]
            XCTAssertTrue(field.waitForExistence(timeout: 15), "Search is showing")
            XCTAssertEqual(field.value as? String, "Coffee")
        }
        // The results are annotated rows: every one a coffee.
        try await eventually("search results are on screen") {
            try await !self.expenses.viewAnnotations().isEmpty
        }
        for annotation in try await expenses.viewAnnotations() {
            let title: String = try annotation.entity.title
            XCTAssertTrue(title.localizedCaseInsensitiveContains("coffee"), "\(title) matches")
        }
    }

    func testSearchFromAColdStart() async throws {
        await Self.quitApp()
        try await definitions.intents["SearchExpensesIntent"].makeIntent(criteria: StringSearchCriteria(term: "Netflix")).run()
        try await Self.onScreen { app in
            let field = app.textFields["Search expenses"]
            XCTAssertTrue(field.waitForExistence(timeout: 20), "Search is showing")
            XCTAssertEqual(field.value as? String, "Netflix")
        }
    }

    func testAssistantSearchOpensWithTheTerm() async throws {
        try await definitions.intents["SearchInKeaserIntent"].makeIntent(criteria: StringSearchCriteria(term: "Groceries")).run()
        try await Self.onScreen { app in
            let field = app.textFields["Search expenses"]
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            XCTAssertEqual(field.value as? String, "Groceries")
        }
    }

    @MainActor
    private static func quitApp() {
        XCUIApplication().terminate()
    }

    @MainActor
    private static func onScreen(_ check: @MainActor (XCUIApplication) throws -> Void) async throws {
        try check(XCUIApplication())
    }
}
