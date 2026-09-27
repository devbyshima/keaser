import Foundation
import Testing
@testable import KeaserKit

private let us = Locale(identifier: "en_US")
private let newYork = TimeZone(identifier: "America/New_York")!

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = newYork
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

/// Personal with Coffee and Lunch, Business with Taxi.
private func sampleDatabase() -> Database {
    var personal = Account(name: "Personal")
    personal.expenses = [
        Expense(title: "Coffee", amount: Decimal(string: "4.50")!, date: day(2026, 9, 26), createdAt: day(2026, 9, 26), updatedAt: day(2026, 9, 26)),
        Expense(title: "Lunch", amount: 12, date: day(2026, 9, 25), createdAt: day(2026, 9, 25), updatedAt: day(2026, 9, 25)),
    ]
    var business = Account(name: "Business")
    business.expenses = [Expense(title: "Taxi", amount: 38, date: day(2026, 9, 24), createdAt: day(2026, 9, 24), updatedAt: day(2026, 9, 24))]
    return Database(accounts: [personal, business], preferences: Preferences(currencyCode: "USD", selectedAccountID: personal.id))
}

struct ExpenseDeletionTests {
    @Test func findsExpensesInEveryAccountInTheOrderAsked() {
        let db = sampleDatabase()
        let taxi = db.accounts[1].expenses[0]
        let coffee = db.accounts[0].expenses[0]
        let deletion = ExpenseDeletion(ids: [taxi.id, UUID(), coffee.id, taxi.id], in: db)
        #expect(deletion.items.map(\.expense.title) == ["Taxi", "Coffee"])
        #expect(deletion.items.map(\.accountName) == ["Business", "Personal"])
        #expect(deletion.total == Decimal(string: "42.50"))
        #expect(ExpenseDeletion(ids: [UUID()], in: db).isEmpty)
    }

    @Test func theQuestionNamesWhatGoes() {
        let db = sampleDatabase()
        let personal = db.accounts[0]
        let one = ExpenseDeletion(ids: [personal.expenses[0].id], in: db)
        #expect(one.question(currencyCode: "USD", locale: us, timeZone: newYork)
            == "Delete \u{201C}Coffee\u{201D} ($4.50 on Sep 26, 2026) from Personal?")
        let two = ExpenseDeletion(ids: personal.expenses.map(\.id), in: db)
        #expect(two.question(currencyCode: "USD", locale: us, timeZone: newYork) == "Delete 2 expenses ($16.50 in all) from Personal?")
        let everywhere = ExpenseDeletion(ids: db.accounts.flatMap(\.expenses).map(\.id), in: db)
        #expect(everywhere.question(currencyCode: "USD", locale: us, timeZone: newYork) == "Delete 3 expenses ($54.50 in all) from 2 accounts?")
    }

    @Test func theDoneSentence() {
        let db = sampleDatabase()
        #expect(ExpenseDeletion(ids: [db.accounts[1].expenses[0].id], in: db).doneSentence == "Deleted \u{201C}Taxi\u{201D} from Business.")
        #expect(ExpenseDeletion(ids: db.accounts[0].expenses.map(\.id), in: db).doneSentence == "Deleted 2 expenses.")
    }
}

@MainActor
struct ExpenseDeletionStoreTests {
    private func tempFile() -> DatabaseFile {
        DatabaseFile(url: FileManager.default.temporaryDirectory
            .appending(path: "keaser-deletion-\(UUID().uuidString)/Keaser/database.json"))
    }

    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func expenses(_ database: Database) -> Set<Expense> {
        Set(database.accounts.flatMap(\.expenses))
    }

    @Test func deletingThenRestoringPutsBackExactlyWhatWasThere() {
        let original = sampleDatabase()
        let store = KeaserStore(database: original, file: nil)
        let deletion = ExpenseDeletion(ids: [original.accounts[0].expenses[1].id, original.accounts[1].expenses[0].id], in: original)
        #expect(store.delete(deletion))
        #expect(store.accounts[0].expenses.map(\.title) == ["Coffee"])
        #expect(store.accounts[1].expenses.isEmpty)

        #expect(store.restore(deletion.items))
        #expect(expenses(store.database) == expenses(original))
        // Undoing twice changes nothing.
        #expect(store.restore(deletion.items))
        #expect(store.database.accounts.flatMap(\.expenses).count == 3)
    }

    @Test func restoringSkipsADeletedAccount() {
        let original = sampleDatabase()
        let store = KeaserStore(database: original, file: nil)
        let deletion = ExpenseDeletion(ids: [original.accounts[1].expenses[0].id], in: original)
        store.delete(deletion)
        store.deleteAccount(original.accounts[1].id)
        #expect(store.restore(deletion.items))
        #expect(store.accounts.count == 1)
    }

    @Test func aDeleteThatCannotBeSavedIsTakenBack() throws {
        let file = tempFile()
        let store = KeaserStore(file: file)
        let account = store.createAccount(name: "Personal")
        store.saveExpense(Expense(title: "Coffee", amount: 4), in: account.id)
        store.saveExpense(Expense(title: "Lunch", amount: 12), in: account.id)
        let before = expenses(store.database)
        let folder = file.url.deletingLastPathComponent()
        try chmod(folder, 0o555) // the next atomic write fails, like a full disk
        defer { try? chmod(folder, 0o755) }

        let deletion = ExpenseDeletion(ids: store.accounts[0].expenses.map(\.id), in: store.database)
        #expect(!store.delete(deletion))
        #expect(expenses(store.database) == before)

        // Once the disk has room again, nothing was deleted after all.
        try chmod(folder, 0o755)
        store.reloadFromDisk()
        #expect(store.lastSaveError == nil)
        #expect(expenses(file.load()) == before)
    }

    @Test func anUndoThatCannotBeSavedIsTakenBack() throws {
        let file = tempFile()
        let store = KeaserStore(file: file)
        let account = store.createAccount(name: "Personal")
        store.saveExpense(Expense(title: "Coffee", amount: 4), in: account.id)
        let deletion = ExpenseDeletion(ids: store.accounts[0].expenses.map(\.id), in: store.database)
        #expect(store.delete(deletion))
        let folder = file.url.deletingLastPathComponent()
        try chmod(folder, 0o555)
        defer { try? chmod(folder, 0o755) }

        #expect(!store.restore(deletion.items))
        #expect(store.accounts[0].expenses.isEmpty)
        try chmod(folder, 0o755)
        store.reloadFromDisk()
        #expect(file.load().accounts[0].expenses.isEmpty)
    }
}
