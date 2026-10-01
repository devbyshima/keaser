import Foundation
import Observation
import os

/// What just changed, for observers that react to edits (widget reloads,
/// notification rescheduling).
public enum StoreChange: Sendable, Equatable {
    case expenseSaved(accountID: UUID, expenseID: UUID)
    case expenseDeleted(accountID: UUID, expenseID: UUID)
    case incomeSaved(accountID: UUID, incomeID: UUID)
    case incomeDeleted(accountID: UUID, incomeID: UUID)
    case transferSaved(accountID: UUID, transferID: UUID)
    case transferDeleted(accountID: UUID, transferID: UUID)
    case accountCreated(accountID: UUID)
    case accountUpdated(accountID: UUID)
    case accountDeleted(accountID: UUID)
    case accountsReordered
    case preferencesChanged
    /// The whole database was replaced (reload from disk).
    case reloaded
    /// Changes made on the person's other devices arrived through iCloud
    /// and were merged in: anything may have changed.
    case mergedFromCloud
}

/// What became of a merge from iCloud handed to the store.
public enum CloudMergeOutcome: Equatable, Sendable {
    /// In the database and on disk (or nothing needed changing).
    case saved
    /// The database changed while the merge was worked out; merge again.
    case stale
    /// Not written: the file cannot be read or written right now. Keep what
    /// iCloud sent and try again later.
    case notSaved
}

/// The single source of truth. Every mutation goes through here, is saved to
/// disk immediately and is announced to observers.
@MainActor
@Observable
public final class KeaserStore {
    public private(set) var database: Database
    /// The last save error, if any. Changes stay in memory and are retried on
    /// the next save or reload; RootView shows a banner while this is set.
    public private(set) var lastSaveError: String?
    /// Set when the database file exists but could not be read (typically
    /// before the first unlock after a restart). While set, nothing is written
    /// to disk, so the real file cannot be overwritten by an empty database;
    /// `reloadFromDisk()` retries the read.
    public private(set) var loadError: String?
    /// Moves on with every change to `database`, so work done away from
    /// the main actor on a copy can tell whether the copy is still current
    /// (see `applyCloudChanges(_:ifRevision:)`).
    @ObservationIgnored public private(set) var revision = 0

