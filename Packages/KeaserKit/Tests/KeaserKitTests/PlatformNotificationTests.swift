import Foundation
import Testing
@testable import KeaserKit

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

struct WeeklySummaryAccountTests {
    @Test func thePlanNamesTheAccountItReports() throws {
        let now = noon(2026, 9, 23)
        var personal = Account(name: "Personal")
        personal.expenses = [Expense(title: "Coffee", amount: 4, date: now)]
        let business = Account(name: "Business")
        var prefs = Preferences(currencyCode: "USD", weeklySummaryEnabled: true)
        prefs.selectedAccountID = business.id
        let database = Database(accounts: [personal, business], preferences: prefs)

        let plan = try #require(WeeklySummary.plan(for: database, now: now, calendar: utc, locale: Locale(identifier: "en_US")))
        #expect(plan.accountID == business.id)
        #expect(plan.body == "You spent $0.00 this week.")

        var switched = database
        switched.preferences.selectedAccountID = personal.id
        let other = try #require(WeeklySummary.plan(for: switched, now: now, calendar: utc, locale: Locale(identifier: "en_US")))
        #expect(other.accountID == personal.id)
        #expect(other.body == "You spent $4.00 this week.")
    }
}
