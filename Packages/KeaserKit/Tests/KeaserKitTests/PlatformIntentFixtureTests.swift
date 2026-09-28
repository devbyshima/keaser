import Foundation
import Testing
@testable import KeaserKit

private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

struct IntentTestFixtureTests {
    @Test func personalIsSelectedAndFullBusinessIsEmpty() throws {
        let now = noon(2026, 9, 28)
        let db = IntentTestFixture.database(pro: true, confirmsDetails: false, now: now, calendar: utc)
        #expect(db.accounts.map(\.name) == [IntentTestFixture.fullAccountName, IntentTestFixture.emptyAccountName])
        #expect(db.selectedAccount?.name == IntentTestFixture.fullAccountName)
        #expect(db.accounts[0].expenses.contains { $0.title == "Coffee" })
        #expect(db.accounts[1].expenses.isEmpty)
        // The empty account still has the default labels to file under.
        #expect(db.accounts[1].categories.contains { $0.name == "Food & Drinks" })
        #expect(db.accounts[1].paymentMethods.contains { $0.name == "Credit Card" })
        #expect(db.preferences.currencyCode == "USD")
    }

    @Test func proStartsThePassOrEndsIt() {
        let now = noon(2026, 9, 28)
        let pro = IntentTestFixture.database(pro: true, confirmsDetails: false, now: now, calendar: utc)
        let lapsed = IntentTestFixture.database(pro: false, confirmsDetails: false, now: now, calendar: utc)
        #expect(ProEntitlement.isPro(pro.preferences, now: now))
        #expect(!ProEntitlement.isPro(lapsed.preferences, now: now))
        // Lapsed means no purchase either, so nothing asks StoreKit first.
        #expect(!lapsed.preferences.hasProPurchase)
        #expect(!ProEntitlement.needsStoreKitCheck(lapsed.preferences, now: now, calendar: utc))
    }

    @Test func withoutAccountsKeaserIsSetUpButEmpty() {
        let now = noon(2026, 9, 28)
        let db = IntentTestFixture.database(pro: true, confirmsDetails: false, accounts: false, now: now, calendar: utc)
        #expect(db.accounts.isEmpty)
        #expect(db.selectedAccount == nil)
        #expect(db.preferences.hasCompletedOnboarding)
        #expect(ProEntitlement.isPro(db.preferences, now: now))
    }

    @Test func confirmationFollowsTheSwitch() {
        let now = noon(2026, 9, 28)
        #expect(!IntentTestFixture.database(pro: true, confirmsDetails: false, now: now, calendar: utc).preferences.shortcutConfirmsDetails)
        #expect(IntentTestFixture.database(pro: true, confirmsDetails: true, now: now, calendar: utc).preferences.shortcutConfirmsDetails)
    }

    @Test func everyResetHasTheSameIDs() {
        // Minutes apart on the same day: nothing Spotlight holds changes.
        let first = IntentTestFixture.database(pro: true, confirmsDetails: false, now: noon(2026, 9, 28), calendar: utc)
        let later = IntentTestFixture.database(pro: true, confirmsDetails: false, now: noon(2026, 9, 28).addingTimeInterval(600), calendar: utc)
        #expect(first.accounts.map(\.id) == later.accounts.map(\.id))
        #expect(first.accounts.flatMap(\.expenses).map(\.id) == later.accounts.flatMap(\.expenses).map(\.id))
        #expect(first.preferences.selectedAccountID == first.accounts[0].id)
        let ids = first.accounts.map(\.id) + first.accounts.flatMap(\.expenses).map(\.id)
        #expect(Set(ids).count == ids.count)
        let marker = "1/1.0.0/1"
        #expect(SpotlightPlan.changes(from: SpotlightPlan.manifest(for: first, marker: marker), to: SpotlightPlan.manifest(for: later, marker: marker)).isEmpty)
    }
}
