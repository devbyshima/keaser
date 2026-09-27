import Foundation
import Observation
import os

/// What just changed, for observers that react to edits (widget reloads,
/// notification rescheduling).
public enum StoreChange: Sendable, Equatable {
    case expenseSaved(accountID: UUID, expenseID: UUID)
    case expenseDeleted(accountID: UUID, expenseID: UUID)
    case accountCreated(accountID: UUID)
    case accountUpdated(accountID: UUID)
    case accountDeleted(accountID: UUID)
    case accountsReordered
    case preferencesChanged
    /// The whole database was replaced (reload from disk).
    case reloaded
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
        let before = database.preferences
        body(&database.preferences)
        guard database.preferences != before else { return }
        commit(.preferencesChanged)
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
        database.accounts.append(account)
        database.preferences.selectedAccountID = account.id
        commit(.accountCreated(accountID: account.id))
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
        let before = database.accounts[index]
        body(&database.accounts[index])
        guard database.accounts[index] != before else { return }
        commit(.accountUpdated(accountID: id))
    }

    /// Removes the account and everything in it. Selects the next account.
    public func deleteAccount(_ id: UUID) {
        guard let index = database.accounts.firstIndex(where: { $0.id == id }) else { return }
        database.accounts.remove(at: index)
        if database.preferences.selectedAccountID == id {
            database.preferences.selectedAccountID = database.accounts.first?.id
        }
        commit(.accountDeleted(accountID: id))
    }

    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        database.accounts.keaserMove(fromOffsets: source, toOffset: destination)
        commit(.accountsReordered)
    }

    // MARK: Expenses

    /// Inserts or replaces an expense (matched by ID) and stamps `updatedAt`.
    public func saveExpense(_ expense: Expense, in accountID: UUID, now: Date = .now) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var expense = expense
        expense.title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.updatedAt = now
        if let e = database.accounts[a].expenses.firstIndex(where: { $0.id == expense.id }) {
            database.accounts[a].expenses[e] = expense
        } else {
            database.accounts[a].expenses.append(expense)
        }
        commit(.expenseSaved(accountID: accountID, expenseID: expense.id))
    }

    public func deleteExpense(_ expenseID: UUID, in accountID: UUID) {
        guard let a = database.accounts.firstIndex(where: { $0.id == accountID }),
              let e = database.accounts[a].expenses.firstIndex(where: { $0.id == expenseID })
        else { return }
        database.accounts[a].expenses.remove(at: e)
        commit(.expenseDeleted(accountID: accountID, expenseID: expenseID))
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

    /// Removes a payment method; its expenses keep no payment method.
    public func deletePaymentMethod(_ methodID: UUID, in accountID: UUID) {
        updateAccount(accountID) { account in
            account.paymentMethods.removeAll { $0.id == methodID }
            for i in account.expenses.indices where account.expenses[i].paymentMethodID == methodID {
                account.expenses[i].paymentMethodID = nil
            }
        }
    }

    public func movePaymentMethods(in accountID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateAccount(accountID) { $0.paymentMethods.keaserMove(fromOffsets: source, toOffset: destination) }
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
        announce(.reloaded)
    }

    // MARK: Private

    private func commit(_ change: StoreChange) {
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
