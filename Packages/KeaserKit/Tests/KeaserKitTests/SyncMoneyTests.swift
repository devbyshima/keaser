import Foundation
import Testing
@testable import KeaserKit

/// Wallets, income, transfers, balance adjustments, income categories and
/// split rules between two devices, through `TestCloud` with the real diff
/// (`SyncPlan`) and merge (`SyncMerge`).
@MainActor
struct SyncMoneyTests {
    /// A has "Personal" in EUR with money in it and has synced; B has
    /// synced too. Cash started tracking at 50 an hour ago and was set to
    /// 80 since (a balance adjustment), a salary went into Bank Transfer,
    /// 100 moved from Bank Transfer to Cash, and there is a "Freelance"
    /// income category.
    private func pair() throws -> (cloud: TestCloud, a: TestDevice, b: TestDevice) {
        let cloud = TestCloud()
        let a = TestDevice()
        a.store.updatePreferences { $0.currencyCode = "EUR" }
        let personal = a.store.createAccount(name: "Personal")
        let cash = personal.paymentMethods[2], bank = personal.paymentMethods[3]
        a.store.setBalance(50, ofWallet: cash.id, in: personal.id, at: later(by: -3600))
        a.store.setBalance(80, ofWallet: cash.id, in: personal.id)
        a.store.saveIncomeCategory(IncomeCategory(name: "Freelance", symbol: "laptopcomputer"), in: personal.id)
        a.store.saveIncome(Income(title: "Salary", amount: 2000, categoryID: personal.incomeCategories[0].id, walletID: bank.id), in: personal.id)
        a.store.saveTransfer(Transfer(fromWalletID: bank.id, toWalletID: cash.id, amountOut: 100, note: "Cash for the week"), in: personal.id)
        a.sync(cloud)
        let b = TestDevice()
        b.sync(cloud)
        return (cloud, a, b)
    }

    @Test func moneyMadeOnOneDeviceArrivesOnTheOther() throws {
        let (cloud, a, b) = try pair()
        let onA = try #require(a.account("Personal"))
        let onB = try #require(b.account("Personal"))
        #expect(onB.incomeCategories.map(\.name) == ["Salary", "Business", "Gifts", "Refunds", "Freelance"])
        #expect(onB.incomeCategories == onA.incomeCategories)
        #expect(onB.incomes == onA.incomes)
        #expect(onB.transfers == onA.transfers)
        #expect(onB.balanceAdjustments == onA.balanceAdjustments)
        #expect(onB.balanceAdjustments.map(\.balance) == [80])
        #expect(onB.splitRule == onA.splitRule)
        let cash = try #require(b.wallet("Cash"))
        #expect(cash.kind == .cash)
        #expect(cash.isTracking)
        #expect(cash.openingBalance == 50)
        #expect(b.income("Salary")?.categoryID == onB.incomeCategories.first?.id)
        #expect(sameContent(a, b))
        // Nothing left to send on either side.
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
        #expect(cloud.names(of: .incomeCategory).count == 5)
        #expect(cloud.names(of: .income).count == 1)
        #expect(cloud.names(of: .transfer).count == 1)
        #expect(cloud.names(of: .balanceAdjustment).count == 1)
        #expect(cloud.names(of: .splitRule) == [SyncRecordName.make(.splitRule, onA.id)])
        #expect(cloud.records[SyncRecordName.incomeCategoriesOrder(onA.id)] != nil)
    }

    @Test func theLaterEditOfAnIncomeWinsAndTransferEditsArrive() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        var onA = try #require(a.income("Salary"))
        onA.amount = 2100
        a.store.saveIncome(onA, in: personal.id, now: later(by: 10))
        var onB = try #require(b.income("Salary"))
        onB.title = "October salary"
        b.store.saveIncome(onB, in: personal.id, now: later(by: 20))
        var transfer = try #require(a.transfer("Cash for the week"))
        transfer.amountOut = 120
        transfer.amountIn = 120
        a.store.saveTransfer(transfer, in: personal.id, now: later(by: 30))

