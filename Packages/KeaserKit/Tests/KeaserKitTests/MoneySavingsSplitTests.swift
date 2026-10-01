import Foundation
import Testing
@testable import KeaserKit

/// The split rule's Savings transfer for an income (`SavingsSplit`), rule by
/// rule.
struct MoneySavingsSplitTests {
    private let day = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private let now = Date(timeIntervalSinceReferenceDate: 780_100_000)
    /// Every `income()` is the same income, saved again.
    private let incomeID = UUID(uuidString: "E1B2C3D4-0002-4000-8000-000000000002")!

    private let cash = PaymentMethod(name: "Cash", symbol: "banknote.fill")
    private let bank = PaymentMethod(name: "Bank Account", symbol: "building.columns.fill")
    private let savings = PaymentMethod(name: "Savings", symbol: "banknote.fill", kind: .bank, isSavings: true)
    private let dollars = PaymentMethod(name: "Dollars", symbol: "dollarsign", kind: .bank, currencyCode: "USD", isSavings: true)

    private var account: Account {
        Account(name: "Personal", paymentMethods: [cash, bank, savings, dollars])
    }

    private var rule: SplitRule {
        SplitRule(isEnabled: true, savingsWalletID: savings.id)
    }

    /// `stored`: the income as the account has it; nil, a new income.
    private func split(
        _ income: Income,
        stored: Income? = nil,
        existing: Transfer? = nil,
        rule: SplitRule? = nil,
        rates: ExchangeRates? = nil
    ) -> (transfer: Transfer?, percent: Int?) {
        SavingsSplit.transfer(
            for: income, stored: stored, existing: existing, in: account, rule: rule ?? self.rule, display: "RWF",
            converter: CurrencyConverter(displayCurrency: "RWF", rates: rates), now: now
        )
    }

    private func income(_ amount: Decimal = 200_000, into wallet: UUID? = nil, percent: Int? = nil) -> Income {
        Income(id: incomeID, title: "Salary", amount: amount, walletID: wallet ?? cash.id, date: day, createdAt: day, updatedAt: day, savingsPercent: percent)
    }

    @Test func rule1NoneWhenSkippedOrIntoNoWallet() {
        var skipped = income()
        skipped.savingsSkipped = true
        #expect(split(skipped).transfer == nil)
        var walletless = income()
        walletless.walletID = nil
        let result = split(walletless)
        #expect(result.transfer == nil && result.percent == nil)
        // A wallet the account no longer has (deleted on another device)
        // reads as none.
        var gone = income()
        gone.walletID = UUID()
        #expect(split(gone).transfer == nil)
    }

    @Test func rule2TheIncomesOwnPercentWinsOverTheRule() {
        #expect(split(income()).percent == 20)
        #expect(split(income(percent: 10)).percent == 10)
        #expect(split(income(percent: 10)).transfer?.amountOut == 20_000)
        // The rule switched off or invalid splits only incomes that already
        // have their percentage.
        var off = rule
        off.isEnabled = false
        #expect(split(income(), rule: off).transfer == nil)
        #expect(split(income(percent: 25), rule: off).transfer?.amountOut == 50_000)
        var invalid = rule
        invalid.savingsPercent = 40
        #expect(split(income(), rule: invalid).transfer == nil)
        #expect(split(income(percent: 15), rule: invalid).percent == 15)
        // 0 is none, on the income or the rule.
        #expect(split(income(percent: 0)).transfer == nil)
        let zero = SplitRule(isEnabled: true, savingsPercent: 0, expensesPercent: 70, freeMoneyPercent: 30, savingsWalletID: savings.id)
        #expect(split(income(), rule: zero).transfer == nil)
    }

    @Test func rule2TheRuleSplitsOnlyANewOrUnskippedIncome() {
        // Logged without a split (the rule was off): saved again with the
        // rule on, it stays without one.
        let logged = income()
        #expect(split(logged, stored: logged).transfer == nil)
        var bigger = logged
        bigger.amount = 300_000
        #expect(split(bigger, stored: logged).transfer == nil)
        // Its Skip This Time turned off: the rule splits it.
        var skipped = logged
        skipped.savingsSkipped = true
        #expect(split(logged, stored: skipped).percent == 20)
        // Its own percentage splits it either way; the stored one counts
        // when the copy saved has none.
        #expect(split(income(percent: 10), stored: logged).percent == 10)
        #expect(split(logged, stored: income(percent: 10)).percent == 10)
        // 0 on the copy saved takes the split away.
        #expect(split(income(percent: 0), stored: income(percent: 10)).transfer == nil)
    }

