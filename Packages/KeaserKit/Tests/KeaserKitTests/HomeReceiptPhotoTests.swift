import Foundation
import Testing
@testable import KeaserKit

private let coffeeID = UUID(uuidString: "5B1F3C2E-8D4A-4E6B-9C0D-1A2B3C4D5E6F")!
private let photoID = UUID(uuidString: "0D9E8F7A-6B5C-4D3E-8F1A-2B3C4D5E6F70")!
private let secondID = UUID(uuidString: "7C6B5A49-3827-4165-9F8E-7D6C5B4A3928")!

/// An expense as a version without receipts wrote it.
private let oldExpenseJSON = """
{"amount":4.5,"createdAt":780000000,"date":780000000,"id":"\(coffeeID.uuidString)","title":"Coffee","updatedAt":780000000}
"""

/// `oldExpenseJSON` with `extra` (a `"key":value` pair) added.
private func expenseJSON(adding extra: String) -> String {
    oldExpenseJSON.replacingOccurrences(of: "}", with: ",\(extra)}")
}

private func decodeExpense(_ json: String) throws -> Expense {
    try DatabaseFile.makeDecoder().decode(Expense.self, from: Data(json.utf8))
}

struct ReceiptPhotoDecodingTests {
    @Test func anExpenseWithoutReceiptsReadsAndWritesAsBefore() throws {
        let expense = try decodeExpense(oldExpenseJSON)
        #expect(expense.title == "Coffee")
        #expect(expense.receipts.isEmpty)
        // Written back, it has no receipts key: files stay as they were.
        let written = String(decoding: try DatabaseFile.makeEncoder().encode(expense), as: UTF8.self)
        #expect(written == oldExpenseJSON)
    }