        // A reaches iCloud first; B's later edit of the income still wins.
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            #expect(device.income("October salary")?.amount == 2000)
            #expect(device.income("Salary") == nil)
            #expect(device.transfer("Cash for the week")?.amountIn == 120)
        }
        #expect(sameContent(a, b))
    }

    @Test func aSavingsTransferTravelsWithItsIncome() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        let savings = PaymentMethod(name: "Savings", symbol: "banknote", isSavings: true)
        a.store.savePaymentMethod(savings, in: personal.id)
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsWalletID = savings.id
        }
        let bank = try #require(a.wallet("Bank Transfer"))
        a.store.saveIncome(Income(title: "Bonus", amount: 500, walletID: bank.id), in: personal.id)
        let bonus = try #require(a.income("Bonus"))
        let transferID = try #require(bonus.savingsTransferID)
        a.sync(cloud)
        b.sync(cloud)

        let onB = try #require(b.account("Personal"))
        let split = try #require(onB.transfer(id: transferID))
        #expect(split.kind == .savings)
        #expect(split.incomeID == bonus.id)
        #expect(split.amountOut == 100)
        #expect(split.toWalletID == savings.id)
        #expect(onB.splitRule.isEnabled)
        #expect(onB.splitRule.savingsWalletID == savings.id)
        #expect(b.income("Bonus")?.savingsPercent == 20)
        #expect(b.wallet("Savings")?.isSavings == true)

        // Deleting it on B is skipping it, on both devices.
        b.store.deleteTransfer(transferID, in: personal.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.account("Personal")?.transfer(id: transferID) == nil)
        #expect(a.income("Bonus")?.savingsSkipped == true)
        #expect(a.income("Bonus")?.savingsTransferID == nil)
        #expect(cloud.records[SyncRecordName.make(.transfer, transferID)] == nil)

        // Deleting an income on B takes its savings transfer along on A.
        a.store.saveIncome(Income(title: "Gift", amount: 50, walletID: bank.id), in: personal.id)
        let gift = try #require(a.income("Gift"))
        let giftTransfer = try #require(gift.savingsTransferID)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.account("Personal")?.transfer(id: giftTransfer)?.amountOut == 10)
        b.store.deleteIncome(gift.id, in: personal.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.income("Gift") == nil)
        #expect(a.account("Personal")?.transfer(id: giftTransfer) == nil)
        #expect(sameContent(a, b))
    }

    /// The pair with a Savings wallet tracking from 0 and the split rule on
    /// into it, synced.
    private func pairWithRule() throws -> (cloud: TestCloud, a: TestDevice, b: TestDevice, savings: PaymentMethod) {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        let savings = PaymentMethod(name: "Savings", symbol: "banknote", isSavings: true)
        a.store.savePaymentMethod(savings, in: personal.id)
        a.store.setBalance(0, ofWallet: savings.id, in: personal.id, at: later(by: -60))
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsWalletID = savings.id
        }
        a.sync(cloud)
        b.sync(cloud)
        return (cloud, a, b, savings)
    }

    /// The device's single savings transfer for the income, or nil when
    /// it has none or more than one; with the Savings balance it makes.
    private func savingsSplit(of title: String, on device: TestDevice, savings: PaymentMethod) -> (Transfer, Decimal?)? {
        guard let account = device.account("Personal"), let income = device.income(title) else { return nil }
        let split = account.transfers.filter { $0.kind == .savings && $0.incomeID == income.id }
        guard split.count == 1, let transfer = split.first, income.savingsTransferID == transfer.id else { return nil }
        let display = device.database.preferences.currencyCode
        let balance = WalletBalances.balance(
            of: savings.id, in: account, display: display,
            converter: CurrencyConverter(displayCurrency: display, rates: nil), calendar: .current
        )
        return (transfer, balance?.amount)
    }

    @Test func aSavingsTransferMadeOnTwoDevicesIsOne() throws {
        let (cloud, a, b, savings) = try pairWithRule()
        let personal = try #require(a.account("Personal"))
        let bank = try #require(a.wallet("Bank Transfer"))
        a.store.saveIncome(Income(title: "Bonus", amount: 500, walletID: bank.id, savingsSkipped: true), in: personal.id)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.income("Bonus")?.savingsSkipped == true)

        // Each device turns Skip This Time off while offline.
        for (device, seconds) in [(a, 10.0), (b, 20.0)] {
            var bonus = try #require(device.income("Bonus"))
            bonus.savingsSkipped = false
            device.store.saveIncome(bonus, in: personal.id, now: later(by: seconds))
        }
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        let bonus = try #require(a.income("Bonus"))
        for device in [a, b] {
            let (transfer, balance) = try #require(savingsSplit(of: "Bonus", on: device, savings: savings))
            #expect(transfer.id == SavingsSplit.transferID(forIncome: bonus.id))
            #expect(transfer.amountOut == 100)
            #expect(balance == 100)
        }
        #expect(cloud.names(of: .transfer).count == 2)
        #expect(sameContent(a, b))
    }

    @Test func anIncomeEditedBeforeItsSavingsTransferArrivesMakesNoSecondOne() throws {
        let (cloud, a, b, savings) = try pairWithRule()
        let personal = try #require(a.account("Personal"))
        let bank = try #require(a.wallet("Bank Transfer"))
        a.store.saveIncome(Income(title: "Bonus", amount: 500, walletID: bank.id), in: personal.id)
        let bonus = try #require(a.income("Bonus"))
        a.sync(cloud)

        // B has the income from one batch of a fetch, not yet its transfer.
        b.pullPartially(cloud, names: [SyncRecordName.make(.income, bonus.id)])
        #expect(b.income("Bonus") != nil)
        #expect(b.account("Personal")?.transfer(id: bonus.savingsTransferID) == nil)
        var onB = try #require(b.income("Bonus"))
        onB.title = "Year-end bonus"
        b.store.saveIncome(onB, in: personal.id, now: later(by: 10))
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            let (transfer, balance) = try #require(savingsSplit(of: "Year-end bonus", on: device, savings: savings))
            #expect(transfer.id == bonus.savingsTransferID)
            #expect(balance == 100)
        }
        #expect(cloud.names(of: .transfer).count == 2)
        #expect(sameContent(a, b))
    }

    @Test func theLaterSplitRuleEditWins() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsPercent = 30
            $0.expensesPercent = 50
            $0.freeMoneyPercent = 20
            $0.updatedAt = later(by: 10)
        }
        b.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsPercent = 10
            $0.expensesPercent = 60
            $0.freeMoneyPercent = 30
            $0.updatedAt = later(by: 20)
        }
        // A reaches iCloud first; B's later edit still wins everywhere.
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            let rule = try #require(device.account("Personal")?.splitRule)
            #expect(rule.savingsPercent == 10)
            #expect(rule.expensesPercent == 60)
        }

        // An earlier edit loses even when it arrives last.
        b.store.updateSplitRule(in: personal.id) {
            $0.savingsPercent = 15
            $0.expensesPercent = 55
            $0.updatedAt = later(by: 40)
        }
        a.store.updateSplitRule(in: personal.id) {
            $0.savingsPercent = 25
            $0.expensesPercent = 45
            $0.updatedAt = later(by: 30)
        }
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        for device in [a, b] {
            #expect(device.account("Personal")?.splitRule.savingsPercent == 15)
        }
        #expect(sameContent(a, b))
    }

    @Test func aDeviceMeetingTheRuleForTheFirstTimeTakesICloudsRule() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        a.sync(cloud)
        // B is set up later from a copy of A as it was now.
        let copy = a.database
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsPercent = 30
            $0.expensesPercent = 50
            $0.freeMoneyPercent = 20
            $0.updatedAt = later(by: 10)
        }
        a.sync(cloud)

        // A new device takes it with the account.
        let fresh = TestDevice()
        fresh.sync(cloud)
        #expect(fresh.account("Personal")?.splitRule == a.account("Personal")?.splitRule)

        // A device that has the account already, and an edit of its own
        // rule it never synced, takes iCloud's rule all the same, though
        // its edit is later.
        let b = TestDevice(copy)
        b.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsPercent = 5
            $0.expensesPercent = 70
            $0.freeMoneyPercent = 25
            $0.updatedAt = later(by: 20)
        }
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b, fresh] {
            #expect(device.account("Personal")?.splitRule.savingsPercent == 30)
        }
        #expect(b.upload().isEmpty)
        #expect(sameContent(a, b))
    }

    @Test func incomeCategoryOrderSyncsAndNewOnesKeepTheirPlace() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        a.store.moveIncomeCategories(in: personal.id, fromOffsets: [0], toOffset: 5)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.account("Personal")?.incomeCategories.map(\.name) == ["Business", "Gifts", "Refunds", "Freelance", "Salary"])

        b.store.saveIncomeCategory(IncomeCategory(name: "Interest", symbol: "percent"), in: personal.id)
        b.sync(cloud)
        a.sync(cloud)
        #expect(a.account("Personal")?.incomeCategories.last?.name == "Interest")
        #expect(sameContent(a, b))
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
    }

    @Test func aWalletDeletedOnOneDeviceLetsGoOfItEverywhere() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        var cash = try #require(a.wallet("Cash"))
        cash.currencyCode = "RWF"
        a.store.savePaymentMethod(cash, in: personal.id)
        a.store.updateSplitRule(in: personal.id) { $0.savingsWalletID = cash.id }
        let bank = try #require(a.wallet("Bank Transfer"))
        a.store.saveTransfer(Transfer(fromWalletID: bank.id, toWalletID: cash.id, amountOut: 10, amountIn: 15_000, note: "Francs"), in: personal.id)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.wallet("Cash")?.currencyCode == "RWF")
        // Made while Cash followed the display currency, it stays in euros.
        #expect(b.transfer("Cash for the week")?.currencyIn == "EUR")
        #expect(b.account("Personal")?.splitRule.savingsWalletID == cash.id)

        a.store.deletePaymentMethod(cash.id, in: personal.id)
        // B, offline, puts a refund into Cash after A deleted it.
        b.store.saveIncome(Income(title: "Refund", amount: 15, walletID: cash.id), in: personal.id, now: later(by: 5))
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)

        for device in [a, b] {
            let account = try #require(device.account("Personal"))
            let display = device.database.preferences.currencyCode
            #expect(device.wallet("Cash") == nil)
            let transfer = try #require(device.transfer("Francs"))
            #expect(transfer.toWalletID == nil)
            // What arrived in Cash stays in Cash's currency.
            #expect(transfer.currencyIn == "RWF")
            #expect(account.effectiveCurrencyIn(of: transfer, display: display) == "RWF")
            #expect(device.transfer("Cash for the week")?.currencyIn == "EUR")
            #expect(account.balanceAdjustments.isEmpty)
            #expect(account.splitRule.savingsWalletID == nil)
            // B's refund keeps working: its wallet reads as none and its
            // currency as the display currency.
            let refund = try #require(device.income("Refund"))
            #expect(account.paymentMethod(id: refund.walletID) == nil)
            #expect(account.effectiveCurrency(of: refund, display: display) == display)
        }
        #expect(cloud.records[SyncRecordName.make(.paymentMethod, cash.id)] == nil)
        #expect(cloud.names(of: .balanceAdjustment).isEmpty)
        #expect(sameContent(a, b))
    }

    @Test func anAccountDeletedElsewhereTakesItsMoneyAlong() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        a.store.deleteAccount(personal.id)
        a.sync(cloud)
        b.sync(cloud)
        #expect(b.account("Personal") == nil)
        #expect(b.income("Salary") == nil)
        #expect(!cloud.records.values.contains { stored in
            (try? SyncRecord(name: "", type: stored.type, payload: stored.payload))?.parent == personal.id
        })
        #expect(cloud.records[SyncRecordName.make(.splitRule, personal.id)] == nil)
        #expect(cloud.records[SyncRecordName.incomeCategoriesOrder(personal.id)] == nil)
        #expect(cloud.names(of: .incomeCategory).isEmpty)
    }

    @Test func moneyThatArrivesBeforeItsAccountWaitsForIt() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let travel = a.store.createAccount(name: "Travel")
        a.store.saveIncome(Income(title: "Per diem", amount: 60, walletID: travel.paymentMethods[2].id), in: travel.id)
        a.store.updateSplitRule(in: travel.id) {
            $0.savingsPercent = 10
            $0.expensesPercent = 60
        }
        a.sync(cloud)

        let b = TestDevice()
        let income = SyncRecordName.make(.income, try #require(a.income("Per diem")).id)
        let rule = SyncRecordName.make(.splitRule, travel.id)
        b.pullPartially(cloud, names: [income, rule])
        #expect(b.income("Per diem") == nil)
        #expect(b.state.parked[income] != nil)
        #expect(b.state.parked[rule] != nil)
        b.sync(cloud)
        #expect(b.income("Per diem") != nil)
        #expect(b.account("Travel")?.splitRule.savingsPercent == 10)
        #expect(b.state.parked.isEmpty)
        #expect(sameContent(a, b))
    }

    @Test func sameNamedWalletsMadeOnTwoDevicesBecomeOneAndEverythingFollows() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        let bank = try #require(a.wallet("Bank Transfer"))
        // Each device makes its own Savings, offline: A's follows the
        // display currency (EUR), B's is in JPY.
        let onA = PaymentMethod(name: "Savings", symbol: "banknote", isSavings: true)
        a.store.savePaymentMethod(onA, in: personal.id)
        a.store.saveTransfer(Transfer(fromWalletID: bank.id, toWalletID: onA.id, amountOut: 40, note: "Put aside on A"), in: personal.id)
        let onB = PaymentMethod(name: "savings", symbol: "building.columns", currencyCode: "JPY", isSavings: true)
        b.store.savePaymentMethod(onB, in: personal.id)
        b.store.setBalance(1000, ofWallet: onB.id, in: personal.id, at: later(by: -60))
        b.store.setBalance(2500, ofWallet: onB.id, in: personal.id)
        b.store.saveIncome(Income(title: "Interest", amount: 20, walletID: onB.id), in: personal.id)
        b.store.saveTransfer(Transfer(fromWalletID: bank.id, toWalletID: onB.id, amountOut: 60, amountIn: 9000, note: "Put aside on B"), in: personal.id)
        b.store.updateSplitRule(in: personal.id) { $0.savingsWalletID = onB.id }

        // A's reaches iCloud first, so it is the one that stays.
        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        for device in [a, b] {
            let account = try #require(device.account("Personal"))
            #expect(account.paymentMethods.filter { $0.name.lowercased() == "savings" }.map(\.id) == [onA.id])
            let interest = try #require(device.income("Interest"))
            #expect(interest.walletID == onA.id)
            // Typed in JPY, it stays in JPY.
            #expect(interest.currencyCode == "JPY")
            let fromB = try #require(device.transfer("Put aside on B"))
            #expect(fromB.toWalletID == onA.id)
            #expect(fromB.currencyIn == "JPY")
            #expect(fromB.currencyOut == nil)
            let fromA = try #require(device.transfer("Put aside on A"))
            #expect(fromA.toWalletID == onA.id)
            // Made while A's Savings followed EUR, it stays in EUR.
            #expect(fromA.currencyIn == "EUR")
            #expect(account.balanceAdjustments.filter { $0.balance == 2500 }.map(\.walletID) == [onA.id])
            // Stated in JPY, it stays in JPY.
            #expect(account.balanceAdjustments.first { $0.balance == 2500 }?.currencyCode == "JPY")
            #expect(!account.balanceAdjustments.contains { $0.walletID == onB.id })
            #expect(account.splitRule.savingsWalletID == onA.id)
            // A's Savings was not tracking, so it takes B's balance and its
            // currency: 2,500 stated, then 20 and 9,000 in.
            let savings = try #require(account.paymentMethod(id: onA.id))
            #expect(savings.currencyCode == "JPY")
            #expect(savings.isTracking && savings.openingBalance == 1000)
            let display = device.database.preferences.currencyCode
            let balance = WalletBalances.balance(
                of: onA.id, in: account, display: display,
                converter: CurrencyConverter(displayCurrency: display, rates: nil), calendar: .current
            )
            #expect(balance == WalletBalance(amount: 11_520, unconverted: 0))
        }
        #expect(cloud.names(of: .paymentMethod).count == 6)
        #expect(cloud.records[SyncRecordName.make(.paymentMethod, onB.id)] == nil)
        #expect(sameContent(a, b))
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
    }

    @Test func sameNamedIncomeCategoriesBecomeOne() throws {
        let (cloud, a, b) = try pair()
        let personal = try #require(a.account("Personal"))
        let bank = try #require(a.wallet("Bank Transfer"))
        let onA = IncomeCategory(name: "Rent", symbol: "house.fill")
        a.store.saveIncomeCategory(onA, in: personal.id)
        a.store.saveIncome(Income(title: "Flat", amount: 700, categoryID: onA.id, walletID: bank.id), in: personal.id)
        let onB = IncomeCategory(name: "rent", symbol: "key.fill")
        b.store.saveIncomeCategory(onB, in: personal.id)
        b.store.saveIncome(Income(title: "Garage", amount: 90, categoryID: onB.id, walletID: bank.id), in: personal.id)

        a.sync(cloud)
        b.sync(cloud)
        a.sync(cloud)
        b.sync(cloud)
        for device in [a, b] {
            let account = try #require(device.account("Personal"))
            let rents = account.incomeCategories.filter { $0.name.lowercased() == "rent" }
            #expect(rents.map(\.id) == [onA.id])
            #expect(device.income("Flat")?.categoryID == onA.id)
            #expect(device.income("Garage")?.categoryID == onA.id)
        }
        #expect(cloud.names(of: .incomeCategory).count == 6)
        #expect(sameContent(a, b))
    }
}

