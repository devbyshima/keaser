import Foundation
import Testing
@testable import KeaserKit

/// Two devices on one Apple Account, syncing through `TestCloud` with the
/// real diff (`SyncPlan`) and merge (`SyncMerge`).
@MainActor
struct SyncTwoDeviceTests {
    /// A has "Personal" with two expenses and has synced; B has synced too.
    private func pair() -> (cloud: TestCloud, a: TestDevice, b: TestDevice) {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        a.store.saveExpense(Expense(title: "Coffee", amount: 4, categoryID: personal.categories[0].id), in: personal.id)
        a.store.saveExpense(Expense(title: "Lunch", amount: 12), in: personal.id)
        a.sync(cloud)
        let b = TestDevice()
        b.sync(cloud)
        return (cloud, a, b)
    }

    @Test func aSecondDeviceReceivesEverything() {
        let (cloud, a, b) = pair()
        #expect(b.account("Personal")?.expenses.count == 2)
        #expect(b.account("Personal")?.categories.map(\.name) == a.account("Personal")?.categories.map(\.name))
        #expect(b.account("Personal")?.paymentMethods.map(\.name) == a.account("Personal")?.paymentMethods.map(\.name))
        #expect(b.expense("Coffee")?.categoryID == a.expense("Coffee")?.categoryID)
        #expect(sameContent(a, b))
        // Nothing left to send on either side.
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
        #expect(cloud.names(of: .expense).count == 2)
    }