    @Test func receiptsRoundTripInOrder() throws {
        let json = expenseJSON(adding: #""receipts":[{"id":"\#(secondID.uuidString)"},{"id":"\#(photoID.uuidString)"}]"#)
        let expense = try decodeExpense(json)
        #expect(expense.receipts == [ReceiptPhoto(id: secondID), ReceiptPhoto(id: photoID)])
        let again = try DatabaseFile.makeDecoder().decode(Expense.self, from: DatabaseFile.makeEncoder().encode(expense))
        #expect(again == expense)
    }

    @Test func theSingleReceiptKeyBecomesAListOfOne() throws {
        let expense = try decodeExpense(expenseJSON(adding: #""receipt":{"id":"\#(photoID.uuidString)"}"#))
        #expect(expense.receipts == [ReceiptPhoto(id: photoID)])
        // Written back under the list's key only.
        let written = String(decoding: try DatabaseFile.makeEncoder().encode(expense), as: UTF8.self)
        #expect(written.contains(#""receipts":[{"id":"\#(photoID.uuidString)"}]"#))
        #expect(!written.contains(#""receipt":"#))
    }

    @Test func aReceiptThatDoesNotReadLosesOnlyThatPhoto() throws {
        let list = try decodeExpense(expenseJSON(adding: #""receipts":[{"id":"not a uuid"},{"id":"\#(photoID.uuidString)"},7]"#))
        #expect(list.title == "Coffee")
        #expect(list.receipts == [ReceiptPhoto(id: photoID)])
        let notAList = try decodeExpense(expenseJSON(adding: #""receipts":"nope""#))
        #expect(notAList.receipts.isEmpty)
        let single = try decodeExpense(expenseJSON(adding: #""receipt":{"id":"not a uuid"}"#))
        #expect(single.receipts.isEmpty)
    }

    @Test func theDatabaseListsEveryPhotoOfEveryExpense() {
        var personal = Account(name: "Personal")
        personal.expenses = [
            Expense(title: "Coffee", amount: 4, receipts: [ReceiptPhoto(id: photoID), ReceiptPhoto(id: secondID)]),
            Expense(title: "Lunch", amount: 12),
        ]
        var business = Account(name: "Business")
        let taxi = ReceiptPhoto()
        business.expenses = [Expense(title: "Taxi", amount: 38, receipts: [taxi])]
        let database = Database(accounts: [personal, business])
        #expect(database.receiptPhotos == [ReceiptPhoto(id: photoID), ReceiptPhoto(id: secondID), taxi])
    }
}

struct ReceiptListTests {
    @Test func anExpenseKeepsAtMostTen() {
        #expect(ReceiptList.maximum == 10)
        #expect(ReceiptList.room(after: 0) == 10)
        #expect(ReceiptList.room(after: 7) == 3)
        #expect(ReceiptList.room(after: 10) == 0)
        #expect(ReceiptList.room(after: 12) == 0)
    }

    @Test func addingKeepsTheOrderAndStopsAtTheCap() {
        #expect(ReceiptList.adding([4, 5], to: [1, 2, 3]) == [1, 2, 3, 4, 5])
        // A four-page scan onto eight receipts: the first two pages fit.
        #expect(ReceiptList.adding(["i", "j", "k", "l"], to: Array(repeating: "a", count: 8)).suffix(3) == ["a", "i", "j"])
        #expect(ReceiptList.adding(Array(1...12), to: []) == Array(1...10))
        #expect(ReceiptList.adding([11], to: Array(1...10)) == Array(1...10))
    }

    @Test func onlyPhotosNoExpenseKeepsAreReleased() {
        let first = ReceiptPhoto(), second = ReceiptPhoto(), third = ReceiptPhoto()
        // Edit Expense took the second of three off.
        #expect(ReceiptList.released(from: [first, second, third], inUse: [first, third]) == [second])
        #expect(ReceiptList.released(from: [first], inUse: [first]).isEmpty)
        #expect(ReceiptList.released(from: [first, second], inUse: []) == [first, second])
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

    @Test func removingPhotosDeletesOnlyTheirFiles() throws {
        let folder = tempFolder()
        let kept = try folder.add(Data([1]))
        let gone = try folder.add(Data([2]))
        #expect(folder.remove([gone, ReceiptPhoto()]) == [gone])
        #expect(folder.data(for: gone) == nil)
        #expect(folder.data(for: kept) == Data([1]))
    }
}

@MainActor
struct ReceiptStoreTests {
    private func tempFolder() -> ReceiptFolder {
        ReceiptFolder(url: FileManager.default.temporaryDirectory
            .appending(path: "keaser-receipts-\(UUID().uuidString)/Keaser/Receipts", directoryHint: .isDirectory))
    }

    @Test func savingKeepsTheReceiptsInOrderAndAnEditCanRemoveOne() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let first = ReceiptPhoto(), second = ReceiptPhoto()
        var expense = Expense(title: "Coffee", amount: 4, receipts: [first, second])
        store.saveExpense(expense, in: account.id)
        #expect(store.account(id: account.id)?.expenses.first?.receipts == [first, second])
        #expect(store.receiptPhotosInUse == [first, second])

        expense.receipts = [second]
        store.saveExpense(expense, in: account.id)
        #expect(store.account(id: account.id)?.expenses.first?.receipts == [second])
        #expect(store.receiptPhotosInUse == [second])
    }

    @Test func removingOneReceiptDeletesOnlyItsFileOnceTheEditIsSaved() throws {
        let folder = tempFolder()
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let first = try folder.add(Data([1])), second = try folder.add(Data([2])), third = try folder.add(Data([3]))
        var expense = Expense(title: "Dinner", amount: 80, receipts: [first, second, third])
        store.saveExpense(expense, in: account.id)
        let before = expense.receipts

        // Edit Expense takes the second off, then saves, as the editor does.
        expense.receipts = [first, third]
        store.saveExpense(expense, in: account.id)
        let released = ReceiptList.released(from: before, inUse: store.database.receiptPhotos)
        #expect(released == [second])
        folder.remove(released)
        #expect(Set(folder.files().map(\.name)) == [first.fileName, third.fileName])
    }

    @Test func deletingAnExpenseLetsTheCleanUpTakeAllItsReceipts() throws {
        let folder = tempFolder()
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let kept = try folder.add(Data([0]))
        let photos = try (1...3).map { try folder.add(Data([UInt8($0)])) }
        store.saveExpense(Expense(title: "Lunch", amount: 12, receipts: [kept]), in: account.id)
        let dinner = Expense(title: "Dinner", amount: 80, receipts: photos)
        store.saveExpense(dinner, in: account.id)
        store.deleteExpense(dinner.id, in: account.id)

        let inUse = try #require(store.receiptPhotosInUse)
        #expect(inUse == [kept])
        // A day later, at launch.
        let removed = folder.removeOrphans(keeping: inUse, now: .now + ReceiptFolder.gracePeriod + 60)
        #expect(Set(removed) == Set(photos.map(\.fileName)))
        #expect(folder.files().map(\.name) == [kept.fileName])
    }

    @Test func undoingADeleteBringsEveryReceiptBack() {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let photos = [ReceiptPhoto(), ReceiptPhoto()]
        store.saveExpense(Expense(title: "Coffee", amount: 4, receipts: photos), in: account.id)
        let deletion = ExpenseDeletion(ids: store.accounts[0].expenses.map(\.id), in: store.database)
        #expect(deletion.items.first?.expense.receipts == photos)

        #expect(store.delete(deletion))
        #expect(store.receiptPhotosInUse == [])
        #expect(store.restore(deletion.items))
        #expect(store.accounts[0].expenses.first?.receipts == photos)
        #expect(store.receiptPhotosInUse == Set(photos))
    }

    @Test func nothingIsCleanedUpWithoutAnAccount() {
        #expect(KeaserStore(file: nil).receiptPhotosInUse == nil)
    }

    @Test func nothingIsCleanedUpWhenTheDatabaseCannotBeRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "keaser-receipts-\(UUID().uuidString)/Keaser/database.json")
        let file = DatabaseFile(url: url)
        let writer = KeaserStore(file: file)
        let account = writer.createAccount(name: "Personal")
        writer.saveExpense(Expense(title: "Coffee", amount: 4, receipts: [ReceiptPhoto()]), in: account.id)
        // Unreadable, as before the first unlock after a restart.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let store = KeaserStore(file: file)
        #expect(store.loadError != nil)
        #expect(store.receiptPhotosInUse == nil)
    }
}

struct ReceiptFillTests {
    private let draft = ReceiptDraft(merchant: "Trader Joe's", total: Decimal(string: "12.50"), day: ReceiptDay(year: 2026, month: 9, day: 21))

    @Test func anEmptyCardTakesEverything() {
        let fill = ReceiptFill(draft, titleIsEmpty: true, amountIsEmpty: true, dateIsUntouched: true)
        #expect(fill.title == "Trader Joe's")
        #expect(fill.total == Decimal(string: "12.50"))
        #expect(fill.day == ReceiptDay(year: 2026, month: 9, day: 21))
    }

    @Test func whatThePersonTypedIsNeverReplaced() {
        let fill = ReceiptFill(draft, titleIsEmpty: false, amountIsEmpty: true, dateIsUntouched: false)
        #expect(fill.title == nil)
        #expect(fill.total == Decimal(string: "12.50"))
        #expect(fill.day == nil)
        #expect(ReceiptFill(draft, titleIsEmpty: false, amountIsEmpty: false, dateIsUntouched: false).isEmpty)
    }

    @Test func aLaterReceiptOnAFilledInExpenseIsNotRead() {
        #expect(ReceiptFill.wantsReading(titleIsEmpty: true, amountIsEmpty: true))
        #expect(ReceiptFill.wantsReading(titleIsEmpty: false, amountIsEmpty: true))
        #expect(ReceiptFill.wantsReading(titleIsEmpty: true, amountIsEmpty: false))
        #expect(!ReceiptFill.wantsReading(titleIsEmpty: false, amountIsEmpty: false))
    }

    @Test func voiceOverHearsTheReceiptsAndTheWholeNoteAtOnce() {
        let warning = ReceiptDraft(merchant: "Café de Flore", total: 14.5, currencyCode: "EUR").note(recordingIn: "USD")
        #expect(ReceiptFill.announcement(attached: 1, note: warning)
            == "Receipt attached. Filled in from your receipt, which shows EUR. Keaser records amounts in USD, so check the amount before saving.")
        #expect(ReceiptFill.announcement(attached: 3, note: draft.note(recordingIn: "USD"))
            == "3 receipts attached. Filled in from your receipt. Check the details before saving.")
        #expect(ReceiptFill.announcement(attached: 0, note: warning) == warning)
        #expect(ReceiptFill.announcement(attached: 2, note: nil) == "2 receipts attached.")
        #expect(ReceiptFill.announcement(attached: 0, note: nil) == nil)
    }
}

@MainActor
struct ReceiptPagesReadingTests {
    private let grocery = ReceiptSamples.named("grocery")!

    @Test func pagesAreReadTogetherInOrderAsOneReceipt() async {
        // The long receipt in two photos: the shop on the first, the total
        // at the foot of the second.
        let split = grocery.lines.firstIndex { $0.hasPrefix("TAX") }!
        let pages = [Array(grocery.lines[..<split]), Array(grocery.lines[split...])]
        #expect(!pages[0].contains { $0.hasPrefix("TOTAL") })

        let draft = await ReceiptReading.read(pages: pages, model: nil, today: ReceiptSamples.today, prefersMonthFirst: true)
        #expect(draft.merchant == "Trader Joe's")
        #expect(draft.total == Decimal(string: "12.50"))
        #expect(draft.day == ReceiptDay(year: 2026, month: 9, day: 21))
        #expect(draft == (await ReceiptReading.read(grocery.lines, model: nil, today: ReceiptSamples.today, prefersMonthFirst: true)))
    }

    @Test func theModelIsAskedAboutEveryPageAtOnceInOrder() async throws {
        let split = grocery.lines.firstIndex { $0.hasPrefix("TAX") }!
        let first = Array(grocery.lines[..<split]), second = Array(grocery.lines[split...])
        let model = FakeReceiptModel(nil)
        _ = await ReceiptReading.read(pages: [first, second], model: model, today: ReceiptSamples.today, prefersMonthFirst: true)
        #expect(model.prompts.count == 1)
        let prompt = try #require(model.prompts.first)
        let shop = try #require(prompt.range(of: "TRADER JOE'S"))
        let total = try #require(prompt.range(of: "TOTAL $12.50"))
        #expect(shop.lowerBound < total.lowerBound)
        #expect(prompt == ReceiptPrompt.prompt(for: grocery.lines))
    }
}
