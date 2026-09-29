import Foundation
import Testing
@testable import KeaserKit

struct SyncRecordTests {
    private func sampleDatabase() -> Database {
        var account = Account(name: "Personal")
        account.expenses = [
            Expense(title: "Coffee", amount: Decimal(string: "4.50")!, categoryID: account.categories[0].id),
            Expense(title: "Rent", amount: Decimal(string: "12345678901234567.89")!),
        ]
        return Database(accounts: [account])
    }

    @Test func everyRecordHasAStableNameTypeAndParent() throws {
        let database = sampleDatabase()
        let account = database.accounts[0]
        let records = SyncKinds.records(in: database)
        let names = Set(records.map(\.name))
        #expect(records.count == names.count)
        #expect(names.contains("Account.\(account.id.uuidString)"))
        #expect(names.contains("Category.\(account.categories[0].id.uuidString)"))
        #expect(names.contains("PaymentMethod.\(account.paymentMethods[0].id.uuidString)"))
        #expect(names.contains("Expense.\(account.expenses[0].id.uuidString)"))
        #expect(names.contains("Settings"))
        #expect(names.contains("Order.Accounts"))
        #expect(names.contains("Order.Categories.\(account.id.uuidString)"))
        #expect(names.contains("Order.PaymentMethods.\(account.id.uuidString)"))
        // 1 account, 7 categories, 5 payment methods, 2 expenses, settings, 3 orders.
        #expect(records.count == 19)
        for record in records where [.category, .paymentMethod, .expense].contains(record.type) {
            #expect(record.parent == account.id)
        }
        #expect(records.first { $0.type == .account }?.parent == nil)
    }

    @Test func aPayloadIsTheSameBytesEveryTimeAndReadsBackExactly() throws {
        let database = sampleDatabase()
        let record = try #require(ExpenseSyncKind.records(in: database).last)
        #expect(record.payload == record.payload)
        let read = try SyncRecord(name: record.name, type: record.type, payload: record.payload)
        #expect(read == record)
        var copy = database
        _ = ExpenseSyncKind.apply(read, to: &copy)
        // Money and dates survive digit for digit.
        #expect(copy.accounts[0].expenses[1] == database.accounts[0].expenses[1])
        #expect(copy.accounts[0].expenses[1].amount == Decimal(string: "12345678901234567.89"))
    }

    @Test func aBatchLookupFindsWhatOneByOneLookupsFind() {
        let database = sampleDatabase()
        let state = SyncState()
        let names = SyncKinds.records(in: database).map(\.name) + ["Expense.\(UUID().uuidString)", "Wallet.x"]
        let batch = SyncPlan.outgoingRecords(named: names, in: database, state: state)
        #expect(batch.count == 19)
        for name in names {
            #expect(batch[name] == SyncPlan.outgoingRecord(named: name, in: database, state: state))
        }
    }

    @Test func theLaterEditWinsAndATieIsDecidedByContent() {
        let early = SyncRecord(name: "Expense.X", type: .expense, modifiedAt: Date(timeIntervalSinceReferenceDate: 1), body: ["title": .string("a")])
        var late = early
        late.modifiedAt = Date(timeIntervalSinceReferenceDate: 2)
        #expect(late.wins(over: early))
        #expect(!early.wins(over: late))
        var other = early
        other.body = ["title": .string("b")]
        #expect(other.wins(over: early) != early.wins(over: other))
    }

    @Test func recordNamesSayWhatTheyStandFor() {
        let id = UUID()
        #expect(SyncKinds.kind(forName: SyncRecordName.make(.expense, id)) == ExpenseSyncKind.self)
        #expect(SyncKinds.kind(forName: SyncRecordName.categoriesOrder(id)) == OrderSyncKind.self)
        #expect(SyncKinds.kind(forName: SyncRecordName.settings) == SettingsSyncKind.self)
        #expect(SyncKinds.kind(forName: "Wallet.\(id.uuidString)") == nil)
        #expect(SyncRecordName.id(in: SyncRecordName.paymentMethodsOrder(id)) == id)
    }