    @Test func rule3ItGoesToAnotherWalletOfTheAccount() {
        // The existing transfer's wallet wins over the rule's.
        let existing = Transfer(id: UUID(), kind: .savings, fromWalletID: cash.id, toWalletID: bank.id, amountOut: 1)
        #expect(split(income(), existing: existing).transfer?.toWalletID == bank.id)
        // Its wallet deleted since: it stays as it is, never moved to the
        // rule's wallet.
        var orphan = existing
        orphan.toWalletID = nil
        #expect(split(income(), existing: orphan).transfer == orphan)
        // Into the savings wallet itself now: none.
        #expect(split(income(into: bank.id), existing: existing).transfer == nil)
        // No savings wallet, one the account lacks, or the income's own: none.
        var noWallet = rule
        noWallet.savingsWalletID = nil
        #expect(split(income(), rule: noWallet).transfer == nil)
        var missing = rule
        missing.savingsWalletID = UUID()
        #expect(split(income(), rule: missing).transfer == nil)
        #expect(split(income(into: savings.id)).transfer == nil)
    }

    @Test func rule4TheAmountIsRoundedToTheIncomesCurrency() {
        #expect(split(income(1_001, percent: 15)).transfer?.amountOut == 150)
        #expect(split(income(2)).transfer == nil) // 0.4 rounds to nothing
        #expect(split(income(0)).transfer == nil)
        // A dollar income into the savings wallet in the display currency.
        let dollarIncome = Income(title: "Pay", amount: Decimal(string: "33.33")!, walletID: dollars.id, date: day)
        let table = ExchangeRates(base: "USD", rates: ["RWF": 1400], date: day, fetchedAt: day)
        let transfer = split(dollarIncome, rates: table).transfer
        #expect(transfer?.amountOut == Decimal(string: "6.67"))
        #expect(transfer?.amountIn == 9_338)
    }

    @Test func rule5WhatArrivesIsInTheSavingsWalletsCurrency() throws {
        var toDollars = rule
        toDollars.savingsWalletID = dollars.id
        let table = ExchangeRates(base: "USD", rates: ["RWF": 1400], date: day, fetchedAt: day)
        let transfer = split(income(280_000), rule: toDollars, rates: table).transfer
        #expect(transfer?.amountOut == 56_000)
        #expect(transfer?.amountIn == 40)
        // No rates: it cannot be converted, so none.
        let result = split(income(280_000), rule: toDollars)
        #expect(result.transfer == nil && result.percent == nil)
        // Within one currency, what arrives is what left.
        let same = try #require(split(income()).transfer)
        #expect(same.amountIn == same.amountOut)
    }

    @Test func rule5AForeignIncomesSavedRateValuesBothSides() throws {
        // 50 EUR into a wallet in the display currency, typed at 1500 RWF
        // while the table says 1450: what arrives is worth what left at
        // the income's rate, not today's.
        var euros = Income(title: "Refund", amount: 50, currencyCode: "EUR", walletID: cash.id, date: day)
        euros.rate = ExchangeRate(rate: 1500, currencyCode: "RWF", date: day, isTyped: true)
        let table = ExchangeRates(base: "EUR", rates: ["RWF": 1450], date: day, fetchedAt: day)
        let transfer = try #require(split(euros, rates: table).transfer)
        #expect(transfer.amountOut == 10 && transfer.currencyOut == "EUR")
        #expect(transfer.amountIn == 15_000)
        #expect(transfer.rate == euros.rate)
        // Without a table the saved rate alone is enough.
        #expect(split(euros).transfer?.amountIn == 15_000)
    }

    @Test func rule6ANewTransferIsMadeAndAnExistingOneKeepsItsIdentity() throws {
        var source = income()
        source.rate = ExchangeRate(rate: 1, currencyCode: "RWF", date: day)
        let made = try #require(split(source).transfer)
        // Its ID comes from the income's alone, the same on every device.
        #expect(made.id == SavingsSplit.transferID(forIncome: incomeID))
        #expect(made.id.uuidString == "AB83AC43-A540-8DE1-966A-C17749E1985C")
        #expect(SavingsSplit.transferID(forIncome: UUID()) != made.id)
        #expect(made.kind == .savings)
        #expect(made.fromWalletID == cash.id && made.toWalletID == savings.id)
        #expect(made.date == day && made.incomeID == source.id)
        #expect(made.currencyOut == nil && made.currencyIn == nil)
        #expect(made.createdAt == now && made.updatedAt == now)
        #expect(made.rate == source.rate)
        #expect(made.note.isEmpty)

        let earlier = Date(timeIntervalSinceReferenceDate: 779_000_000)
        let existing = Transfer(
            id: UUID(), kind: .savings, fromWalletID: cash.id, toWalletID: savings.id, amountOut: 1,
            note: "Rainy day", incomeID: source.id, createdAt: earlier, updatedAt: earlier
        )
        let updated = try #require(split(source, existing: existing).transfer)
        #expect(updated.id == existing.id)
        #expect(updated.createdAt == earlier && updated.updatedAt == now)
        #expect(updated.note == "Rainy day")
        #expect(updated.amountOut == 40_000)
    }

