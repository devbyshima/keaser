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
        var database = DemoData.database(accounts ? .demo : .onboarded, now: now, calendar: calendar)
        database.preferences.shortcutConfirmsDetails = confirmsDetails
        database.preferences.hasProPurchase = false
        database.preferences.proExpirationDate = nil
        let passDays = ProEntitlement.trialDays
        database.preferences.trialStartDate = pro ? now : calendar.date(byAdding: .day, value: -(passDays + 3), to: now)
        return database
    }
}