    @Test func theSyncStateSurvivesBeingSaved() throws {
        var state = SyncState()
        state.userRecordName = "_abc"
        state.hasCompletedInitialSync = true
        state.known["Expense.X"] = KnownRecord(type: .expense, fingerprint: .max, modifiedAt: .now, parent: UUID(), extras: Data("{}".utf8), systemFields: Data([1, 2, 3]))
        state.known["Order.Accounts"] = KnownRecord(type: .order, fingerprint: 7, modifiedAt: .distantPast, orderIDs: [UUID()])
        state.tombstones["Expense.Y"] = Tombstone(type: .expense, deletedAt: .now)
        state.parked["Wallet.Z"] = FetchedRecord(name: "Wallet.Z", type: SyncRecordType("Wallet"), payload: Data("{}".utf8))
        state.receive(FetchedRecord(name: "Expense.W", type: .expense, payload: Data("{\"body\":{}}".utf8), systemFields: Data([9])))
        state.receiveDeletion(of: "Category.V", type: .category)
        let read = try #require(SyncState.decoded(from: try state.encoded()))
        #expect(read == state)
        #expect(SyncState.decoded(from: Data("not a state".utf8)) == nil)
    }

    @Test func statusLinesReadQuietly() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let us = Locale(identifier: "en_US")
        let utc = TimeZone(identifier: "UTC")!
        #expect(CloudSyncStatus.synced(now.addingTimeInterval(-20)).text(now: now) == "Synced with iCloud just now")
        #expect(CloudSyncStatus.synced(now.addingTimeInterval(-125)).text(now: now) == "Synced with iCloud 2 min ago")
        #expect(CloudSyncStatus.synced(now.addingTimeInterval(-3 * 3600)).text(now: now) == "Synced with iCloud 3 hr ago")
        #expect(CloudSyncStatus.synced(now.addingTimeInterval(-3 * 86_400)).text(now: now, locale: us, timeZone: utc) == "Synced with iCloud on May 6")
        #expect(CloudSyncStatus.iCloudOff.text(now: now) == "iCloud is off in Settings")
        #expect(CloudSyncStatus.waitingForNetwork.text(now: now) == "Waiting for network")
        #expect(CloudSyncStatus.preview(named: "synced", now: now) == .synced(now.addingTimeInterval(-120)))
        #expect(CloudSyncStatus.preview(named: "nonsense") == nil)
        for name in ["synced", "syncing", "offline", "off", "restricted", "otherAccount", "full", "unavailable", "failed"] {
            #expect(CloudSyncStatus.preview(named: name) != nil, "\(name)")
        }
    }
}

/// Later versions of Keaser, and data from before sync existed.
@MainActor
struct SyncSchemaToleranceTests {
    @Test func filesFromBeforeSyncStillLoad() throws {
        let id = UUID()
        let json = """
        {"version":1,"accounts":[{"id":"\(id.uuidString)","name":"Personal","createdAt":700000000,
        "categories":[{"id":"\(UUID().uuidString)","name":"Food","symbol":"fork.knife"}],
        "paymentMethods":[{"id":"\(UUID().uuidString)","name":"Cash","symbol":"banknote.fill"}],
        "expenses":[]}],"preferences":{"currencyCode":"EUR"}}
        """
        let database = try DatabaseFile.makeDecoder().decode(Database.self, from: Data(json.utf8))
        let account = try #require(database.accounts.first)
        #expect(account.updatedAt == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(account.categoriesOrderedAt == .distantPast)
        #expect(account.categories.first?.updatedAt == .distantPast)
        #expect(account.paymentMethods.first?.updatedAt == .distantPast)
        #expect(database.accountsOrderedAt == .distantPast)
        #expect(database.preferences.settingsUpdatedAt == .distantPast)
        #expect(database.preferences.currencyCode == "EUR")
    }

    /// A later version added a field to expenses; this one edits the
    /// expense and sends it back with the field untouched.
    @Test func fieldsFromALaterVersionSurviveAnEditHere() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        let expense = Expense(title: "Dinner", amount: 30)
        a.store.saveExpense(expense, in: personal.id)
        a.sync(cloud)
        let name = SyncRecordName.make(.expense, expense.id)
        var newer = try #require(SyncRecord(name: name, type: .expense, payload: try #require(cloud.records[name]).payload))
        newer.body["tip"] = .number(Decimal(string: "4.5")!)
        newer.body["tags"] = .array([.string("work"), .null])
        newer.modifiedAt = later(by: 5)
        newer.body["updatedAt"] = .number(Decimal(newer.modifiedAt.timeIntervalSinceReferenceDate))
        cloud.put(name: name, type: .expense, payload: newer.payload)

