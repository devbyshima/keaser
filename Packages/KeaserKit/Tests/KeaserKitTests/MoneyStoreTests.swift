import Foundation
import Testing
@testable import KeaserKit

/// `KeaserStore`'s income, transfer, balance and split rule edits: what each
/// changes, announces and stamps, and what deleting cleans up.
@MainActor
struct MoneyStoreTests {
    private let then = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private let later = Date(timeIntervalSinceReferenceDate: 780_000_600)

    /// Personal with its built-in wallets plus a Savings wallet, and the
    /// split rule on into it.
    private func storeWithRule() -> (KeaserStore, Account) {
        let store = KeaserStore(file: nil)
        store.updatePreferences { $0.currencyCode = "RWF" }
        let account = store.createAccount(name: "Personal")
        let savings = PaymentMethod(name: "Savings", symbol: "banknote.fill", kind: .bank, isSavings: true)
        store.savePaymentMethod(savings, in: account.id)
        store.updateSplitRule(in: account.id) {
            $0.isEnabled = true
            $0.savingsWalletID = savings.id
        }
        return (store, store.account(id: account.id)!)
    }

    private func wallet(_ name: String, in account: Account) -> PaymentMethod {
        account.paymentMethods.first { $0.name == name }!
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 1 USD = `rwf` RWF.
    private func table(_ rwf: Decimal) -> ExchangeRates {
        ExchangeRates(base: "USD", rates: ["RWF": rwf], date: then, fetchedAt: then)
    }

    /// The balances of the named wallets of the account, in RWF.
    private func balances(_ names: [String], in store: KeaserStore, _ accountID: UUID, rates: ExchangeRates? = nil) -> [Decimal?] {
        guard let account = store.account(id: accountID) else { return [] }
        return names.map { name in
            account.paymentMethods.first { $0.name == name }.flatMap { wallet in
                WalletBalances.balance(
                    of: wallet.id, in: account, display: "RWF",
                    converter: CurrencyConverter(displayCurrency: "RWF", rates: rates), calendar: Self.calendar
                )?.amount
            }
        }
    }

    @Test func aNewAccountStartsWithIncomeCategoriesAndNoMoney() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        #expect(account.incomeCategories == IncomeCategory.defaults(for: account.id))
        #expect(account.incomeCategoriesOrderedAt == account.createdAt)
        #expect(account.incomes.isEmpty && account.transfers.isEmpty && account.balanceAdjustments.isEmpty)
        #expect(account.splitRule == SplitRule())
        #expect(account.paymentMethods.allSatisfy { !$0.isTracking })
    }