    @Test func editsToDifferentRecordsBothArrive() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        var coffee = try #require(a.expense("Coffee"))
        coffee.amount = 5
        a.store.saveExpense(coffee, in: account.id)
        var lunch = try #require(b.expense("Lunch"))
        lunch.title = "Team lunch"
        b.store.saveExpense(lunch, in: account.id)
        b.store.saveExpense(Expense(title: "Taxi", amount: 20), in: account.id)

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.expense("Coffee")?.amount == 5)
        #expect(a.expense("Team lunch") != nil)
        #expect(a.expense("Taxi") != nil)
        #expect(sameContent(a, b))
    }

    @Test func theLaterEditOfTheSameRecordWins() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        var onA = try #require(a.expense("Coffee"))
        onA.title = "Coffee on A"
        a.store.saveExpense(onA, in: account.id, now: later(by: 10))
        var onB = try #require(b.expense("Coffee"))
        onB.title = "Coffee on B"
        b.store.saveExpense(onB, in: account.id, now: later(by: 20))

        // A reaches iCloud first; B's later edit still wins everywhere.
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.expense("Coffee on B") != nil)
        #expect(b.expense("Coffee on B") != nil)
        #expect(a.expense("Coffee on A") == nil)
        #expect(sameContent(a, b))
    }

    @Test func anEarlierEditLosesEvenWhenItArrivesLast() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        var onA = try #require(a.expense("Coffee"))
        onA.title = "Coffee on A"
        a.store.saveExpense(onA, in: account.id, now: later(by: 30))
        var onB = try #require(b.expense("Coffee"))
        onB.title = "Coffee on B"
        b.store.saveExpense(onB, in: account.id, now: later(by: 20))

        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        #expect(a.expense("Coffee on A") != nil)
        #expect(b.expense("Coffee on A") != nil)
        #expect(sameContent(a, b))
    }

    @Test func editsAtTheSameInstantSettleTheSameWayOnBothDevices() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        let instant = later(by: 50)
        var onA = try #require(a.expense("Lunch"))
        onA.amount = 13
        a.store.saveExpense(onA, in: account.id, now: instant)
        var onB = try #require(b.expense("Lunch"))
        onB.amount = 14
        b.store.saveExpense(onB, in: account.id, now: instant)

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        let amount = a.expense("Lunch")?.amount
        #expect(amount == b.expense("Lunch")?.amount)
        #expect(amount == 13 || amount == 14)
        #expect(sameContent(a, b))
    }

    @Test func anEditMadeAfterADeletionBringsTheRecordBack() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        let lunch = try #require(a.expense("Lunch"))
        a.store.deleteExpense(lunch.id, in: account.id)
        _ = a.upload() // the deletion is noticed now...
        var edited = try #require(b.expense("Lunch"))
        edited.amount = 15
        b.store.saveExpense(edited, in: account.id, now: later(by: 5)) // ...and the edit after it

        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        #expect(a.expense("Lunch")?.amount == 15)
        #expect(b.expense("Lunch")?.amount == 15)
        #expect(cloud.records[SyncRecordName.make(.expense, lunch.id)] != nil)
    }

    @Test func aDeletionAfterTheLastEditStands() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        var edited = try #require(b.expense("Lunch"))
        edited.amount = 15
        b.store.saveExpense(edited, in: account.id)
        b.sync(cloud)
        // A deletes after B's edit, without having seen it.
        let lunch = try #require(a.expense("Lunch"))
        a.store.deleteExpense(lunch.id, in: account.id)
        _ = a.upload(now: later(by: 5))

        a.sync(cloud)
        b.sync(cloud)
        #expect(a.expense("Lunch") == nil)
        #expect(b.expense("Lunch") == nil)
        #expect(cloud.records[SyncRecordName.make(.expense, lunch.id)] == nil)
    }

    @Test func anEditOutlivesADeletionThatReachedICloudFirst() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        let lunch = try #require(a.expense("Lunch"))
        a.store.deleteExpense(lunch.id, in: account.id)
        a.sync(cloud)
        #expect(cloud.records[SyncRecordName.make(.expense, lunch.id)] == nil)
        // B edited it offline, before hearing of the deletion.
        var edited = try #require(b.expense("Lunch"))
        edited.title = "Lunch with receipt"
        b.store.saveExpense(edited, in: account.id)

        b.sync(cloud)
        a.sync(cloud)
        #expect(b.expense("Lunch with receipt") != nil)
        #expect(a.expense("Lunch with receipt") != nil)
        #expect(sameContent(a, b))
    }

    @Test func aDeletionElsewhereRemovesAnUnchangedRecord() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        let coffee = try #require(a.expense("Coffee"))
        a.store.deleteExpense(coffee.id, in: account.id)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.expense("Coffee") == nil)
        #expect(b.upload().isEmpty)
    }

    @Test func expensesOfACategoryDeletedElsewhereKeepWorkingUncategorised() throws {
        let (cloud, a, b) = pair()
        let account = try #require(a.account("Personal"))
        let food = try #require(account.categories.first)
        // B files Lunch under Food & Drinks too, offline, after A's delete.
        a.store.deleteCategory(food.id, in: account.id)
        var lunch = try #require(b.expense("Lunch"))
        lunch.categoryID = food.id
        b.store.saveExpense(lunch, in: account.id, now: later(by: 5))

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            let personal = try #require(device.account("Personal"))
            #expect(!personal.categories.contains { $0.id == food.id })
            #expect(device.expense("Coffee")?.categoryID == nil)
            // Kept, and shown as uncategorised: the ID matches no category.
            let kept = try #require(device.expense("Lunch"))
            #expect(personal.category(id: kept.categoryID) == nil)
            #expect(personal.symbol(for: kept) == ExpenseCategory.fallbackSymbol)
        }
        #expect(cloud.records[SyncRecordName.make(.category, food.id)] == nil)
    }

    @Test func anAccountDeletedElsewhereTakesEverythingInItAlong() throws {
        let (cloud, a, b) = pair()
        let business = b.store.createAccount(name: "Business")
        b.store.saveExpense(Expense(title: "Printer", amount: 99), in: business.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.expense("Printer") != nil)

        a.store.deleteAccount(business.id)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.account("Business") == nil)
        #expect(b.expense("Printer") == nil)
        #expect(b.database.preferences.selectedAccountID == b.account("Personal")?.id)
        #expect(!cloud.records.values.contains { stored in
            (try? SyncRecord(name: "", type: stored.type, payload: stored.payload))?.parent == business.id
        })
        #expect(cloud.records[SyncRecordName.make(.account, business.id)] == nil)
        #expect(cloud.records[SyncRecordName.categoriesOrder(business.id)] == nil)
    }

    @Test func somethingAddedToAnAccountDeletedHereGoesToo() throws {
        let (cloud, a, b) = pair()
        let personal = try #require(a.account("Personal"))
        a.store.deleteAccount(personal.id)
        _ = a.upload()
        b.store.saveExpense(Expense(title: "Late", amount: 1), in: personal.id)
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        #expect(a.account("Personal") == nil)
        #expect(a.expense("Late") == nil)
        #expect(b.account("Personal") == nil)
        #expect(cloud.names(of: .expense).isEmpty)
    }

    @Test func offlineEditsAllGoOutTogether() throws {
        let (cloud, a, b) = pair()
        let personal = try #require(b.account("Personal"))
        let business = b.store.createAccount(name: "Business")
        b.store.renameAccount(personal.id, to: "Home")
        b.store.saveCategory(ExpenseCategory(name: "Gym", symbol: "dumbbell.fill"), in: personal.id)
        b.store.savePaymentMethod(PaymentMethod(name: "Company Card", symbol: "briefcase.fill"), in: business.id)
        for n in 1 ... 5 { b.store.saveExpense(Expense(title: "Offline \(n)", amount: Decimal(n)), in: business.id) }
        b.store.updatePreferences { $0.currencyCode = "EUR" }

        b.sync(cloud)
        a.sync(cloud)
        #expect(a.account("Home") != nil)
        #expect(a.account("Home")?.categories.last?.name == "Gym")
        #expect(a.account("Business")?.paymentMethods.last?.name == "Company Card")
        #expect(a.account("Business")?.expenses.count == 5)
        #expect(a.database.preferences.currencyCode == "EUR")
        #expect(sameContent(a, b))
    }

    @Test func settingsSyncButDeviceSettingsStay() throws {
        let (cloud, a, b) = pair()
        a.store.updatePreferences {
            $0.firstWeekday = .monday
            $0.smartSuggestionsEnabled = false
            $0.weeklySummaryEnabled = true
            $0.hasSeenWelcomeLetter = true
        }
        let business = a.store.createAccount(name: "Business")
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.database.preferences.firstWeekday == .monday)
        #expect(!b.database.preferences.smartSuggestionsEnabled)
        // One device's own: its summary, its letter, its selected account.
        #expect(!b.database.preferences.weeklySummaryEnabled)
        #expect(!b.database.preferences.hasSeenWelcomeLetter)
        #expect(b.database.preferences.selectedAccountID != business.id)
    }

    @Test func theEarliestPassStartWins() throws {
        let (cloud, a, b) = pair()
        let early = Date(timeIntervalSinceReferenceDate: 800_000_000)
        a.store.updatePreferences { $0.trialStartDate = early.addingTimeInterval(86_400) }
        b.store.updatePreferences {
            $0.trialStartDate = early
        }
        // A's change is later, so A's settings win, but not A's later pass.
        a.store.updatePreferences { $0.currencyCode = "JPY" }
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        #expect(a.database.preferences.currencyCode == "JPY")
        #expect(a.database.preferences.trialStartDate == early)
        #expect(b.database.preferences.trialStartDate == early)
    }

    @Test func sameNamedCategoriesMadeOnTwoDevicesBecomeOne() throws {
        let (cloud, a, b) = pair()
        let personal = try #require(a.account("Personal"))
        let gymA = ExpenseCategory(name: "Gym", symbol: "dumbbell.fill")
        a.store.saveCategory(gymA, in: personal.id)
        a.store.saveExpense(Expense(title: "Membership", amount: 30, categoryID: gymA.id), in: personal.id)
        let gymB = ExpenseCategory(name: "gym", symbol: "figure.run")
        b.store.saveCategory(gymB, in: personal.id)
        b.store.saveExpense(Expense(title: "Shoes", amount: 80, categoryID: gymB.id), in: personal.id)

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        for device in [a, b] {
            let account = try #require(device.account("Personal"))
            let gyms = account.categories.filter { $0.name.lowercased() == "gym" }
            #expect(gyms.count == 1)
            #expect(device.expense("Membership")?.categoryID == gyms.first?.id)
            #expect(device.expense("Shoes")?.categoryID == gyms.first?.id)
        }
        #expect(cloud.names(of: .category).count == 8)
        #expect(sameContent(a, b))
    }

    @Test func aReorderReachesTheOtherDeviceAndNewLabelsKeepTheirPlace() throws {
        let (cloud, a, b) = pair()
        let personal = try #require(a.account("Personal"))
        a.store.moveCategories(in: personal.id, fromOffsets: [0], toOffset: 7)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.account("Personal")?.categories.map(\.name) == a.account("Personal")?.categories.map(\.name))
        #expect(b.account("Personal")?.categories.last?.name == "Food & Drinks")

        b.store.saveCategory(ExpenseCategory(name: "Pets", symbol: "pawprint.fill"), in: personal.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.account("Personal")?.categories.last?.name == "Pets")
        #expect(sameContent(a, b))
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
    }

    @Test func theLaterOfTwoReordersWinsAndNoLabelIsLost() throws {
        let (cloud, a, b) = pair()
        let personal = try #require(a.account("Personal"))
        a.store.moveCategories(in: personal.id, fromOffsets: [0], toOffset: 7)
        b.store.saveCategory(ExpenseCategory(name: "Pets", symbol: "pawprint.fill"), in: personal.id)
        b.store.moveCategories(in: personal.id, fromOffsets: [6], toOffset: 0)
        let expected = b.account("Personal")?.categories.map(\.name)

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.account("Personal")?.categories.map(\.name) == expected)
        #expect(sameContent(a, b))
    }

    @Test func accountOrderAndRenamesSync() throws {
        let (cloud, a, b) = pair()
        let business = a.store.createAccount(name: "Business")
        a.store.moveAccounts(fromOffsets: [1], toOffset: 0)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.database.accounts.map(\.name) == ["Business", "Personal"])
        b.store.renameAccount(business.id, to: "Work")
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.database.accounts.map(\.name) == ["Work", "Personal"])
    }

    @Test func somethingThatArrivesBeforeItsAccountWaitsForIt() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let travel = a.store.createAccount(name: "Travel")
        a.store.saveExpense(Expense(title: "Hotel", amount: 200), in: travel.id)
        a.sync(cloud)

        let b = TestDevice()
        let expenseName = SyncRecordName.make(.expense, try #require(a.expense("Hotel")).id)
        b.pullPartially(cloud, names: [expenseName])
        #expect(b.expense("Hotel") == nil)
        #expect(b.state.parked[expenseName] != nil)
        b.sync(cloud)
        #expect(b.expense("Hotel") != nil)
        #expect(b.state.parked.isEmpty)
        #expect(sameContent(a, b))
    }

    @Test func aLostZoneIsFilledAgainWithoutDuplicates() throws {
        let (cloud, a, b) = pair()
        cloud.wipe()
        a.state.forgetZone()
        b.state.forgetZone()
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.database.accounts.count == 1)
        #expect(b.database.accounts.count == 1)
        #expect(cloud.names(of: .account).count == 1)
        #expect(cloud.names(of: .expense).count == 2)
        #expect(sameContent(a, b))
    }
}

