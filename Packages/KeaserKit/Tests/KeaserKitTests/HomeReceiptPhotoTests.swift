import Foundation
import Testing
@testable import KeaserKit

private let coffeeID = UUID(uuidString: "5B1F3C2E-8D4A-4E6B-9C0D-1A2B3C4D5E6F")!
private let photoID = UUID(uuidString: "0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70")!

/// An expense as a version without receipts wrote it.
private let oldExpenseJSON = """
{"amount":4.5,"createdAt":780000000,"date":780000000,"id":"\(coffeeID.uuidString)","title":"Coffee","updatedAt":780000000}
"""

private func decodeExpense(_ json: String) throws -> Expense {
    try DatabaseFile.makeDecoder().decode(Expense.self, from: Data(json.utf8))
}

struct ReceiptPhotoDecodingTests {
    @Test func anExpenseWithoutAReceiptReadsAsBefore() throws {
        let expense = try decodeExpense(oldExpenseJSON)
        #expect(expense.title == "Coffee")
        #expect(expense.receipt == nil)
        // Written back, it has no receipt key: files stay as they were.
        let written = String(decoding: try DatabaseFile.makeEncoder().encode(expense), as: UTF8.self)
        #expect(!written.contains("receipt"))
    }

    @Test func anExpenseWithAReceiptRoundTrips() throws {
        let json = oldExpenseJSON.replacingOccurrences(of: "}", with: #","receipt":{"id":"\#(photoID.uuidString)"}}"#)
        let expense = try decodeExpense(json)
        #expect(expense.receipt == ReceiptPhoto(id: photoID))
        let again = try DatabaseFile.makeDecoder().decode(Expense.self, from: DatabaseFile.makeEncoder().encode(expense))
        #expect(again == expense)
    }

    @Test func aReceiptThatDoesNotReadLosesOnlyThePhoto() throws {
        let json = oldExpenseJSON.replacingOccurrences(of: "}", with: #","receipt":{"id":"not a uuid"}}"#)
        let expense = try decodeExpense(json)
        #expect(expense.title == "Coffee")
        #expect(expense.receipt == nil)
    }

    @Test func theDatabaseListsEveryPhotoInUse() {
        var personal = Account(name: "Personal")
        personal.expenses = [
            Expense(title: "Coffee", amount: 4, receipt: ReceiptPhoto(id: photoID)),
            Expense(title: "Lunch", amount: 12),
        ]
        var business = Account(name: "Business")
        let taxi = ReceiptPhoto()
        business.expenses = [Expense(title: "Taxi", amount: 38, receipt: taxi)]
        let database = Database(accounts: [personal, business])
        #expect(database.receiptPhotos == [ReceiptPhoto(id: photoID), taxi])
    }
}

struct ReceiptPhotoNamingTests {
    @Test func aPhotoIsNamedAfterItsID() {
        let photo = ReceiptPhoto(id: photoID)
        #expect(photo.fileName == "receipt-0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70.jpg")
        #expect(ReceiptPhoto(fileName: photo.fileName) == photo)
        #expect(ReceiptPhoto(fileName: photo.fileName.lowercased()) == photo)
    }

    @Test func newPhotosNeverShareAName() {
        #expect(ReceiptPhoto().fileName != ReceiptPhoto().fileName)
    }

    @Test(arguments: [
        "database.json",
        ".DS_Store",
        "receipt-.jpg",
        "receipt-nope.jpg",
        "receipt-0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70.png",
        "0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70.jpg",
        "receipt-0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70.jpg.tmp",
    ])
    func otherFilesAreNotPhotos(_ name: String) {
        #expect(ReceiptPhoto(fileName: name) == nil)
    }
}

struct ReceiptOrphanTests {
    private let now = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private let hour: TimeInterval = 60 * 60

    @Test func onlyPhotosNoExpenseKeepsAndOlderThanADayGo() {
        let kept = ReceiptPhoto()
        let deletedLastWeek = ReceiptPhoto()
        let deletedJustNow = ReceiptPhoto()
        let files = [
            ReceiptFolder.File(name: kept.fileName, modified: now - 30 * 24 * hour),
            ReceiptFolder.File(name: deletedLastWeek.fileName, modified: now - 7 * 24 * hour),
            // Written an hour ago: perhaps for an expense still on its way
            // to the disk, or one undo may bring back.
            ReceiptFolder.File(name: deletedJustNow.fileName, modified: now - hour),
            ReceiptFolder.File(name: "database.json", modified: now - 30 * 24 * hour),
            ReceiptFolder.File(name: "notes.txt", modified: .distantPast),
        ]
        #expect(ReceiptFolder.orphans(among: files, keeping: [kept], now: now) == [deletedLastWeek.fileName])
    }

    @Test func theGracePeriodIsADay() {
        #expect(ReceiptFolder.gracePeriod == 24 * hour)
        let photo = ReceiptPhoto()
        let almost = [ReceiptFolder.File(name: photo.fileName, modified: now - 24 * hour + 1)]
        let exactly = [ReceiptFolder.File(name: photo.fileName, modified: now - 24 * hour)]
        #expect(ReceiptFolder.orphans(among: almost, keeping: [], now: now).isEmpty)
        #expect(ReceiptFolder.orphans(among: exactly, keeping: [], now: now) == [photo.fileName])
    }

    @Test func aFileFromTheFutureStays() {
        // The clock was set back since it was written.
        let photo = ReceiptPhoto()
        let files = [ReceiptFolder.File(name: photo.fileName, modified: now + 3 * 24 * hour)]
        #expect(ReceiptFolder.orphans(among: files, keeping: [], now: now).isEmpty)
    }
}

struct ReceiptFolderTests {
    private func tempFolder() -> ReceiptFolder {
        ReceiptFolder(url: FileManager.default.temporaryDirectory
            .appending(path: "keaser-receipts-\(UUID().uuidString)/Keaser/Receipts", directoryHint: .isDirectory))
    }

    private func setModified(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func theSharedFolderSitsBesideTheDatabase() {
        #expect(ReceiptFolder.shared.url.deletingLastPathComponent().standardizedFileURL
            == DatabaseFile.shared.url.deletingLastPathComponent().standardizedFileURL)
        #expect(ReceiptFolder.shared.url.lastPathComponent == "Receipts")
    }

    @Test func addingWritesOnePhotoPerCall() throws {
        let folder = tempFolder()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let first = try folder.add(jpeg)
        let second = try folder.add(jpeg)
        #expect(first != second)
        #expect(folder.data(for: first) == jpeg)
        #expect(Set(folder.files().map(\.name)) == [first.fileName, second.fileName])
        #expect(folder.data(for: ReceiptPhoto()) == nil)
    }

    @Test func removingOrphansLeavesPhotosInUseAndRecentOnes() throws {
        let folder = tempFolder()
        let inUse = try folder.add(Data([1]))
        let old = try folder.add(Data([2]))
        let recent = try folder.add(Data([3]))
        let lastMonth = Date.now - 30 * 24 * 60 * 60
        try setModified(lastMonth, of: folder.fileURL(for: inUse))
        try setModified(lastMonth, of: folder.fileURL(for: old))
        let stranger = folder.url.appending(path: "keep-me.txt")
        try Data([4]).write(to: stranger)
        try setModified(lastMonth, of: stranger)

        #expect(folder.removeOrphans(keeping: [inUse]) == [old.fileName])
        #expect(Set(folder.files().map(\.name)) == [inUse.fileName, recent.fileName, "keep-me.txt"])
        #expect(folder.data(for: old) == nil)
    }

    @Test func aFolderNotYetMadeHasNothingToRemove() {
        let folder = tempFolder()
        #expect(folder.files().isEmpty)
        #expect(folder.removeOrphans(keeping: []).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path))
    }
}

@MainActor
struct ReceiptStoreTests {
    @Test func savingKeepsTheReceiptAndAnEditCanRemoveIt() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let photo = ReceiptPhoto()
        var expense = Expense(title: "Coffee", amount: 4, receipt: photo)
        store.saveExpense(expense, in: account.id)
        #expect(store.account(id: account.id)?.expenses.first?.receipt == photo)
        #expect(store.receiptPhotosInUse == [photo])

        expense.receipt = nil
        store.saveExpense(expense, in: account.id)
        #expect(store.account(id: account.id)?.expenses.first?.receipt == nil)
        #expect(store.receiptPhotosInUse == [])
    }

    @Test func undoingADeleteBringsTheReceiptBack() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let photo = ReceiptPhoto()
        store.saveExpense(Expense(title: "Coffee", amount: 4, receipt: photo), in: account.id)
        let deletion = ExpenseDeletion(ids: store.accounts[0].expenses.map(\.id), in: store.database)
        #expect(deletion.items.first?.expense.receipt == photo)

        #expect(store.delete(deletion))
        #expect(store.receiptPhotosInUse == [])
        #expect(store.restore(deletion.items))
        #expect(store.accounts[0].expenses.first?.receipt == photo)
        #expect(store.receiptPhotosInUse == [photo])
    }

    @Test func nothingIsCleanedUpWithoutAnAccount() {
        #expect(KeaserStore(file: nil).receiptPhotosInUse == nil)
    }

    @Test func nothingIsCleanedUpWhenTheDatabaseCannotBeRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "keaser-receipts-\(UUID().uuidString)/Keaser/database.json")
        let file = DatabaseFile(url: url)
        let writer = KeaserStore(file: file)
        let account = writer.createAccount(name: "Personal")
        writer.saveExpense(Expense(title: "Coffee", amount: 4, receipt: ReceiptPhoto()), in: account.id)
        // Unreadable, as before the first unlock after a restart.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let store = KeaserStore(file: file)
        #expect(store.loadError != nil)
        #expect(store.receiptPhotosInUse == nil)
    }
}