    @ObservationIgnored private let file: DatabaseFile?
    @ObservationIgnored private var observers: [@MainActor (StoreChange) -> Void] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "KeaserStore")

    /// `file == nil` keeps everything in memory (tests, previews, seeded debug
    /// launches).
    public init(database: Database? = nil, file: DatabaseFile?) {
        self.file = file
        if let database {
            self.database = database
        } else if let file {
            do {
                self.database = try file.read() ?? Database()
            } catch {
                self.database = Database()
                self.loadError = error.localizedDescription
            }
        } else {
            self.database = Database()
        }
    }

    // MARK: Reading

    public var accounts: [Account] { database.accounts }
    public var preferences: Preferences { database.preferences }
    public var selectedAccount: Account? { database.selectedAccount }

    public func account(id: UUID) -> Account? {
        database.accounts.first { $0.id == id }
    }

    /// Whether the user has Pro right now (purchase or live 7-day pass).
    public func isPro(now: Date = .now) -> Bool {
        ProEntitlement.isPro(database.preferences, now: now)
    }

    // MARK: Observing

    public func addObserver(_ observer: @escaping @MainActor (StoreChange) -> Void) {
        observers.append(observer)
    }

    // MARK: Preferences

    public func updatePreferences(_ body: (inout Preferences) -> Void) {
        let before = database
        body(&database.preferences)
        guard database.preferences != before.preferences else { return }
        commit(.preferencesChanged, since: before)
    }

    public func selectAccount(_ id: UUID) {
        guard account(id: id) != nil else { return }
        updatePreferences { $0.selectedAccountID = id }
    }

    // MARK: Accounts

    /// Creates an account with the default categories and payment methods and
    /// selects it.
    @discardableResult
    public func createAccount(name: String) -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(name: trimmed.isEmpty ? "Personal" : trimmed)
        let before = database
        database.accounts.append(account)
        database.preferences.selectedAccountID = account.id
        commit(.accountCreated(accountID: account.id), since: before)
        return account
    }

    public func renameAccount(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateAccount(id) { $0.name = trimmed }
    }

    /// General-purpose edit of one account.
    public func updateAccount(_ id: UUID, _ body: (inout Account) -> Void) {
        guard let index = database.accounts.firstIndex(where: { $0.id == id }) else { return }
        let before = database
        body(&database.accounts[index])
        guard database.accounts[index] != before.accounts[index] else { return }
        commit(.accountUpdated(accountID: id), since: before)
    }

    /// Removes the account and everything in it. Selects the next account.
    public func deleteAccount(_ id: UUID) {
        guard let index = database.accounts.firstIndex(where: { $0.id == id }) else { return }
        let before = database
        database.accounts.remove(at: index)
        if database.preferences.selectedAccountID == id {
            database.preferences.selectedAccountID = database.accounts.first?.id
        }
        commit(.accountDeleted(accountID: id), since: before)
    }

    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        let before = database
        database.accounts.keaserMove(fromOffsets: source, toOffset: destination)
        commit(.accountsReordered, since: before)
    }

    // MARK: Expenses

    /// Inserts or replaces an expense (matched by ID) and stamps `updatedAt`.
    public func saveExpense(_ expense: Expense, in accountID: UUID, now: Date = .now) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var expense = expense
        expense.title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.updatedAt = now
        let before = database
        if let e = database.accounts[a].expenses.firstIndex(where: { $0.id == expense.id }) {
            database.accounts[a].expenses[e] = expense
        } else {
            database.accounts[a].expenses.append(expense)
        }
        commit(.expenseSaved(accountID: accountID, expenseID: expense.id), since: before, now: now)
    }

    public func deleteExpense(_ expenseID: UUID, in accountID: UUID) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }),
              let e = database.accounts[a].expenses.firstIndex(where: { $0.id == expenseID })
        else { return }
        let before = database
        database.accounts[a].expenses.remove(at: e)
        commit(.expenseDeleted(accountID: accountID, expenseID: expenseID), since: before)
    }

    // MARK: Categories

    /// Inserts or replaces a category (matched by ID).
    public func saveCategory(_ category: ExpenseCategory, in accountID: UUID) {
        updateAccount(accountID) { account in
            if let i = account.categories.firstIndex(where: { $0.id == category.id }) {
                account.categories[i] = category
            } else {
                account.categories.append(category)
            }
        }
    }

    /// Removes a category; its expenses become uncategorised.
    public func deleteCategory(_ categoryID: UUID, in accountID: UUID) {
        updateAccount(accountID) { account in
            account.categories.removeAll { $0.id == categoryID }
            for i in account.expenses.indices where account.expenses[i].categoryID == categoryID {
                account.expenses[i].categoryID = nil
            }
        }
    }

    public func moveCategories(in accountID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateAccount(accountID) { $0.categories.keaserMove(fromOffsets: source, toOffset: destination) }
    }

    // MARK: Payment methods

    /// Inserts or replaces a payment method (matched by ID).
    public func savePaymentMethod(_ method: PaymentMethod, in accountID: UUID) {
        updateAccount(accountID) { account in
            if let i = account.paymentMethods.firstIndex(where: { $0.id == method.id }) {
                account.paymentMethods[i] = method
            } else {
                account.paymentMethods.append(method)
            }
        }
    }

    /// Removes a payment method (a wallet). Its expenses, incomes and
    /// transfers keep no wallet, its balance adjustments go, and the split
    /// rule loses it as the savings wallet. What followed the wallet's own
    /// currency is given that currency first, so it keeps it rather than
    /// falling back to the display currency.
    public func deletePaymentMethod(_ methodID: UUID, in accountID: UUID) {
        updateAccount(accountID) { account in
            let currency = account.paymentMethod(id: methodID)?.currencyCode
            account.paymentMethods.removeAll { $0.id == methodID }
            for i in account.expenses.indices where account.expenses[i].paymentMethodID == methodID {
                account.expenses[i].currencyCode = account.expenses[i].currencyCode ?? currency
                account.expenses[i].paymentMethodID = nil
            }
            for i in account.incomes.indices where account.incomes[i].walletID == methodID {
                account.incomes[i].currencyCode = account.incomes[i].currencyCode ?? currency
                account.incomes[i].walletID = nil
            }
            for i in account.transfers.indices {
                if account.transfers[i].fromWalletID == methodID {
                    account.transfers[i].currencyOut = account.transfers[i].currencyOut ?? currency
                    account.transfers[i].fromWalletID = nil
                }
                if account.transfers[i].toWalletID == methodID {
                    account.transfers[i].currencyIn = account.transfers[i].currencyIn ?? currency
                    account.transfers[i].toWalletID = nil
                }
            }
            account.balanceAdjustments.removeAll { $0.walletID == methodID }
            if account.splitRule.savingsWalletID == methodID {
                account.splitRule.savingsWalletID = nil
            }
        }
    }

    public func movePaymentMethods(in accountID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateAccount(accountID) { $0.paymentMethods.keaserMove(fromOffsets: source, toOffset: destination) }
    }

    // MARK: Labels

    /// Saves a category's or payment method's name and icon, as the label
    /// editor does. One the account has keeps everything else (a category's
    /// role, a wallet's kind, currency, balance, limit and switches), so a
    /// rename or a new icon never resets it; a new one starts from its name.
    public func saveLabel(id: UUID, name: String, symbol: String, kind: LabelKind, in accountID: UUID) {
        let stored = account(id: accountID)
        switch kind {
        case .category:
            var category = stored?.category(id: id) ?? ExpenseCategory(id: id, name: name, symbol: symbol)
            category.name = name
            category.symbol = symbol
            saveCategory(category, in: accountID)
        case .paymentMethod:
            var method = stored?.paymentMethod(id: id) ?? PaymentMethod(id: id, name: name, symbol: symbol)
            method.name = name
            method.symbol = symbol
            savePaymentMethod(method, in: accountID)
        }
    }

    // MARK: Wallet balances

    /// States what is in a wallet at `date`. A wallet not tracking starts
    /// tracking from that balance; one already tracking gets a balance
    /// adjustment, a later checkpoint that leaves its history as it is.
    public func setBalance(_ balance: Decimal, ofWallet walletID: UUID, in accountID: UUID, at date: Date = .now) {
        updateAccount(accountID) { account in
            guard let w = account.paymentMethods.firstIndex(where: { $0.id == walletID }) else { return }
            if account.paymentMethods[w].trackingSince == nil {
                account.paymentMethods[w].trackingSince = date
                account.paymentMethods[w].openingBalance = balance
            } else {
                account.balanceAdjustments.append(BalanceAdjustment(walletID: walletID, balance: balance, date: date))
            }
        }
    }

    public func deleteBalanceAdjustment(_ adjustmentID: UUID, in accountID: UUID) {
        updateAccount(accountID) { $0.balanceAdjustments.removeAll { $0.id == adjustmentID } }
    }

    // MARK: Income

    /// Inserts or replaces an income (matched by ID) and stamps `updatedAt`.
    /// In the same save, its savings transfer is made, updated or removed
    /// as the split rule says (`SavingsSplit`), at `rates` when the savings
    /// wallet is in another currency. The rule applies to a new income or
    /// one whose Skip This Time was just turned off; any other keeps the
    /// split it was logged with. One already made stays as it is unless
    /// what leaves the income's wallet changed.
    public func saveIncome(_ income: Income, in accountID: UUID, rates: ExchangeRates? = nil, now: Date = .now) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var income = income
        income.title = income.title.trimmingCharacters(in: .whitespacesAndNewlines)
        income.updatedAt = now
        let before = database
        var account = database.accounts[a]
        let display = database.preferences.currencyCode
        let stored = account.income(id: income.id)
        let linked = income.savingsTransferID ?? stored?.savingsTransferID
        let existing = account.transfer(id: linked)
            ?? account.transfers.first { $0.kind == .savings && $0.incomeID == income.id }
        let split = SavingsSplit.transfer(
            for: income, stored: stored, existing: existing, in: account, rule: account.splitRule, display: display,
            converter: CurrencyConverter(displayCurrency: display, rates: rates), now: now
        )
        if let transfer = split.transfer {
            if let t = account.transfers.firstIndex(where: { $0.id == transfer.id }) {
                account.transfers[t] = transfer
            } else {
                account.transfers.append(transfer)
            }
        } else if let existing {
            account.transfers.removeAll { $0.id == existing.id }
        }
        // Any other savings transfer of it is a copy (made on another
        // device) that would count twice.
        account.transfers.removeAll { $0.kind == .savings && $0.incomeID == income.id && $0.id != split.transfer?.id }
        income.savingsTransferID = split.transfer?.id
        income.savingsPercent = split.percent
        if let i = account.incomes.firstIndex(where: { $0.id == income.id }) {
            account.incomes[i] = income
        } else {
            account.incomes.append(income)
        }
        database.accounts[a] = account
        commit(.incomeSaved(accountID: accountID, incomeID: income.id), since: before, now: now)
    }

    /// Removes an income and the savings transfer it made.
    public func deleteIncome(_ incomeID: UUID, in accountID: UUID) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }),
              let i = database.accounts[a].incomes.firstIndex(where: { $0.id == incomeID })
        else { return }
        let before = database
        let linked = database.accounts[a].incomes[i].savingsTransferID
        database.accounts[a].incomes.remove(at: i)
        database.accounts[a].transfers.removeAll { transfer in
            transfer.id == linked || (transfer.kind == .savings && transfer.incomeID == incomeID)
        }
        commit(.incomeDeleted(accountID: accountID, incomeID: incomeID), since: before)
    }

    // MARK: Transfers

    /// Inserts or replaces a transfer (matched by ID) and stamps `updatedAt`.
    public func saveTransfer(_ transfer: Transfer, in accountID: UUID, now: Date = .now) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var transfer = transfer
        transfer.note = transfer.note.trimmingCharacters(in: .whitespacesAndNewlines)
        transfer.updatedAt = now
        let before = database
        if let t = database.accounts[a].transfers.firstIndex(where: { $0.id == transfer.id }) {
            database.accounts[a].transfers[t] = transfer
        } else {
            database.accounts[a].transfers.append(transfer)
        }
        commit(.transferSaved(accountID: accountID, transferID: transfer.id), since: before, now: now)
    }

    /// Removes a transfer. Deleting an income's savings transfer is
    /// skipping it: the income keeps no split and is marked skipped. A
    /// copy of it the income does not link, while another remains, goes
    /// alone.
    public func deleteTransfer(_ transferID: UUID, in accountID: UUID) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }),
              let t = database.accounts[a].transfers.firstIndex(where: { $0.id == transferID })
        else { return }
        let before = database
        let transfer = database.accounts[a].transfers.remove(at: t)
        let remaining = database.accounts[a].transfers
        for i in database.accounts[a].incomes.indices {
            let income = database.accounts[a].incomes[i]
            let itsLast = transfer.kind == .savings && transfer.incomeID == income.id
                && !remaining.contains { $0.kind == .savings && $0.incomeID == income.id }
            guard income.savingsTransferID == transferID || itsLast else { continue }
            database.accounts[a].incomes[i].savingsTransferID = nil
            database.accounts[a].incomes[i].savingsPercent = nil
            database.accounts[a].incomes[i].savingsSkipped = true
        }
        commit(.transferDeleted(accountID: accountID, transferID: transferID), since: before)
    }

    // MARK: Income categories

    /// Inserts or replaces an income category (matched by ID).
    public func saveIncomeCategory(_ category: IncomeCategory, in accountID: UUID) {
        updateAccount(accountID) { account in
            if let i = account.incomeCategories.firstIndex(where: { $0.id == category.id }) {
                account.incomeCategories[i] = category
            } else {
                account.incomeCategories.append(category)
            }
        }
    }

    /// Removes an income category; its incomes become uncategorised.
    public func deleteIncomeCategory(_ categoryID: UUID, in accountID: UUID) {
        updateAccount(accountID) { account in
            account.incomeCategories.removeAll { $0.id == categoryID }
            for i in account.incomes.indices where account.incomes[i].categoryID == categoryID {
                account.incomes[i].categoryID = nil
            }
        }
    }

    public func moveIncomeCategories(in accountID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateAccount(accountID) { $0.incomeCategories.keaserMove(fromOffsets: source, toOffset: destination) }
    }

    // MARK: Split rule

    public func updateSplitRule(in accountID: UUID, _ body: (inout SplitRule) -> Void) {
        updateAccount(accountID) { body(&$0.splitRule) }
    }

    // MARK: Whole database

    /// Re-reads the file, for when another process (an App Intent running in
    /// the background) may have written it. Never discards a change that has
    /// not reached the disk: a pending failed save is retried instead, and a
    /// file that still cannot be read leaves memory untouched.
    public func reloadFromDisk() {
        guard let file else { return }
        if lastSaveError != nil, loadError == nil {
            persist()
            return
        }
        let fresh: Database
        do {
            fresh = try file.read() ?? Database()
        } catch {
            loadError = error.localizedDescription
            return
        }
        loadError = nil
        guard fresh != database else { return }
        database = fresh
        revision += 1
        announce(.reloaded)
    }

    /// Replaces the database with `merged`, the result of merging changes
    /// from iCloud into it (`SyncMerge`), unless the database changed since
    /// `revision` was read, in which case the caller merges again from the
    /// current one. Nothing is stamped: the merge carries the edit times of
    /// the devices that made the changes. Announced as `.mergedFromCloud`,
    /// so widgets, Spotlight and the weekly summary catch up in one go.
    public func applyCloudChanges(_ merged: Database, ifRevision expected: Int) -> CloudMergeOutcome {
        guard revision == expected else { return .stale }
        // Never while the file is unreadable (memory holds an empty
        // stand-in) or an earlier change is still unsaved (the merge would
        // be saved on top of a file that lacks it).
        guard loadError == nil, lastSaveError == nil else { return .notSaved }
        guard merged != database else { return .saved }
        database = merged
        revision += 1
        persist()
        announce(.mergedFromCloud)
        return lastSaveError == nil ? .saved : .notSaved
    }

    // MARK: Private

    /// Stamps the records the edit changed with `now` (`SyncStamps`), then
    /// saves and announces it.
    private func commit(_ change: StoreChange, since before: Database, now: Date = .now) {
        SyncStamps.stamp(&database, since: before, now: now)
        revision += 1
        persist()
        announce(change)
    }

    private func persist() {
        // Writing now would replace a file we could not read with whatever is
        // in memory, which is not the user's data.
        guard let file, loadError == nil else { return }
        do {
            try file.save(database)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func announce(_ change: StoreChange) {
        for observer in observers { observer(change) }
    }
}

extension Array {
    /// `move(fromOffsets:toOffset:)` without importing SwiftUI.
    public mutating func keaserMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.reversed() { remove(at: index) }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(count, destination - before)))
    }
}