        a.sync(cloud)
        #expect(a.upload().isEmpty)
        var dinner = try #require(a.expense("Dinner"))
        dinner.title = "Dinner out"
        a.store.saveExpense(dinner, in: personal.id, now: later(by: 10))
        a.sync(cloud)
        #expect(a.upload().isEmpty)
        let body = try #require(cloud.body(of: name))
        #expect(body["title"] == .string("Dinner out"))
        #expect(body["tip"] == .number(Decimal(string: "4.5")!))
        #expect(body["tags"] == .array([.string("work"), .null]))
    }

    @Test func recordTypesFromALaterVersionAreKeptNotApplied() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        a.store.createAccount(name: "Personal")
        a.sync(cloud)
        let wallet = SyncRecord(name: "Wallet.\(UUID().uuidString)", type: SyncRecordType("Wallet"), modifiedAt: .now, body: ["currency": .string("EUR")])
        cloud.put(name: wallet.name, type: wallet.type, payload: wallet.payload)

        let before = a.database
        a.sync(cloud)
        #expect(a.database == before)
        #expect(a.state.parked[wallet.name] != nil)
        // Never deleted or overwritten from here, however often it syncs.
        a.store.createAccount(name: "Business")
        a.sync(cloud)
        a.sync(cloud)
        #expect(cloud.records[wallet.name]?.payload == wallet.payload)
        #expect(a.state.parked[wallet.name] != nil)
        let read = try #require(SyncState.decoded(from: try a.state.encoded()))
        #expect(read.parked[wallet.name] == a.state.parked[wallet.name])
    }

    @Test func recordsNeedingALaterReaderWaitAndAreNotOverwritten() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        let personal = a.store.createAccount(name: "Personal")
        let expense = Expense(title: "Dinner", amount: 30)
        a.store.saveExpense(expense, in: personal.id)
        a.sync(cloud)
        let name = SyncRecordName.make(.expense, expense.id)
        var future = try #require(SyncRecord(name: name, type: .expense, payload: try #require(cloud.records[name]).payload))
        future.readerVersion = SyncSchema.readerVersion + 1
        future.body["amount"] = .object(["value": .number(30), "currency": .string("EUR")])
        cloud.put(name: name, type: .expense, payload: future.payload)

        a.sync(cloud)
        #expect(a.expense("Dinner")?.amount == 30)
        #expect(a.state.parked[name] != nil)
        var dinner = try #require(a.expense("Dinner"))
        dinner.title = "Edited on an old version"
        a.store.saveExpense(dinner, in: personal.id)
        a.sync(cloud)
        #expect(cloud.records[name]?.payload == future.payload)
    }

    @Test func aPayloadThatIsNotAnEnvelopeIsKeptAside() throws {
        let cloud = TestCloud()
        let a = TestDevice()
        a.store.createAccount(name: "Personal")
        a.sync(cloud)
        let name = SyncRecordName.make(.expense, UUID())
        cloud.put(name: name, type: .expense, payload: Data("[1,2,3]".utf8))
        a.sync(cloud)
        #expect(a.state.parked[name] != nil)
        #expect(cloud.records[name] != nil)
    }

    @Test func aDeletedReceiptRecordLetsItsFileGo() {
        let photo = UUID()
        let name = SyncRecordName.make(ReceiptSyncKind.type, photo)
        #expect(ReceiptSyncKind.assets(named: name) == [SyncAsset(field: "file", fileName: "receipt-\(photo.uuidString).jpg")])
        #expect(ExpenseSyncKind.assets(named: SyncRecordName.make(.expense, photo)).isEmpty)
        let device = TestDevice()
        device.state.hasCompletedInitialSync = true
        device.state.receiveDeletion(of: name, type: ReceiptSyncKind.type)
        device.merge()
        #expect(device.lastRemovedAssets == ReceiptSyncKind.assets(named: name))
        // An expense without photos has no photo records.
        #expect(ReceiptSyncKind.records(in: Database(accounts: [Account(name: "A", expenses: [Expense(title: "x", amount: 1)])])).isEmpty)
    }
}

