import Foundation

/// Edit times for last-writer-wins. After every local edit `KeaserStore`
/// stamps `now` on each record the edit changed, so when two devices change
/// the same record, iCloud sync keeps the later change. The stamps are kept
/// whether or not sync is on, so they are right the day it is turned on.
///
/// - An account's `updatedAt` moves when its name changes.
/// - A category's, payment method's or expense's `updatedAt` moves when
///   anything else about it changes (an expense losing its deleted
///   category included).
/// - `categoriesOrderedAt`, `paymentMethodsOrderedAt` and
///   `Database.accountsOrderedAt` move when their list's order changes:
///   an item moved, added or deleted.
/// - `Preferences.settingsUpdatedAt` moves when a `SyncedSettings` field
///   changes.
///
/// A stamp the edit set itself is kept (`saveExpense` stamps its own time;
/// an undone deletion puts the expense back with its old one), and a new
/// record keeps the time it was made with.
public enum SyncStamps {
    public static func stamp(_ database: inout Database, since before: Database, now: Date) {
        if database.accounts.map(\.id) != before.accounts.map(\.id), database.accountsOrderedAt == before.accountsOrderedAt {
            database.accountsOrderedAt = now
        }
        if SyncedSettings(database.preferences).differs(from: SyncedSettings(before.preferences)),
           database.preferences.settingsUpdatedAt == before.preferences.settingsUpdatedAt {
            database.preferences.settingsUpdatedAt = now
        }
        guard database.accounts != before.accounts else { return }
        let previous = Dictionary(before.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in database.accounts.indices {
            guard let old = previous[database.accounts[index].id], database.accounts[index] != old else { continue }
            stamp(&database.accounts[index], since: old, now: now)
        }
    }

    static func stamp(_ account: inout Account, since old: Account, now: Date) {
        if account.name != old.name || account.createdAt != old.createdAt, account.updatedAt == old.updatedAt {
            account.updatedAt = now
        }
        stampList(&account.categories, orderedAt: &account.categoriesOrderedAt, since: old.categories, oldOrderedAt: old.categoriesOrderedAt, now: now)
        stampList(&account.paymentMethods, orderedAt: &account.paymentMethodsOrderedAt, since: old.paymentMethods, oldOrderedAt: old.paymentMethodsOrderedAt, now: now)
        var unused = Date.distantPast
        stampList(&account.expenses, orderedAt: &unused, since: old.expenses, oldOrderedAt: .distantPast, now: now)
    }

    private static func stampList<Item: AccountItem>(_ items: inout [Item], orderedAt: inout Date, since old: [Item], oldOrderedAt: Date, now: Date) {
        guard items != old else { return }
        if items.map(\.id) != old.map(\.id), orderedAt == oldOrderedAt {
            orderedAt = now
        }
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in items.indices {
            guard let before = previous[items[index].id], items[index].updatedAt == before.updatedAt else { continue }
            if items[index] != before { items[index].updatedAt = now }
        }
    }
}
