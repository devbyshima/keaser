import Foundation
import Testing
@testable import KeaserKit

/// Receipt photos in iCloud sync: the expense's list of photo IDs, and one
/// record per photo, named and filed as the Receipts folder names them.
@MainActor
struct SyncReceiptTests {
    private func names(_ photos: [ReceiptPhoto]) -> [String] {
        photos.map { SyncRecordName.make(ReceiptSyncKind.type, $0.id) }
    }

    @Test func anExpensesPhotoIDsFollowItsReceiptsInOrder() {
        let first = ReceiptPhoto(), second = ReceiptPhoto(), third = ReceiptPhoto()
        var expense = Expense(title: "Dinner", amount: 80, receipts: [second, first, third])
        #expect(expense.receiptPhotoIDs == [second.id, first.id, third.id])
        expense.receipts = ReceiptList.adding([ReceiptPhoto()], to: expense.receipts)
        #expect(expense.receiptPhotoIDs == expense.receipts.map(\.id))
        #expect(Expense(title: "Coffee", amount: 4).receiptPhotoIDs.isEmpty)

        let account = Account(name: "Personal", expenses: [expense])
        #expect(ReceiptSyncKind.records(in: Database(accounts: [account])).map(\.name) == names(expense.receipts))
    }

    @Test func aRemovedReceiptLeavesTheSyncedList() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let first = ReceiptPhoto(), second = ReceiptPhoto(), third = ReceiptPhoto()
        var expense = Expense(title: "Dinner", amount: 80, receipts: [first, second, third])
        store.saveExpense(expense, in: account.id)
        #expect(ReceiptSyncKind.records(in: store.database).map(\.name) == names([first, second, third]))
        let stamped = try #require(store.account(id: account.id)?.expenses.first?.updatedAt)

        // Edit Expense takes the second off and saves, through the store.
        expense.receipts = [first, third]
        store.saveExpense(expense, in: account.id, now: stamped.addingTimeInterval(60))
        let saved = try #require(store.account(id: account.id)?.expenses.first)
        #expect(saved.receiptPhotoIDs == [first.id, third.id])
        #expect(saved.updatedAt > stamped)
        #expect(ReceiptSyncKind.records(in: store.database).map(\.name) == names([first, third]))
        #expect(ReceiptSyncKind.record(named: names([second])[0], in: store.database) == nil)
    }

    @Test func syncFilesPhotosUnderTheFolderNames() {
        let photo = ReceiptPhoto()
        #expect(ReceiptSyncKind.fileName(for: photo.id) == photo.fileName)
        let assets = ReceiptSyncKind.assets(named: SyncRecordName.make(ReceiptSyncKind.type, photo.id))
        #expect(assets.map(\.fileName) == [photo.fileName])
        #expect(ReceiptFolder.writingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
    }
}