    @Test func anIncomeInAnotherCurrencyThanItsWalletKeepsItsCurrency() throws {
        // Logged in EUR into a wallet now in the display currency.
        let euros = Income(title: "Refund", amount: 50, currencyCode: "EUR", walletID: cash.id, date: day)
        let table = ExchangeRates(base: "EUR", rates: ["RWF": 1500], date: day, fetchedAt: day)
        let transfer = try #require(split(euros, rates: table).transfer)
        #expect(transfer.amountOut == 10)
        #expect(transfer.currencyOut == "EUR")
        #expect(transfer.amountIn == 15_000)
        #expect(account.effectiveCurrencyOut(of: transfer, display: "RWF") == "EUR")
    }

    // MARK: An existing transfer

    @Test func anExistingTransferChangesOnlyWithWhatTheIncomeChanged() throws {
        var toDollars = rule
        toDollars.savingsWalletID = dollars.id
        let made = try #require(split(income(280_000), rule: toDollars, rates: table(1400)).transfer)
        #expect(made.amountIn == 40)

        // Saved again unchanged, under another table or none: as it was.
        #expect(split(income(280_000, percent: 20), existing: made, rule: toDollars, rates: table(1500)).transfer == made)
        #expect(split(income(280_000, percent: 20), existing: made, rule: toDollars).transfer == made)
        // The rule switched off since changes nothing either.
        var off = toDollars
        off.isEnabled = false
        #expect(split(income(280_000, percent: 20), existing: made, rule: off).transfer == made)
        // A new date moves it, and only that.
        var moved = income(280_000, percent: 20)
        moved.date = now
        let redated = try #require(split(moved, existing: made, rule: toDollars).transfer)
        #expect(redated.date == now && redated.amountIn == 40 && redated.updatedAt == now)

        // A new amount converts again, at today's rates.
        let raised = try #require(split(income(300_000, percent: 20), existing: made, rule: toDollars, rates: table(1500)).transfer)
        #expect(raised.id == made.id)
        #expect(raised.amountOut == 60_000 && raised.amountIn == 40)
        // Without rates it cannot, so the transfer stays as it was.
        let offline = split(income(300_000, percent: 20), existing: made, rule: toDollars)
        #expect(offline.transfer == made && offline.percent == 20)
    }

    @Test func aTransferWhoseWalletWasDeletedIsKeptAsItIs() throws {
        let made = try #require(split(income()).transfer)
        // The savings wallet deleted: the transfer lost it, as did the rule.
        var lostTarget = made
        lostTarget.toWalletID = nil
        var noRule = rule
        noRule.savingsWalletID = nil
        let kept = split(income(percent: 20), existing: lostTarget, rule: noRule)
        #expect(kept.transfer == lostTarget && kept.percent == 20)
        // With a new savings wallet picked since, it still stays where it went.
        var newWallet = rule
        newWallet.savingsWalletID = bank.id
        #expect(split(income(percent: 20), existing: lostTarget, rule: newWallet).transfer == lostTarget)

        // The income's wallet deleted: both lost it.
        var lostSource = made
        lostSource.fromWalletID = nil
        var walletless = income(percent: 20)
        walletless.walletID = nil
        #expect(split(walletless, existing: lostSource).transfer == lostSource)
        // Taken out of a wallet that is still there, it moves nothing.
        #expect(split(walletless, existing: made).transfer == nil)
        // Skipped, it goes whatever became of its wallets.
        var skipped = walletless
        skipped.savingsSkipped = true
        #expect(split(skipped, existing: lostSource).transfer == nil)
    }

    private func table(_ rwf: Decimal) -> ExchangeRates {
        ExchangeRates(base: "USD", rates: ["RWF": rwf], date: day, fetchedAt: day)
    }
}