    @Test func aDatabaseWithEverythingNewRoundTripsThroughTheFile() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let cash = account.paymentMethods[2]
        let bank = account.paymentMethods[3]
        store.updateSplitRule(in: account.id) {
            $0.isEnabled = true
            $0.savingsWalletID = bank.id
        }
        store.setBalance(250, ofWallet: cash.id, in: account.id)
        store.saveIncome(Income(title: "Salary", amount: 900, walletID: cash.id), in: account.id)
        let rate = ExchangeRate(rate: Decimal(string: "1385.37")!, currencyCode: "RWF", date: then)
        store.saveIncome(Income(title: "Refund", amount: 12, currencyCode: "USD", rate: rate, categoryID: account.incomeCategories[3].id), in: account.id)
        store.saveTransfer(Transfer(fromWalletID: cash.id, toWalletID: bank.id, amountOut: 40, note: "Rent"), in: account.id)
        store.setBalance(200, ofWallet: cash.id, in: account.id)
        #expect(store.account(id: account.id)?.transfers.count == 2)
        let data = try DatabaseFile.makeEncoder().encode(store.database)
        let read = try DatabaseFile.makeDecoder().decode(Database.self, from: data)
        #expect(read == store.database)
    }

    // MARK: Income

    @Test func savingAnIncomeTrimsStampsUpsertsAndAnnouncesIt() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        var income = Income(title: "  Salary ", amount: 900, createdAt: then, updatedAt: then)
        store.saveIncome(income, in: account.id, now: later)
        let saved = try #require(store.account(id: account.id)?.incomes.first)
        #expect(saved.title == "Salary")
        #expect(saved.updatedAt == later)
        #expect(saved.createdAt == then)
        #expect(changes == [.incomeSaved(accountID: account.id, incomeID: income.id)])

        income.amount = 950
        store.saveIncome(income, in: account.id)
        #expect(store.account(id: account.id)?.incomes.map(\.amount) == [950])
        // The rule is off: no savings transfer.
        #expect(store.account(id: account.id)?.transfers.isEmpty == true)
        store.saveIncome(income, in: UUID())
        #expect(changes.count == 2)
    }

    @Test func anIncomeMakesItsSavingsTransferInTheSameSave() throws {
        let (store, account) = storeWithRule()
        let cash = wallet("Cash", in: account)
        let savings = wallet("Savings", in: account)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        let income = Income(title: "Salary", amount: 200_000, walletID: cash.id, date: then)
        store.saveIncome(income, in: account.id, now: later)
        #expect(changes == [.incomeSaved(accountID: account.id, incomeID: income.id)])

        let stored = try #require(store.account(id: account.id))
        let transfer = try #require(stored.transfers.first)
        #expect(stored.transfers.count == 1)
        #expect(transfer.kind == .savings)
        #expect(transfer.fromWalletID == cash.id && transfer.toWalletID == savings.id)
        #expect(transfer.amountOut == 40_000 && transfer.amountIn == 40_000)
        #expect(transfer.incomeID == income.id && transfer.date == then && transfer.updatedAt == later)
        let saved = try #require(stored.incomes.first)
        #expect(saved.savingsTransferID == transfer.id)
        #expect(saved.savingsPercent == 20)
    }

    @Test func editingAnIncomeUpdatesItsSavingsTransferInPlace() throws {
        let (store, account) = storeWithRule()
        let cash = wallet("Cash", in: account)
        store.saveIncome(Income(title: "Salary", amount: 100_000, walletID: cash.id), in: account.id, now: then)
        var income = try #require(store.account(id: account.id)?.incomes.first)
        let first = try #require(store.account(id: account.id)?.transfers.first)

        income.amount = 150_000
        store.saveIncome(income, in: account.id, now: later)
        let second = try #require(store.account(id: account.id)?.transfers.first)
        #expect(store.account(id: account.id)?.transfers.count == 1)
        #expect(second.id == first.id && second.createdAt == first.createdAt)
        #expect(second.amountOut == 30_000)
        #expect(second.updatedAt == later)

        // An income that already has its split keeps it with the rule off.
        store.updateSplitRule(in: account.id) { $0.isEnabled = false }
        income.title = "Salary, September"
        store.saveIncome(income, in: account.id)
        #expect(store.account(id: account.id)?.transfers.first?.amountOut == 30_000)
        #expect(store.account(id: account.id)?.incomes.first?.savingsPercent == 20)
    }

    @Test func skippingRemovesTheSavingsTransferAndClearsTheLink() throws {
        let (store, account) = storeWithRule()
        let cash = wallet("Cash", in: account)
        store.saveIncome(Income(title: "Salary", amount: 100_000, walletID: cash.id), in: account.id)
        var income = try #require(store.account(id: account.id)?.incomes.first)
        let manual = Transfer(fromWalletID: cash.id, toWalletID: wallet("Bank Transfer", in: account).id, amountOut: 5_000)
        store.saveTransfer(manual, in: account.id)

        income.savingsSkipped = true
        store.saveIncome(income, in: account.id)
        let stored = try #require(store.account(id: account.id))
        #expect(stored.transfers.map(\.id) == [manual.id])
        #expect(stored.incomes.first?.savingsTransferID == nil)
        #expect(stored.incomes.first?.savingsPercent == nil)

        // Found by its income even when the copy saved has lost the link.
        income.savingsSkipped = false
        store.saveIncome(income, in: account.id)
        var stale = try #require(store.account(id: account.id)?.incomes.first)
        stale.savingsTransferID = nil
        stale.amount = 50_000
        store.saveIncome(stale, in: account.id)
        let savingsTransfers = try #require(store.account(id: account.id)).transfers.filter { $0.kind == .savings }
        #expect(savingsTransfers.count == 1)
        #expect(savingsTransfers.first?.amountOut == 10_000)
    }

    @Test func aSavingsWalletInAnotherCurrencyTakesTodaysRate() throws {
        let (store, account) = storeWithRule()
        var savings = wallet("Savings", in: account)
        savings.currencyCode = "USD"
        store.savePaymentMethod(savings, in: account.id)
        let rates = ExchangeRates(base: "USD", rates: ["RWF": 1400], date: then, fetchedAt: then)
        store.saveIncome(Income(title: "Salary", amount: 280_000, walletID: wallet("Cash", in: account).id), in: account.id, rates: rates)
        let transfer = try #require(store.account(id: account.id)?.transfers.first)
        #expect(transfer.amountOut == 56_000)
        #expect(transfer.amountIn == 40)

        // Without rates it cannot be converted, so there is no transfer.
        store.saveIncome(Income(title: "Gift", amount: 10_000, walletID: wallet("Cash", in: account).id), in: account.id)
        #expect(store.account(id: account.id)?.transfers.count == 1)
        #expect(store.account(id: account.id)?.incomes.last?.savingsPercent == nil)
    }

    @Test func savingAnIncomeAgainLeavesItsSavingsTransferAsItWas() throws {
        let (store, account) = storeWithRule()
        var savings = wallet("Savings", in: account)
        savings.currencyCode = "USD"
        store.savePaymentMethod(savings, in: account.id)
        let cash = wallet("Cash", in: account)
        let start = then.addingTimeInterval(-2 * 86_400)
        store.setBalance(0, ofWallet: cash.id, in: account.id, at: start)
        store.setBalance(0, ofWallet: savings.id, in: account.id, at: start)
        let salary = Income(title: "Salary", amount: 280_000, walletID: cash.id, date: then, createdAt: then)
        store.saveIncome(salary, in: account.id, rates: table(1400), now: then)
        let made = try #require(store.account(id: account.id)?.transfers.first)
        #expect(made.amountOut == 56_000 && made.amountIn == 40)
        #expect(balances(["Cash", "Savings"], in: store, account.id) == [224_000, 40])

        // Its title fixed without a rate table, then under another one:
        // nothing about the money moves.
        var income = try #require(store.account(id: account.id)?.incomes.first)
        income.title = "Salary, September"
        store.saveIncome(income, in: account.id, now: later)
        income.title = "September salary"
        store.saveIncome(income, in: account.id, rates: table(1500), now: later)
        var stored = try #require(store.account(id: account.id))
        #expect(stored.transfers == [made])
        #expect(stored.incomes.first?.savingsPercent == 20)
        #expect(stored.incomes.first?.savingsTransferID == made.id)
        #expect(balances(["Cash", "Savings"], in: store, account.id) == [224_000, 40])

        // The savings wallet deleted and another picked, then the title
        // fixed: the money that went stays gone from Cash.
        store.deletePaymentMethod(savings.id, in: account.id)
        store.updateSplitRule(in: account.id) { $0.savingsWalletID = wallet("Bank Transfer", in: account).id }
        income = try #require(store.account(id: account.id)?.incomes.first)
        income.title = "Salary"
        store.saveIncome(income, in: account.id, rates: table(1500))
        stored = try #require(store.account(id: account.id))
        let orphan = try #require(stored.transfers.first)
        #expect(stored.transfers.count == 1)
        #expect(orphan.id == made.id && orphan.toWalletID == nil)
        #expect(orphan.amountIn == 40 && orphan.currencyIn == "USD")
        #expect(balances(["Cash"], in: store, account.id) == [224_000])

        // Cash deleted too, then the title fixed again: still saved that month.
        store.deletePaymentMethod(cash.id, in: account.id)
        income = try #require(store.account(id: account.id)?.incomes.first)
        income.title = "Pay"
        store.saveIncome(income, in: account.id)
        stored = try #require(store.account(id: account.id))
        #expect(stored.transfers.map(\.id) == [made.id])
        #expect(stored.incomes.first?.savingsPercent == 20 && stored.incomes.first?.savingsTransferID == made.id)
        let month = MonthEnvelopes.envelopes(
            for: stored, month: then, calendar: Self.calendar, display: "RWF",
            converter: CurrencyConverter(displayCurrency: "RWF", rates: nil)
        )
        #expect(month.savings.spent == 56_000)
    }

    @Test func aForeignIncomesSavingsAddUpOnBothSides() throws {
        let (store, account) = storeWithRule()
        let start = then.addingTimeInterval(-2 * 86_400)
        for name in ["Cash", "Savings"] {
            store.setBalance(0, ofWallet: wallet(name, in: account).id, in: account.id, at: start)
        }
        // 50 EUR typed at 1500 RWF, while today's table says 1450.
        let rate = ExchangeRate(rate: 1500, currencyCode: "RWF", date: then, isTyped: true)
        let rates = ExchangeRates(base: "EUR", rates: ["RWF": 1450], date: then, fetchedAt: then)
        let refund = Income(title: "Refund", amount: 50, currencyCode: "EUR", rate: rate, walletID: wallet("Cash", in: account).id, date: then, createdAt: then)
        store.saveIncome(refund, in: account.id, rates: rates, now: then)
        let transfer = try #require(store.account(id: account.id)?.transfers.first)
        #expect(transfer.amountOut == 10 && transfer.amountIn == 15_000)

        let stored = try #require(store.account(id: account.id))
        let converter = CurrencyConverter(displayCurrency: "RWF", rates: rates)
        #expect(balances(["Cash", "Savings"], in: store, account.id, rates: rates) == [60_000, 15_000])
        #expect(WalletBalances.total(in: stored, display: "RWF", converter: converter, calendar: Self.calendar).amount == 75_000)
        let month = MonthEnvelopes.envelopes(for: stored, month: then, calendar: Self.calendar, display: "RWF", converter: converter)
        #expect(month.income == 75_000)
        #expect(month.savings.spent == 15_000)
    }

    @Test func deletingAnIncomeTakesItsSavingsTransfer() throws {
        let (store, account) = storeWithRule()
        let cash = wallet("Cash", in: account)
        let income = Income(title: "Salary", amount: 100_000, walletID: cash.id)
        store.saveIncome(income, in: account.id)
        let manual = Transfer(fromWalletID: cash.id, toWalletID: wallet("Savings", in: account).id, amountOut: 5_000)
        store.saveTransfer(manual, in: account.id)
        // A savings transfer that names it without being linked goes too.
        store.saveTransfer(Transfer(kind: .savings, fromWalletID: cash.id, toWalletID: nil, amountOut: 1, incomeID: income.id), in: account.id)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }

        store.deleteIncome(income.id, in: account.id)
        let stored = try #require(store.account(id: account.id))
        #expect(stored.incomes.isEmpty)
        #expect(stored.transfers.map(\.id) == [manual.id])
        #expect(changes == [.incomeDeleted(accountID: account.id, incomeID: income.id)])
        store.deleteIncome(income.id, in: account.id)
        #expect(changes.count == 1)
    }

    // MARK: Transfers

    @Test func savingATransferTrimsStampsUpsertsAndAnnouncesIt() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        var transfer = Transfer(
            fromWalletID: account.paymentMethods[2].id, toWalletID: account.paymentMethods[0].id,
            amountOut: 300, note: "  Card bill\n", createdAt: then, updatedAt: then
        )
        store.saveTransfer(transfer, in: account.id, now: later)
        let saved = try #require(store.account(id: account.id)?.transfers.first)
        #expect(saved.note == "Card bill")
        #expect(saved.updatedAt == later && saved.createdAt == then)
        #expect(saved.amountIn == 300)
        #expect(changes == [.transferSaved(accountID: account.id, transferID: transfer.id)])

        transfer.amountOut = 350
        transfer.amountIn = 350
        store.saveTransfer(transfer, in: account.id)
        #expect(store.account(id: account.id)?.transfers.map(\.amountOut) == [350])
    }

    @Test func deletingASavingsTransferSkipsItsIncome() throws {
        let (store, account) = storeWithRule()
        let income = Income(title: "Salary", amount: 100_000, walletID: wallet("Cash", in: account).id)
        store.saveIncome(income, in: account.id, now: then)
        let transfer = try #require(store.account(id: account.id)?.transfers.first)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }

        store.deleteTransfer(transfer.id, in: account.id)
        let stored = try #require(store.account(id: account.id))
        #expect(stored.transfers.isEmpty)
        let skipped = try #require(stored.incomes.first)
        #expect(skipped.savingsSkipped)
        #expect(skipped.savingsTransferID == nil && skipped.savingsPercent == nil)
        #expect(skipped.updatedAt > then)
        #expect(changes == [.transferDeleted(accountID: account.id, transferID: transfer.id)])

        // Saved again, it stays skipped.
        store.saveIncome(skipped, in: account.id)
        #expect(store.account(id: account.id)?.transfers.isEmpty == true)
    }

    @Test func deletingAManualTransferLeavesIncomesAlone() throws {
        let (store, account) = storeWithRule()
        let cash = wallet("Cash", in: account)
        store.saveIncome(Income(title: "Salary", amount: 100_000, walletID: cash.id), in: account.id)
        let manual = Transfer(fromWalletID: cash.id, toWalletID: wallet("Savings", in: account).id, amountOut: 5_000)
        store.saveTransfer(manual, in: account.id)
        let before = try #require(store.account(id: account.id)?.incomes)
        store.deleteTransfer(manual.id, in: account.id)
        #expect(store.account(id: account.id)?.incomes == before)
        #expect(store.account(id: account.id)?.transfers.count == 1)
    }

    // MARK: Income categories

    @Test func incomeCategoriesAreEditedLikeSpendingCategories() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let salary = account.incomeCategories[0]
        store.saveIncome(Income(title: "Pay", amount: 10, categoryID: salary.id), in: account.id, now: then)
        store.saveIncome(Income(title: "Gift", amount: 5, categoryID: account.incomeCategories[2].id), in: account.id, now: then)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }

        var edited = salary
        edited.symbol = "dollarsign.circle.fill"
        store.saveIncomeCategory(edited, in: account.id)
        var stored = try #require(store.account(id: account.id))
        #expect(stored.incomeCategories[0].symbol == "dollarsign.circle.fill")
        #expect(stored.incomeCategories[0].updatedAt > .distantPast)
        #expect(stored.incomeCategories[1].updatedAt == .distantPast)
        #expect(stored.incomeCategoriesOrderedAt == account.incomeCategoriesOrderedAt)

        store.saveIncomeCategory(IncomeCategory(name: "Rent", symbol: "house.fill"), in: account.id)
        stored = try #require(store.account(id: account.id))
        #expect(stored.incomeCategories.map(\.name) == ["Salary", "Business", "Gifts", "Refunds", "Rent"])
        #expect(stored.incomeCategoriesOrderedAt > account.incomeCategoriesOrderedAt)

        let addedAt = stored.incomeCategoriesOrderedAt
        store.moveIncomeCategories(in: account.id, fromOffsets: [4], toOffset: 0)
        stored = try #require(store.account(id: account.id))
        #expect(stored.incomeCategories.first?.name == "Rent")
        #expect(stored.incomeCategoriesOrderedAt >= addedAt)

        store.deleteIncomeCategory(salary.id, in: account.id)
        stored = try #require(store.account(id: account.id))
        #expect(!stored.incomeCategories.contains { $0.id == salary.id })
        #expect(stored.incomes[0].categoryID == nil)
        #expect(stored.incomes[0].updatedAt > then)
        #expect(stored.incomes[1].categoryID != nil && stored.incomes[1].updatedAt == then)
        #expect(changes.allSatisfy { $0 == .accountUpdated(accountID: account.id) })
        #expect(changes.count == 4)
    }

    // MARK: Balances

    @Test func setBalanceStartsTrackingThenAddsCheckpoints() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let cash = account.paymentMethods[2]
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }

        store.setBalance(250, ofWallet: cash.id, in: account.id, at: then)
        var stored = try #require(store.account(id: account.id))
        let tracking = try #require(stored.paymentMethod(id: cash.id))
        #expect(tracking.trackingSince == then)
        #expect(tracking.openingBalance == 250)
        #expect(tracking.updatedAt > cash.updatedAt)
        #expect(stored.balanceAdjustments.isEmpty)

        store.setBalance(180, ofWallet: cash.id, in: account.id, at: later)
        stored = try #require(store.account(id: account.id))
        #expect(stored.paymentMethod(id: cash.id) == tracking)
        let adjustment = try #require(stored.balanceAdjustments.first)
        #expect(adjustment.walletID == cash.id && adjustment.balance == 180 && adjustment.date == later)

        store.deleteBalanceAdjustment(adjustment.id, in: account.id)
        #expect(store.account(id: account.id)?.balanceAdjustments.isEmpty == true)
        #expect(changes == Array(repeating: .accountUpdated(accountID: account.id), count: 3))

        // An unknown wallet changes nothing.
        store.setBalance(1, ofWallet: UUID(), in: account.id)
        #expect(changes.count == 3)
    }

    // MARK: Split rule

    @Test func editingTheSplitRuleStampsIt() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        store.updateSplitRule(in: account.id) {
            $0.savingsPercent = 10
            $0.freeMoneyPercent = 40
        }
        let rule = try #require(store.account(id: account.id)?.splitRule)
        #expect(rule.savingsPercent == 10 && rule.freeMoneyPercent == 40)
        #expect(rule.updatedAt > .distantPast)
        #expect(changes == [.accountUpdated(accountID: account.id)])

        // No change, no save.
        store.updateSplitRule(in: account.id) { $0.savingsPercent = 10 }
        #expect(changes.count == 1)
        // A time the edit sets itself is kept.
        store.updateSplitRule(in: account.id) {
            $0.isEnabled = true
            $0.updatedAt = then
        }
        #expect(store.account(id: account.id)?.splitRule.updatedAt == then)
        // Other edits to the account leave it alone.
        store.renameAccount(account.id, to: "Home")
        #expect(store.account(id: account.id)?.splitRule.updatedAt == then)
    }

    // MARK: Renaming a label

    @Test func aRenameOrANewIconInTheLabelEditorKeepsWhatTheLabelHolds() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var cash = account.paymentMethods[2]
        cash.currencyCode = "USD"
        cash.creditLimit = 300
        cash.isSavings = true
        cash.isHidden = true
        store.savePaymentMethod(cash, in: account.id)
        store.setBalance(5_000, ofWallet: cash.id, in: account.id, at: then)
        store.setBalance(4_000, ofWallet: cash.id, in: account.id, at: later)
        store.updateSplitRule(in: account.id) { $0.savingsWalletID = cash.id }
        let shopping = account.categories[1]
        #expect(shopping.role == .freeMoney)
        let before = try #require(store.account(id: account.id)?.paymentMethod(id: cash.id))

        store.saveLabel(id: cash.id, name: "Pocket", symbol: cash.symbol, kind: .paymentMethod, in: account.id)
        store.saveLabel(id: cash.id, name: "Pocket", symbol: "wallet.bifold.fill", kind: .paymentMethod, in: account.id)
        store.saveLabel(id: shopping.id, name: "Clothes", symbol: "tshirt.fill", kind: .category, in: account.id)
        let stored = try #require(store.account(id: account.id))
        let pocket = try #require(stored.paymentMethod(id: cash.id))
        #expect(pocket.name == "Pocket" && pocket.symbol == "wallet.bifold.fill")
        #expect(pocket.updatedAt > before.updatedAt)
        #expect(pocket.kind == .cash)
        #expect(pocket.currencyCode == "USD")
        #expect(pocket.trackingSince == then && pocket.openingBalance == 5_000)
        #expect(pocket.creditLimit == 300)
        #expect(pocket.isSavings && pocket.isHidden)
        #expect(stored.balanceAdjustments.map(\.walletID) == [cash.id])
        #expect(stored.splitRule.savingsWalletID == cash.id)
        let clothes = try #require(stored.category(id: shopping.id))
        #expect(clothes.name == "Clothes" && clothes.symbol == "tshirt.fill")
        #expect(clothes.role == .freeMoney)

        // A new one starts from its name; saving it unchanged changes nothing.
        let momo = UUID()
        store.saveLabel(id: momo, name: "MoMo", symbol: "iphone", kind: .paymentMethod, in: account.id)
        let made = try #require(store.account(id: account.id)?.paymentMethod(id: momo))
        #expect(made.kind == .mobileMoney && !made.isTracking)
        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        store.saveLabel(id: momo, name: "MoMo", symbol: "iphone", kind: .paymentMethod, in: account.id)
        #expect(changes.isEmpty)
    }

    // MARK: Deleting a wallet

    @Test func deletingAWalletUnlinksEverythingAndKeepsCurrencies() throws {
        let store = KeaserStore(file: nil)
        store.updatePreferences { $0.currencyCode = "RWF" }
        let account = store.createAccount(name: "Personal")
        let dollars = PaymentMethod(name: "Dollars", symbol: "dollarsign", kind: .bank, currencyCode: "USD")
        let cash = account.paymentMethods[2]
        store.savePaymentMethod(dollars, in: account.id)
        store.setBalance(100, ofWallet: dollars.id, in: account.id, at: then)
        store.setBalance(90, ofWallet: dollars.id, in: account.id, at: later)
        store.setBalance(5_000, ofWallet: cash.id, in: account.id, at: then)
        store.setBalance(4_000, ofWallet: cash.id, in: account.id, at: later)
        store.updateSplitRule(in: account.id) { $0.savingsWalletID = dollars.id }

        let lunch = Expense(title: "Lunch", amount: 12, paymentMethodID: dollars.id)
        let euros = Expense(title: "Museum", amount: 9, paymentMethodID: dollars.id, currencyCode: "EUR")
        let bus = Expense(title: "Bus", amount: 500, paymentMethodID: cash.id)
        for expense in [lunch, euros, bus] { store.saveExpense(expense, in: account.id, now: then) }
        let pay = Income(title: "Pay", amount: 1_000, walletID: dollars.id)
        store.saveIncome(pay, in: account.id, now: then)
        let out = Transfer(fromWalletID: dollars.id, toWalletID: cash.id, amountOut: 10, amountIn: 14_000)
        let into = Transfer(fromWalletID: cash.id, toWalletID: dollars.id, amountOut: 14_000, amountIn: 10)
        store.saveTransfer(out, in: account.id, now: then)
        store.saveTransfer(into, in: account.id, now: then)

        let ruleStamp = try #require(store.account(id: account.id)).splitRule.updatedAt
        store.deletePaymentMethod(dollars.id, in: account.id)
        let stored = try #require(store.account(id: account.id))
        #expect(stored.paymentMethod(id: dollars.id) == nil)
        let expenses = Dictionary(uniqueKeysWithValues: stored.expenses.map { ($0.title, $0) })
        #expect(expenses["Lunch"]?.paymentMethodID == nil && expenses["Lunch"]?.currencyCode == "USD")
        #expect(expenses["Museum"]?.currencyCode == "EUR")
        #expect(expenses["Bus"]?.paymentMethodID == cash.id && expenses["Bus"]?.currencyCode == nil)
        #expect(expenses["Bus"]?.updatedAt == then)
        #expect(expenses["Lunch"].map { $0.updatedAt > then } == true)
        #expect(stored.incomes.first?.walletID == nil && stored.incomes.first?.currencyCode == "USD")
        let transfers = Dictionary(uniqueKeysWithValues: stored.transfers.map { ($0.id, $0) })
        #expect(transfers[out.id]?.fromWalletID == nil && transfers[out.id]?.currencyOut == "USD")
        #expect(transfers[out.id]?.toWalletID == cash.id && transfers[out.id]?.currencyIn == nil)
        #expect(transfers[into.id]?.toWalletID == nil && transfers[into.id]?.currencyIn == "USD")
        #expect(transfers[into.id]?.fromWalletID == cash.id && transfers[into.id]?.currencyOut == nil)
        #expect(stored.balanceAdjustments.map(\.walletID) == [cash.id])
        #expect(stored.splitRule.savingsWalletID == nil)
        #expect(stored.splitRule.updatedAt > ruleStamp)
    }

    @Test func deletingAWalletInTheDisplayCurrencyPinsNothing() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let cash = account.paymentMethods[2]
        store.saveExpense(Expense(title: "Bus", amount: 2, paymentMethodID: cash.id), in: account.id)
        store.saveIncome(Income(title: "Pay", amount: 10, walletID: cash.id), in: account.id)
        store.saveTransfer(Transfer(fromWalletID: cash.id, toWalletID: account.paymentMethods[3].id, amountOut: 1), in: account.id)
        store.deletePaymentMethod(cash.id, in: account.id)
        let stored = try #require(store.account(id: account.id))
        #expect(stored.expenses.first?.currencyCode == nil && stored.expenses.first?.paymentMethodID == nil)
        #expect(stored.incomes.first?.currencyCode == nil && stored.incomes.first?.walletID == nil)
        #expect(stored.transfers.first?.currencyOut == nil && stored.transfers.first?.fromWalletID == nil)
    }

    @Test func untouchedIncomesAndTransfersKeepTheirTimes() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        store.saveIncome(Income(title: "Pay", amount: 10), in: account.id, now: then)
        store.saveTransfer(Transfer(fromWalletID: nil, toWalletID: nil, amountOut: 1), in: account.id, now: then)
        store.setBalance(5, ofWallet: account.paymentMethods[0].id, in: account.id)
        store.renameAccount(account.id, to: "Home")
        let stored = try #require(store.account(id: account.id))
        #expect(stored.incomes.first?.updatedAt == then)
        #expect(stored.transfers.first?.updatedAt == then)
    }
}