/// A device that already has money meeting iCloud for the first time.
@MainActor
struct SyncMoneyFirstSyncTests {
    @Test func aSecondDevicesAccountBringsItsMoneyAlong() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        a.store.updatePreferences { $0.currencyCode = "EUR" }
        let personal = a.store.createAccount(name: "Personal")
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.savingsPercent = 30
            $0.expensesPercent = 50
            $0.freeMoneyPercent = 20
        }
        a.sync(cloud)

        // B was used offline first: its own Personal, its Cash in RWF and
        // tracking a balance, a wallet A does not have, income, a transfer,
        // an income category of its own and its own split rule.
        let b = TestDevice()
        let own = b.store.createAccount(name: "personal")
        var ownCash = own.paymentMethods[2]
        ownCash.currencyCode = "RWF"
        b.store.savePaymentMethod(ownCash, in: own.id)
        let momo = PaymentMethod(name: "MoMo", symbol: "iphone")
        b.store.savePaymentMethod(momo, in: own.id)
        b.store.setBalance(10_000, ofWallet: ownCash.id, in: own.id, at: later(by: -60))
        b.store.setBalance(12_000, ofWallet: ownCash.id, in: own.id)
        b.store.saveIncome(Income(title: "Wages", amount: 50_000, categoryID: own.incomeCategories[0].id, walletID: ownCash.id), in: own.id)
        b.store.saveTransfer(Transfer(fromWalletID: ownCash.id, toWalletID: momo.id, amountOut: 3000, note: "Top up"), in: own.id)
        b.store.saveIncomeCategory(IncomeCategory(name: "Tips", symbol: "dollarsign"), in: own.id)
        b.store.updateSplitRule(in: own.id) {
            $0.isEnabled = true
            $0.savingsPercent = 10
            $0.expensesPercent = 70
            $0.freeMoneyPercent = 20
            $0.savingsWalletID = momo.id
        }

        b.sync(cloud)
        a.sync(cloud)
        let cashID = personal.paymentMethods[2].id
        for device in [a, b] {
            #expect(device.database.accounts.count == 1)
            let account = try #require(device.account("Personal"))
            #expect(account.id == personal.id)
            #expect(account.paymentMethods.first { $0.name == "Cash" }?.id == cashID)
            #expect(account.paymentMethods.last?.id == momo.id)
            #expect(account.incomeCategories.map(\.name) == ["Salary", "Business", "Gifts", "Refunds", "Tips"])
            let wages = try #require(device.income("Wages"))
            #expect(wages.walletID == cashID)
            #expect(wages.categoryID == personal.incomeCategories[0].id)
            // Typed in RWF, it stays in RWF.
            #expect(wages.currencyCode == "RWF")
            let topUp = try #require(device.transfer("Top up"))
            #expect(topUp.fromWalletID == cashID)
            #expect(topUp.toWalletID == momo.id)
            #expect(topUp.currencyOut == "RWF")
            #expect(account.balanceAdjustments.map(\.walletID) == [cashID])
            #expect(account.balanceAdjustments.map(\.currencyCode) == ["RWF"])
            // A's Cash was not tracking, so it takes B's balance and its
            // currency: 12,000 stated, then 50,000 in and 3,000 out.
            let cash = try #require(account.paymentMethod(id: cashID))
            #expect(cash.currencyCode == "RWF")
            #expect(cash.isTracking && cash.openingBalance == 10_000)
            let balance = WalletBalances.balance(
                of: cashID, in: account, display: "EUR",
                converter: CurrencyConverter(displayCurrency: "EUR", rates: nil), calendar: .current
            )
            #expect(balance == WalletBalance(amount: 59_000, unconverted: 0))
            // The account's own rule stays.
            #expect(account.splitRule.savingsPercent == 30)
            #expect(account.splitRule.savingsWalletID == nil)
        }
        #expect(b.database.preferences.selectedAccountID == personal.id)
        #expect(cloud.names(of: .account).count == 1)
        #expect(cloud.names(of: .incomeCategory).count == 5)
        #expect(cloud.names(of: .splitRule).count == 1)
        #expect(sameContent(a, b))
    }

    /// The person's flow: B used offline first, with its own Personal and
    /// a balance in Cash, meets A's Personal.
    @Test func aBalanceStatedOnTheSecondDeviceSurvivesTheMerge() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        let cashID = personal.paymentMethods[2].id
        // A's Bank Transfer tracks a balance too, stated earlier than B's.
        let bankID = personal.paymentMethods[3].id
        a.store.setBalance(100, ofWallet: bankID, in: personal.id, at: later(by: -120))
        a.sync(cloud)

        let b = TestDevice()
        let own = b.store.createAccount(name: "Personal")
        b.store.setBalance(300, ofWallet: own.paymentMethods[2].id, in: own.id, at: later(by: -60))
        b.store.setBalance(700, ofWallet: own.paymentMethods[3].id, in: own.id, at: later(by: -60))
        b.store.saveExpense(Expense(title: "Coffee", amount: 4, paymentMethodID: own.paymentMethods[2].id), in: own.id)
        b.store.saveExpense(Expense(title: "Books", amount: 30, paymentMethodID: own.paymentMethods[3].id), in: own.id)
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            let account = try #require(device.account("Personal"))
            let display = device.database.preferences.currencyCode
            func balance(_ id: UUID) -> WalletBalance? {
                WalletBalances.balance(
                    of: id, in: account, display: display,
                    converter: CurrencyConverter(displayCurrency: display, rates: nil), calendar: .current
                )
            }
            // A's Cash was not tracking: it takes B's 300.
            #expect(balance(cashID) == WalletBalance(amount: 296, unconverted: 0))
            #expect(account.paymentMethod(id: cashID)?.currencyCode == nil)
            // A's Bank Transfer was: B's later 700 is a stated balance of it.
            #expect(balance(bankID) == WalletBalance(amount: 670, unconverted: 0))
            #expect(account.paymentMethod(id: bankID)?.openingBalance == 100)
            #expect(account.balanceAdjustments.map(\.balance) == [700])
        }
        #expect(cloud.names(of: .balanceAdjustment).count == 1)
        #expect(sameContent(a, b))
        #expect(a.upload().isEmpty)
        #expect(b.upload().isEmpty)
    }

    @Test func onlyAnAccountWithNothingButTheBuiltInLabelsGivesWay() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        a.store.createAccount(name: "Personal")
        a.sync(cloud)

        // Set up minutes ago with the built-in labels, income categories
        // included, and nothing else: a placeholder.
        let bare = TestDevice()
        bare.store.createAccount(name: "Main")
        bare.sync(cloud)
        #expect(bare.database.accounts.map(\.name) == ["Personal"])

        // Set up minutes ago with only a wallet's balance in it.
        let balance = TestDevice()
        let main = balance.store.createAccount(name: "Main")
        balance.store.setBalance(40, ofWallet: main.paymentMethods[2].id, in: main.id)
        balance.sync(cloud)
        #expect(Set(balance.database.accounts.map(\.name)) == ["Personal", "Main"])

        // Set up minutes ago with only an income in it.
        let income = TestDevice()
        let work = income.store.createAccount(name: "Work")
        income.store.saveIncome(Income(title: "Advance", amount: 100), in: work.id)
        income.sync(cloud)
        #expect(Set(income.database.accounts.map(\.name)) == ["Personal", "Main", "Work"])

        // Set up minutes ago with only an income category of its own.
        let label = TestDevice()
        let side = label.store.createAccount(name: "Side")
        label.store.saveIncomeCategory(IncomeCategory(name: "Royalties", symbol: "music.note"), in: side.id)
        label.sync(cloud)
        #expect(Set(label.database.accounts.map(\.name)) == ["Personal", "Main", "Work", "Side"])
    }
}