/// `KeaserStore` stamping edit times on local edits (`SyncStamps`).
@MainActor
struct SyncStampTests {
    @Test func aRenameStampsTheAccountOnly() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let before = try #require(store.account(id: account.id))
        store.renameAccount(account.id, to: "Home")
        let after = try #require(store.account(id: account.id))
        #expect(after.updatedAt > before.updatedAt)
        #expect(after.categories == before.categories)
        #expect(after.categoriesOrderedAt == before.categoriesOrderedAt)
    }

    @Test func editingALabelStampsItAndAddingOneStampsTheOrder() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        var food = account.categories[0]
        food.symbol = "cup.and.saucer.fill"
        store.saveCategory(food, in: account.id)
        let edited = try #require(store.account(id: account.id))
        #expect(edited.categories[0].updatedAt > account.categories[0].updatedAt)
        #expect(edited.categories[1] == account.categories[1])
        #expect(edited.categoriesOrderedAt == account.categoriesOrderedAt)

        store.saveCategory(ExpenseCategory(name: "Pets", symbol: "pawprint.fill"), in: account.id)
        #expect(try #require(store.account(id: account.id)).categoriesOrderedAt > account.categoriesOrderedAt)
        store.movePaymentMethods(in: account.id, fromOffsets: [0], toOffset: 3)
        #expect(try #require(store.account(id: account.id)).paymentMethodsOrderedAt > account.paymentMethodsOrderedAt)
    }

    @Test func deletingACategoryStampsTheExpensesItLeaves() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let food = account.categories[0]
        let then = Date(timeIntervalSinceNow: -60)
        store.saveExpense(Expense(title: "Lunch", amount: 10, categoryID: food.id), in: account.id, now: then)
        store.saveExpense(Expense(title: "Taxi", amount: 10), in: account.id, now: then)
        store.deleteCategory(food.id, in: account.id)
        let expenses = try #require(store.account(id: account.id)).expenses
        #expect(expenses[0].updatedAt > then)
        #expect(expenses[1].updatedAt == then)
    }

    @Test func accountOrderMovesWithAddsMovesAndDeletes() {
        let store = KeaserStore(file: nil)
        let one = store.createAccount(name: "One")
        let first = store.database.accountsOrderedAt
        #expect(first > .distantPast)
        store.createAccount(name: "Two")
        let second = store.database.accountsOrderedAt
        #expect(second > first)
        store.moveAccounts(fromOffsets: [1], toOffset: 0)
        let third = store.database.accountsOrderedAt
        #expect(third > second)
        store.deleteAccount(one.id)
        #expect(store.database.accountsOrderedAt > third)
    }

    @Test func onlySharedSettingsStampTheSettings() {
        let store = KeaserStore(file: nil)
        store.updatePreferences { $0.weeklySummaryEnabled = true }
        store.updatePreferences { $0.hasSeenWelcomeLetter = true }
        #expect(store.preferences.settingsUpdatedAt == .distantPast)
        store.updatePreferences { $0.currencyCode = "JPY" }
        #expect(store.preferences.settingsUpdatedAt > .distantPast)
    }

    @Test func anUndoneDeletionComesBackWithItsOwnTime() throws {
        let store = KeaserStore(file: nil)
        let account = store.createAccount(name: "Personal")
        let then = Date(timeIntervalSinceNow: -600)
        store.saveExpense(Expense(title: "Coffee", amount: 4), in: account.id, now: then)
        let deletion = ExpenseDeletion(ids: store.accounts[0].expenses.map(\.id), in: store.database)
        store.delete(deletion)
        store.restore(deletion.items)
        #expect(store.accounts[0].expenses.first?.updatedAt == then)
    }

    @Test func aMergeFromICloudIsNotStampedAndWaitsForLocalEdits() {
        let store = KeaserStore(file: nil)
        store.createAccount(name: "Personal")
        var merged = store.database
        merged.accounts[0].name = "From iCloud"
        merged.accounts[0].updatedAt = .distantPast
        let revision = store.revision
        store.updatePreferences { $0.currencyCode = "EUR" }
        #expect(store.applyCloudChanges(merged, ifRevision: revision) == .stale)
        #expect(store.accounts[0].name == "Personal")

        var changes: [StoreChange] = []
        store.addObserver { changes.append($0) }
        var current = store.database
        current.accounts[0].name = "From iCloud"
        current.accounts[0].updatedAt = .distantPast
        #expect(store.applyCloudChanges(current, ifRevision: store.revision) == .saved)
        #expect(store.accounts[0].name == "From iCloud")
        #expect(store.accounts[0].updatedAt == .distantPast)
        #expect(changes == [.mergedFromCloud])
    }
}
