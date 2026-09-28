import Foundation

/// The data every App Intents test (the KeaserIntentTests UI-test bundle)
/// starts from, written to the real database file by the Debug-only
/// `ResetTestDataIntent`: the demo seed (Personal, selected and full of
/// expenses, and an empty Business), so a test can add expenses to Business
/// and know exactly what its totals must be.
public enum IntentTestFixture {
    /// The selected account, with the demo seed's expenses.
    public static let fullAccountName = "Personal"
    /// Empty, so totals after adding to it are exact.
    public static let emptyAccountName = "Business"

    /// - Parameters:
    ///   - pro: true starts the 7-day pass now; false has it end days ago,
    ///     with no purchase, so Pro features refuse.
    ///   - confirmsDetails: Settings > Shortcut > Confirm Expense Details.
    ///     Off lets Add Expense run with everything supplied and nothing
    ///     asked.
    ///   - accounts: false leaves Keaser set up but with no account yet.
    public static func database(pro: Bool, confirmsDetails: Bool, accounts: Bool = true, now: Date = .now, calendar: Calendar = .current) -> Database {
        var database = withFixedIDs(DemoData.database(accounts ? .demo : .onboarded, now: now, calendar: calendar))
        database.preferences.shortcutConfirmsDetails = confirmsDetails
        database.preferences.hasProPurchase = false
        database.preferences.proExpirationDate = nil
        let passDays = ProEntitlement.trialDays
        database.preferences.trialStartDate = pro ? now : calendar.date(byAdding: .day, value: -(passDays + 3), to: now)
        return database
    }

    /// The same account and expense IDs on every reset (within a day, the
    /// same dates too), so a reset changes in Spotlight only what the last
    /// test added or deleted. With new IDs every time, each reset deleted
    /// and indexed the whole demo account again (hundreds of items) before
    /// every test, the simulator's Spotlight fell behind, and searches were
    /// held back while it still had writes queued.
    static func withFixedIDs(_ database: Database) -> Database {
        var database = database
        var expenseIndex = 0
        for a in database.accounts.indices {
            let fixed = fixedID(kind: 0xA, index: a)
            if database.preferences.selectedAccountID == database.accounts[a].id {
                database.preferences.selectedAccountID = fixed
            }
            database.accounts[a].id = fixed
            for e in database.accounts[a].expenses.indices {
                database.accounts[a].expenses[e].id = fixedID(kind: 0xE, index: expenseIndex)
                expenseIndex += 1
            }
        }
        return database
    }

    static func fixedID(kind: Int, index: Int) -> UUID {
        UUID(uuidString: String(format: "4B454153-%04X-4000-8000-%012X", kind, index))!
    }
}