/// Later and earlier versions of Keaser meeting the money records.
@MainActor
struct SyncMoneyToleranceTests {
    /// A has "Personal" with a salary, a transfer and Cash tracking a
    /// balance, synced.
    private func device() -> (TestCloud, TestDevice, Account) {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        a.store.setBalance(50, ofWallet: personal.paymentMethods[2].id, in: personal.id)
        a.store.saveIncome(Income(title: "Salary", amount: 2000, walletID: personal.paymentMethods[3].id), in: personal.id)
        a.store.saveTransfer(Transfer(fromWalletID: personal.paymentMethods[3].id, toWalletID: personal.paymentMethods[2].id, amountOut: 100, note: "Cash"), in: personal.id)
        a.sync(cloud)
        return (cloud, a, personal)
    }

    private func stored(_ name: String, _ type: SyncRecordType, in cloud: TestCloud) throws -> SyncRecord {
        try SyncRecord(name: name, type: type, payload: try #require(cloud.records[name]).payload)
    }

    @Test func moneyRecordsALaterVersionWritesAreKeptNotApplied() throws {
        let (cloud, a, personal) = device()
        let salary = try #require(a.income("Salary"))
        let incomeName = SyncRecordName.make(.income, salary.id)
        var future = try stored(incomeName, .income, in: cloud)
        future.readerVersion = SyncSchema.readerVersion + 1
        future.body["amount"] = .object(["value": .number(2000), "currency": .string("EUR")])
        cloud.put(name: incomeName, type: .income, payload: future.payload)
        let ruleName = SyncRecordName.make(.splitRule, personal.id)
        var rule = try stored(ruleName, .splitRule, in: cloud)
        rule.readerVersion = SyncSchema.readerVersion + 1
        rule.body["savingsPercent"] = .string("a fifth")
        cloud.put(name: ruleName, type: .splitRule, payload: rule.payload)
        // A kind of money record this version does not have at all.
        let budget = SyncRecord(
            name: "Budget.\(UUID().uuidString)", type: SyncRecordType("Budget"), modifiedAt: .now,
            parent: personal.id, body: ["limit": .number(500)]
        )
        cloud.put(name: budget.name, type: budget.type, payload: budget.payload)

        let before = a.database
        a.sync(cloud)
        #expect(a.database == before)
        #expect(a.state.parked[incomeName] != nil)
        #expect(a.state.parked[ruleName] != nil)
        #expect(a.state.parked[budget.name] != nil)

        // Edits here never overwrite them.
        var edited = try #require(a.income("Salary"))
        edited.title = "Edited on an old version"
        a.store.saveIncome(edited, in: personal.id)
        a.store.updateSplitRule(in: personal.id) { $0.isEnabled = true }
        a.sync(cloud)
        a.sync(cloud)
        #expect(cloud.records[incomeName]?.payload == future.payload)
        #expect(cloud.records[ruleName]?.payload == rule.payload)
        #expect(cloud.records[budget.name]?.payload == budget.payload)
    }

    /// A later version added a field to each kind of money record; this one
    /// edits them and sends them back with the field untouched.
    @Test func fieldsALaterVersionAddsSurviveAnEditHere() throws {
        let (cloud, a, personal) = device()
        let cash = try #require(a.wallet("Cash"))
        let names: [(String, SyncRecordType)] = [
            (SyncRecordName.make(.income, try #require(a.income("Salary")).id), .income),
            (SyncRecordName.make(.transfer, try #require(a.transfer("Cash")).id), .transfer),
            (SyncRecordName.make(.splitRule, personal.id), .splitRule),
            (SyncRecordName.make(.paymentMethod, cash.id), .paymentMethod),
            (SyncRecordName.make(.incomeCategory, personal.incomeCategories[0].id), .incomeCategory),
        ]
        let newer = later(by: 5)
        for (name, type) in names {
            var record = try stored(name, type, in: cloud)
            record.body["tags"] = .array([.string("later"), .null])
            record.modifiedAt = newer
            record.body["updatedAt"] = .number(Decimal(newer.timeIntervalSinceReferenceDate))
            cloud.put(name: name, type: type, payload: record.payload)
        }
        a.sync(cloud)
        #expect(a.upload().isEmpty)

        let edit = later(by: 10)
        var salary = try #require(a.income("Salary"))
        salary.amount = 2500
        a.store.saveIncome(salary, in: personal.id, now: edit)
        var transfer = try #require(a.transfer("Cash"))
        transfer.note = "Weekly cash"
        a.store.saveTransfer(transfer, in: personal.id, now: edit)
        a.store.updateSplitRule(in: personal.id) {
            $0.isEnabled = true
            $0.updatedAt = edit
        }
        var wallet = try #require(a.wallet("Cash"))
        wallet.currencyCode = "EUR"
        wallet.updatedAt = edit
        a.store.savePaymentMethod(wallet, in: personal.id)
        var salaryCategory = personal.incomeCategories[0]
        salaryCategory.symbol = "banknote"
        salaryCategory.updatedAt = edit
        a.store.saveIncomeCategory(salaryCategory, in: personal.id)
        a.sync(cloud)
        #expect(a.upload().isEmpty)

        for (name, _) in names {
            let body = try #require(cloud.body(of: name))
            #expect(body["tags"] == .array([.string("later"), .null]), "\(name)")
        }
        #expect(cloud.body(of: names[0].0)?["amount"] == .number(2500))
        #expect(cloud.body(of: names[1].0)?["note"] == .string("Weekly cash"))
        #expect(cloud.body(of: names[2].0)?["isEnabled"] == .bool(true))
        #expect(cloud.body(of: names[3].0)?["currencyCode"] == .string("EUR"))
        #expect(cloud.body(of: names[4].0)?["symbol"] == .string("banknote"))
    }

    /// A build from before wallets edits a payment method: it sends back
    /// the wallet fields it does not know as they were, so they survive.
    @Test func anOlderBuildsEditKeepsTheWalletFieldsItDoesNotKnow() throws {
        let (cloud, a, personal) = device()
        var cash = try #require(a.wallet("Cash"))
        cash.currencyCode = "EUR"
        cash.creditLimit = 300
        a.store.savePaymentMethod(cash, in: personal.id)
        a.sync(cloud)
        let name = SyncRecordName.make(.paymentMethod, cash.id)
        let current = try stored(name, .paymentMethod, in: cloud)

        // What such a build knows of a payment method, and keeps aside.
        var old = current
        old.body = current.body.filter { ["id", "name", "symbol", "updatedAt"].contains($0.key) }
        let extras = SyncPlan.extras(of: current, canonical: old)
        old.body["symbol"] = .string("dollarsign.circle")
        old.modifiedAt = later(by: 5)
        old.body["updatedAt"] = .number(Decimal(old.modifiedAt.timeIntervalSinceReferenceDate))
        cloud.put(name: name, type: .paymentMethod, payload: SyncPlan.outgoing(old, extras: extras).payload)

        let b = TestDevice()
        b.sync(cloud)
        a.sync(cloud)
        for device in [a, b] {
            let wallet = try #require(device.wallet("Cash"))
            #expect(wallet.symbol == "dollarsign.circle")
            #expect(wallet.kind == .cash)
            #expect(wallet.currencyCode == "EUR")
            #expect(wallet.creditLimit == 300)
            #expect(wallet.isTracking)
            #expect(wallet.openingBalance == 50)
        }

        // One such a build made reads as a wallet with the kind its name
        // suggests, not tracking a balance.
        let momo = UUID()
        let made = later(by: 6)
        let plain = SyncRecord(
            name: SyncRecordName.make(.paymentMethod, momo), type: .paymentMethod, modifiedAt: made, parent: personal.id,
            body: [
                "id": .string(momo.uuidString), "name": .string("MoMo"), "symbol": .string("iphone"),
                "updatedAt": .number(Decimal(made.timeIntervalSinceReferenceDate)),
            ]
        )
        cloud.put(name: plain.name, type: plain.type, payload: plain.payload)
        b.sync(cloud)
        let wallet = try #require(b.wallet("MoMo"))
        #expect(wallet.kind == .mobileMoney)
        #expect(!wallet.isTracking)
        #expect(wallet.currencyCode == nil)
        #expect(b.upload().isEmpty)
    }
}

/// What a wallet that merges into another leaves to it
/// (`LabelRedirects.carryOverBalances`).
struct SyncWalletMergeTests {
    private let since = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private let now = Date(timeIntervalSinceReferenceDate: 780_100_000)
    private let old = Date(timeIntervalSinceReferenceDate: 770_000_000)

    /// `gone` merges into `stays` in an account holding `stays` and the
    /// expenses, with the display currency EUR.
    private func merge(_ gone: PaymentMethod, into stays: PaymentMethod, expenses: [Expense] = []) -> Account {
        var redirects = LabelRedirects()
        redirects.merge(gone, into: stays, display: "EUR")
        var account = Account(name: "Personal", paymentMethods: [stays], expenses: expenses)
        redirects.apply(to: &account, display: "EUR", now: now)
        return account
    }

    private func wallet(_ name: String = "Cash", currency: String? = nil, since: Date? = nil, opening: Decimal = 0) -> PaymentMethod {
        PaymentMethod(name: name, symbol: "banknote.fill", updatedAt: old, currencyCode: currency, trackingSince: since, openingBalance: opening)
    }

    @Test func aWalletThatWasNotTrackingLeavesNoBalance() {
        let stays = wallet()
        let account = merge(wallet(), into: stays)
        #expect(account.paymentMethods == [stays])
        #expect(account.balanceAdjustments.isEmpty)
    }

    @Test func oneNotTrackingTakesTheBalanceInTheSameCurrency() throws {
        let account = merge(wallet(currency: "EUR", since: since, opening: 300), into: wallet())
        let stays = try #require(account.paymentMethods.first)
        #expect(stays.trackingSince == since && stays.openingBalance == 300)
        // Its currency followed the display currency, which is EUR anyway.
        #expect(stays.currencyCode == "EUR")
        #expect(stays.updatedAt == now)
        #expect(account.balanceAdjustments.isEmpty)
    }

    @Test func oneWithoutACurrencyTakesTheOthersAndKeepsWhatItHeld() throws {
        let stays = wallet()
        let lunch = Expense(title: "Lunch", amount: 12, paymentMethodID: stays.id, createdAt: old, updatedAt: old)
        let account = merge(wallet(currency: "RWF", since: since, opening: 10_000), into: stays, expenses: [lunch])
        let merged = try #require(account.paymentMethods.first)
        #expect(merged.currencyCode == "RWF")
        #expect(merged.trackingSince == since && merged.openingBalance == 10_000)
        // Spent while it followed EUR: still EUR.
        #expect(account.expenses.first?.currencyCode == "EUR")
        #expect(account.expenses.first?.updatedAt == now)
    }

    @Test func oneInAnotherCurrencyOfItsOwnGetsTheBalanceAsAnAdjustment() throws {
        let gone = wallet(currency: "RWF", since: since, opening: 10_000)
        let account = merge(gone, into: wallet(currency: "USD"))
        let stays = try #require(account.paymentMethods.first)
        #expect(stays.currencyCode == "USD")
        #expect(stays.trackingSince == since && stays.openingBalance == 0)
        let adjustment = try #require(account.balanceAdjustments.first)
        #expect(adjustment.walletID == stays.id)
        #expect(adjustment.balance == 10_000 && adjustment.currencyCode == "RWF")
        #expect(adjustment.date == since)
        // It wins the tie with the opening: 10,000 RWF at 1400 RWF to the
        // dollar; without rates it is passed over and counted.
        let table = ExchangeRates(base: "USD", rates: ["RWF": 1400], date: since, fetchedAt: since)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func balance(_ rates: ExchangeRates?) -> WalletBalance? {
            WalletBalances.balance(
                of: stays.id, in: account, display: "EUR",
                converter: CurrencyConverter(displayCurrency: "EUR", rates: rates), calendar: calendar
            )
        }
        #expect(balance(table) == WalletBalance(amount: Decimal(string: "7.14")!, unconverted: 0))
        #expect(balance(nil) == WalletBalance(amount: 0, unconverted: 1))
    }

    @Test func oneTrackingAlreadyGetsTheBalanceAsAnAdjustmentOnce() throws {
        let gone = wallet(since: since, opening: 300)
        let stays = wallet(since: old, opening: 100)
        var account = merge(gone, into: stays)
        #expect(account.paymentMethods.first?.trackingSince == old)
        #expect(account.paymentMethods.first?.openingBalance == 100)
        let adjustment = try #require(account.balanceAdjustments.first)
        #expect(adjustment.balance == 300 && adjustment.currencyCode == "EUR" && adjustment.date == since)
        // The same merge on another device makes the same record.
        #expect(adjustment.id == merge(gone, into: stays).balanceAdjustments.first?.id)
        var redirects = LabelRedirects()
        redirects.merge(gone, into: stays, display: "EUR")
        redirects.apply(to: &account, display: "EUR", now: now)
        #expect(account.balanceAdjustments.count == 1)
    }

    @Test func itIsASavingsWalletWhenEitherWasAndTakesALimit() throws {
        var gone = wallet()
        gone.isSavings = true
        gone.creditLimit = 500
        let account = merge(gone, into: wallet())
        let stays = try #require(account.paymentMethods.first)
        #expect(stays.isSavings && stays.creditLimit == 500)
        // A limit in another currency is not taken.
        gone.currencyCode = "USD"
        #expect(merge(gone, into: wallet()).paymentMethods.first?.creditLimit == nil)
    }
}
