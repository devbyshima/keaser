import Foundation
import Testing
@testable import KeaserKit

/// The store must never lose a change it showed the user, and never replace a
/// real database file with an empty one.
@MainActor
struct StoreSafetyTests {
    private func tempFile() -> DatabaseFile {
        DatabaseFile(url: FileManager.default.temporaryDirectory
            .appending(path: "keaser-safety-\(UUID().uuidString)/Keaser/database.json"))
    }

    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    @Test func reloadKeepsAChangeWhoseSaveFailedAndRetriesIt() throws {
        let file = tempFile()
        let store = KeaserStore(file: file)
        let account = store.createAccount(name: "Personal")
        let folder = file.url.deletingLastPathComponent()
        try chmod(folder, 0o555) // the next atomic write fails, like a full disk
        defer { try? chmod(folder, 0o755) }

        store.saveExpense(Expense(title: "Lunch", amount: 12), in: account.id)
        #expect(store.lastSaveError != nil)

        store.reloadFromDisk()
        #expect(store.account(id: account.id)?.expenses.count == 1)

        try chmod(folder, 0o755)
        store.reloadFromDisk()
        #expect(store.lastSaveError == nil)
        #expect(file.load().accounts.first?.expenses.count == 1)
    }

    @Test func anUnreadableFileIsNeverOverwritten() throws {
        let file = tempFile()
        let first = KeaserStore(file: file)
        let account = first.createAccount(name: "Personal")
        first.saveExpense(Expense(title: "Rent", amount: 900), in: account.id)

        try chmod(file.url, 0o000)
        defer { try? chmod(file.url, 0o644) }
        let relaunched = KeaserStore(file: file)
        #expect(relaunched.loadError != nil)
        relaunched.updatePreferences { $0.hasProPurchase = true }

        try chmod(file.url, 0o644)
        #expect(file.load().accounts.count == 1)
        #expect(file.load().preferences.hasProPurchase == false)

        relaunched.reloadFromDisk()
        #expect(relaunched.loadError == nil)
        #expect(relaunched.accounts.first?.expenses.count == 1)
    }

    @Test func aMissingFileIsAFreshInstall() throws {
        let store = KeaserStore(file: tempFile())
        #expect(store.loadError == nil)
        #expect(store.accounts.isEmpty)
    }
}