/// A device that already has data meeting iCloud for the first time.
@MainActor
struct SyncFirstSyncTests {
    private func original() -> (TestCloud, TestDevice) {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        a.store.saveExpense(Expense(title: "Coffee", amount: 4, categoryID: personal.categories[0].id), in: personal.id)
        a.store.updatePreferences { $0.currencyCode = "EUR" }
        a.sync(cloud)
        return (cloud, a)
    }

    @Test func nothingIsSentBeforeTheFirstFetch() {
        let b = TestDevice()
        b.store.createAccount(name: "Personal")
        #expect(b.upload().isEmpty)
        b.state.hasCompletedInitialSync = true
        #expect(!b.upload().isEmpty)
    }

    @Test func aSecondDevicesAccountOfTheSameNameMergesIn() throws {
        let (cloud, a) = original()
        // B was used offline first: its own Personal, with an expense filed
        // under its own copy of a built-in category, and a custom one.
        let b = TestDevice()
        let own = b.store.createAccount(name: "personal")
        b.store.saveCategory(ExpenseCategory(name: "Pets", symbol: "pawprint.fill"), in: own.id)
        b.store.saveExpense(Expense(title: "Groceries", amount: 50, categoryID: own.categories[1].id, paymentMethodID: own.paymentMethods[2].id), in: own.id)

        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            #expect(device.database.accounts.count == 1)
            let personal = try #require(device.account("Personal"))
            #expect(personal.expenses.count == 2)
            #expect(personal.categories.count == 8)
            #expect(personal.categories.last?.name == "Pets")
            #expect(personal.paymentMethods.count == 5)
            let groceries = try #require(device.expense("Groceries"))
            #expect(personal.category(id: groceries.categoryID)?.name == "Shopping")
            #expect(personal.paymentMethod(id: groceries.paymentMethodID)?.name == "Cash")
        }
        #expect(b.database.preferences.selectedAccountID == a.account("Personal")?.id)
        #expect(cloud.names(of: .account).count == 1)
        #expect(cloud.names(of: .category).count == 8)
        #expect(cloud.names(of: .paymentMethod).count == 5)
    }

    @Test func aSecondDeviceTakesOnTheSettingsInICloud() throws {
        let (cloud, a) = original()
        let b = TestDevice()
        // Onboarding on B: its own currency, a pass started now.
        b.store.updatePreferences {
            $0.currencyCode = "USD"
            $0.trialStartDate = .now
            $0.hasCompletedOnboarding = true
        }
        a.store.updatePreferences { $0.trialStartDate = Date(timeIntervalSinceReferenceDate: 800_000_000) }
        a.sync(cloud)

        b.sync(cloud)
        #expect(b.database.preferences.currencyCode == "EUR")
        #expect(b.database.preferences.trialStartDate == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(b.database.preferences.hasCompletedOnboarding)
    }

    @Test func aPlaceholderAccountGivesWayToTheAccountsInICloud() throws {
        let (cloud, a) = original()
        let b = TestDevice()
        b.store.createAccount(name: "Main")
        b.sync(cloud)
        a.sync(cloud)
        #expect(b.database.accounts.map(\.name) == ["Personal"])
        #expect(b.database.preferences.selectedAccountID == b.account("Personal")?.id)
        #expect(a.database.accounts.map(\.name) == ["Personal"])
    }

    @Test func anAccountWithSomethingInItStays() throws {
        let (cloud, a) = original()
        let b = TestDevice()
        let main = b.store.createAccount(name: "Main")
        b.store.saveExpense(Expense(title: "Books", amount: 9), in: main.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(Set(a.database.accounts.map(\.name)) == ["Personal", "Main"])
        #expect(Set(b.database.accounts.map(\.name)) == ["Personal", "Main"])
    }

    @Test func anOldEmptyAccountStays() throws {
        let (cloud, _) = original()
        let b = TestDevice(Database(accounts: [Account(name: "Savings", createdAt: Date(timeIntervalSinceNow: -7200))]))
        b.sync(cloud)
        #expect(Set(b.database.accounts.map(\.name)) == ["Personal", "Savings"])
    }

    @Test func accountsOfOtherNamesStaySeparateAfterTheFirstSync() throws {
        let (cloud, a) = original()
        let b = TestDevice()
        b.sync(cloud)
        // Both devices now make a "Business" on their own: two accounts, as
        // the person may well want two of a name once synced.
        a.store.createAccount(name: "Business")
        b.store.createAccount(name: "Business")
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.database.accounts.filter { $0.name == "Business" }.count == 2)
        #expect(b.database.accounts.filter { $0.name == "Business" }.count == 2)
    }
}
