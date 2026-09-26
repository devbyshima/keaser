import Foundation
import Testing
@testable import KeaserKit

enum NotionTestData {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func column(_ name: String, _ type: NotionPropertyType, id: String? = nil) -> NotionPropertySchema {
        NotionPropertySchema(id: id ?? (type == .title ? "title" : "id-\(name)"), name: name, type: type)
    }

    static func source(_ columns: [NotionPropertySchema]) -> NotionDataSource {
        NotionDataSource(id: "ds-1", title: "Expenses", databaseID: "db-1", properties: columns)
    }

    static let standard = source([
        column("Name", .title),
        column("Amount", .number),
        column("Category", .select),
        column("Payment", .select),
        column("Date", .date),
        column("Notes", .richText),
    ])

    static var standardMapper: ExpenseMapper {
        ExpenseMapper(map: NotionPropertyMatcher.autoMap(standard)!.resolved(in: standard)!, calendar: utc)
    }

    /// A row as Notion would return it after the mapper's writes.
    static func page(
        id: String,
        _ writes: [String: NotionPropertyWrite],
        in source: NotionDataSource = standard,
        created: Date = Date(timeIntervalSince1970: 1_789_000_000),
        edited: Date = Date(timeIntervalSince1970: 1_789_000_000),
        removed: Bool = false
    ) -> NotionPage {
        var values: [String: NotionPropertyValue] = [:]
        for (name, write) in writes {
            let column = source.property(named: name)!
            var value = NotionPropertyValue(id: column.id, type: column.type)
            switch write {
            case .title(let text), .richText(let text): value.text = text
            case .number(let number): value.number = number
            case .select(let option): value.names = option.map { [$0] } ?? []
            case .multiSelect(let options): value.names = options
            case .date(let day): value.dateStart = day
            }
            values[name] = value
        }
        return NotionPage(
            id: id, createdTime: created, lastEditedTime: edited, inTrash: removed,
            parent: NotionParent(type: "data_source_id", databaseID: "db-1", dataSourceID: "ds-1"),
            properties: values
        )
    }
}

struct NotionAutoMappingTests {
    @Test func mapsTheObviousSchema() throws {
        let map = try #require(NotionPropertyMatcher.autoMap(NotionTestData.standard))
        #expect(map.title == "Name")
        #expect(map.amount == "Amount")
        #expect(map.category == "Category")
        #expect(map.paymentMethod == "Payment")
        #expect(map.date == "Date")
        #expect(map.amountID == "id-Amount")
    }

    @Test func mapsSynonymsAndTextPaymentColumns() throws {
        let source = NotionTestData.source([
            NotionTestData.column("Item", .title),
            NotionTestData.column("Cost", .number),
            NotionTestData.column("Type", .select),
            NotionTestData.column("Paid With", .richText),
            NotionTestData.column("Day", .date),
            NotionTestData.column("Trip", .select),
        ])
        let map = try #require(NotionPropertyMatcher.autoMap(source))
        #expect(map.title == "Item")
        #expect(map.amount == "Cost")
        #expect(map.category == "Type")
        #expect(map.paymentMethod == "Paid With")
        #expect(map.date == "Day")
    }

    @Test func paymentTypeGoesToPaymentNotCategory() throws {
        let source = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Payment Type", .select),
            NotionTestData.column("Total Price", .number),
            NotionTestData.column("Net", .number),
        ])
        let map = try #require(NotionPropertyMatcher.autoMap(source))
        #expect(map.paymentMethod == "Payment Type")
        #expect(map.category == nil)
        #expect(map.amount == "Total Price")
    }

    @Test func guessesALoneNumberOrDateButNeverALoneSelect() throws {
        let source = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Euros", .number),
            NotionTestData.column("Logged", .date),
            NotionTestData.column("Mood", .select),
        ])
        let map = try #require(NotionPropertyMatcher.autoMap(source))
        #expect(map.amount == "Euros")
        #expect(map.date == "Logged")
        #expect(map.category == nil)
        #expect(map.paymentMethod == nil)
    }

    @Test func noTitleNoMap() {
        #expect(NotionPropertyMatcher.autoMap(NotionTestData.source([NotionTestData.column("Amount", .number)])) == nil)
    }

    @Test func resolvingFollowsRenamesAndDropsChangedTypes() throws {
        let map = try #require(NotionPropertyMatcher.autoMap(NotionTestData.standard))
        let renamed = NotionTestData.source([
            NotionTestData.column("Title", .title),
            NotionTestData.column("Spent", .number, id: "id-Amount"),
            NotionTestData.column("Category", .richText, id: "id-Category"),
            NotionTestData.column("Payment", .select),
        ])
        let resolved = try #require(map.resolved(in: renamed))
        #expect(resolved.title.name == "Title")
        #expect(resolved.amount?.name == "Spent")
        #expect(resolved.category == nil)
        #expect(resolved.paymentMethod?.name == "Payment")
        #expect(resolved.date == nil)
        #expect(resolved.map.amount == "Spent")
    }

    @Test func candidatesListBestGuessFirst() {
        let source = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Tip", .number),
            NotionTestData.column("Amount", .number),
        ])
        #expect(NotionPropertyMatcher.candidates(for: .amount, in: source).map(\.name) == ["Amount", "Tip"])
    }

    @Test func keaserSchemaUsesTheCurrencyFormat() {
        #expect(NotionKeaserSchema.numberFormat(for: "usd") == "dollar")
        #expect(NotionKeaserSchema.numberFormat(for: "JPY") == "yen")
        #expect(NotionKeaserSchema.numberFormat(for: "RWF") == "number_with_commas")
        let schema = NotionKeaserSchema.properties(currencyCode: "GBP", categories: ["Food"], paymentMethods: ["Cash"])
        #expect(schema["Amount"] == .number(format: "pound"))
        #expect(schema["Name"] == .title)
        #expect(Set(schema.keys) == ["Name", "Amount", "Category", "Payment", "Date", "Keaser ID"])
        #expect(schema["Keaser ID"] == .richText)
    }

    @Test func theKeaserIDPropertyIsFoundByNameButNeverOfferedForAField() throws {
        let source = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Amount", .number),
            NotionTestData.column("Keaser ID", .richText),
        ])
        #expect(NotionPropertyMatcher.candidates(for: .paymentMethod, in: source).isEmpty)
        let map = try #require(NotionPropertyMatcher.autoMap(source))
        #expect(map.paymentMethod == nil)
        let resolved = try #require(map.resolved(in: source))
        #expect(resolved.keaserID?.name == "Keaser ID")
        #expect(resolved.map.keaserIDPropertyID == "id-Keaser ID")

        // Renamed in Notion: followed by its ID.
        let renamed = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Keaser Ref", .richText, id: "id-Keaser ID"),
        ])
        #expect(resolved.map.resolved(in: renamed)?.keaserID?.name == "Keaser Ref")
    }

    @Test func aKeaserIDPropertyOfAnotherTypeOrInUseIsLeftAlone() throws {
        let number = NotionTestData.source([NotionTestData.column("Name", .title), NotionTestData.column("Keaser ID", .number)])
        #expect(NotionPropertyMap(title: "Name").resolved(in: number)?.keaserID == nil)

        let text = NotionTestData.source([NotionTestData.column("Name", .title), NotionTestData.column("Keaser ID", .richText)])
        var map = NotionPropertyMap(title: "Name")
        map.set(.paymentMethod, to: text.property(named: "Keaser ID"))
        let resolved = try #require(map.resolved(in: text))
        #expect(resolved.paymentMethod?.name == "Keaser ID")
        #expect(resolved.keaserID == nil)
    }
}

struct ExpenseMapperTests {
    @Test func roundTripsAnExpense() throws {
        let mapper = NotionTestData.standardMapper
        var account = Account(name: "Personal")
        let food = try #require(account.categories.first { $0.name == "Food & Drinks" })
        let cash = try #require(account.paymentMethods.first { $0.name == "Cash" })
        let day = try #require(NotionTestData.utc.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let original = Expense(title: "Lunch", amount: Decimal(string: "12.35")!, categoryID: food.id, paymentMethodID: cash.id, date: day)

        let writes = mapper.properties(for: original, in: account)
        #expect(writes["Name"] == .title("Lunch"))
        #expect(writes["Amount"] == .number(Decimal(string: "12.35")))
        #expect(writes["Category"] == .select("Food & Drinks"))
        #expect(writes["Payment"] == .select("Cash"))
        #expect(writes["Date"] == .date("2026-09-20"))

        let page = NotionTestData.page(id: "p1", writes)
        #expect(mapper.matches(original, page, in: account))
        let pulled = mapper.makeExpense(from: page, in: &account)
        #expect(pulled.title == original.title)
        #expect(pulled.amount == original.amount)
        #expect(pulled.categoryID == food.id)
        #expect(pulled.paymentMethodID == cash.id)
        #expect(pulled.date == day)
        #expect(pulled.notionPageID == "p1")
        #expect(account.categories.count == ExpenseCategory.defaults().count)
    }

    @Test func unknownNamesCreateCategoriesAndMethods() throws {
        let mapper = NotionTestData.standardMapper
        var account = Account(name: "Personal")
        let page = NotionTestData.page(id: "p1", [
            "Name": .title("Vet"), "Amount": .number(80), "Category": .select("Pets"), "Payment": .select("Apple Pay"),
        ])
        let expense = mapper.makeExpense(from: page, in: &account)
        let category = try #require(account.category(id: expense.categoryID))
        let method = try #require(account.paymentMethod(id: expense.paymentMethodID))
        #expect(category.name == "Pets")
        #expect(category.symbol == "pawprint.fill")
        #expect(method.name == "Apple Pay")
        #expect(method.symbol == "wallet.bifold.fill")
        #expect(NotionSymbolGuess.category(for: "Miscellaneous") == "tag.fill")
    }

    @Test func namesMatchLooselyAndCommasAreStripped() throws {
        let mapper = NotionTestData.standardMapper
        var account = Account(name: "Personal", categories: [ExpenseCategory(name: "Food, Drinks", symbol: "fork.knife")])
        let expense = Expense(title: "Tea", amount: 3, categoryID: account.categories[0].id)
        #expect(mapper.properties(for: expense, in: account)["Category"] == .select("Food Drinks"))
        let page = NotionTestData.page(id: "p", ["Name": .title("Tea"), "Amount": .number(3), "Category": .select("food drinks")])
        let pulled = mapper.makeExpense(from: page, in: &account)
        #expect(pulled.categoryID == account.categories[0].id)
        #expect(account.categories.count == 1)
    }

    @Test func emptyMappedValuesClearAndUnmappedOnesAreLeftAlone() throws {
        let source = NotionTestData.source([NotionTestData.column("Name", .title), NotionTestData.column("Category", .select)])
        let mapper = ExpenseMapper(map: try #require(NotionPropertyMatcher.autoMap(source)?.resolved(in: source)), calendar: NotionTestData.utc)
        var account = Account(name: "Personal")
        var expense = Expense(title: "Old", amount: 42, categoryID: account.categories[0].id, paymentMethodID: account.paymentMethods[0].id)
        let page = NotionTestData.page(id: "p", ["Name": .title("New"), "Category": .select(nil)], in: source)
        #expect(mapper.apply(mapper.remoteExpense(from: page), to: &expense, in: &account))
        #expect(expense.title == "New")
        #expect(expense.categoryID == nil)
        #expect(expense.amount == 42)
        #expect(expense.paymentMethodID == account.paymentMethods[0].id)
        #expect(mapper.properties(for: expense, in: account).keys.sorted() == ["Category", "Name"])
    }

    @Test func textAndMultiSelectPaymentColumns() throws {
        let source = NotionTestData.source([
            NotionTestData.column("Name", .title),
            NotionTestData.column("Tags", .multiSelect),
            NotionTestData.column("Card", .richText),
        ])
        let mapper = ExpenseMapper(map: try #require(NotionPropertyMatcher.autoMap(source)?.resolved(in: source)), calendar: NotionTestData.utc)
        let account = Account(name: "Personal")
        let expense = Expense(title: "Bus", amount: 2, categoryID: account.categories[0].id, paymentMethodID: account.paymentMethods[2].id)
        let writes = mapper.properties(for: expense, in: account)
        #expect(writes["Tags"] == .multiSelect(["Food & Drinks"]))
        #expect(writes["Card"] == .richText("Cash"))
    }

    @Test func writesAndReadsTheKeaserID() throws {
        let source = NotionTestData.source([NotionTestData.column("Name", .title), NotionTestData.column("Keaser ID", .richText)])
        let mapper = ExpenseMapper(map: try #require(NotionPropertyMap(title: "Name").resolved(in: source)), calendar: NotionTestData.utc)
        let expense = Expense(title: "Bus", amount: 2)
        let writes = mapper.properties(for: expense, in: Account(name: "Personal"))
        #expect(writes["Keaser ID"] == .richText(expense.id.uuidString))
        #expect(mapper.keaserID(of: NotionTestData.page(id: "p", writes, in: source)) == expense.id)
        #expect(mapper.keaserID(of: NotionTestData.page(id: "p", ["Keaser ID": .richText("  \(expense.id.uuidString.lowercased()) ")], in: source)) == expense.id)
        #expect(mapper.keaserID(of: NotionTestData.page(id: "p", ["Keaser ID": .richText("")], in: source)) == nil)
        #expect(mapper.keaserID(of: NotionTestData.page(id: "p", ["Keaser ID": .richText("not an id")], in: source)) == nil)
        // A page that says the same apart from the ID still matches.
        #expect(mapper.matches(expense, NotionTestData.page(id: "p", ["Name": .title("Bus")], in: source), in: Account(name: "Personal")))
    }

    @Test func blankRowsAreRecognised() {
        let mapper = NotionTestData.standardMapper
        #expect(mapper.remoteExpense(from: NotionTestData.page(id: "b", [:])).isBlank)
        #expect(!mapper.remoteExpense(from: NotionTestData.page(id: "b", ["Amount": .number(5)])).isBlank)
    }

    @Test func dateTimesKeepTheirWrittenDay() throws {
        let mapper = NotionTestData.standardMapper
        var page = NotionTestData.page(id: "p", ["Name": .title("Late")])
        page.properties["Date"] = NotionPropertyValue(id: "id-Date", type: .date, dateStart: "2026-09-15T23:30:00.000-04:00")
        #expect(mapper.remoteExpense(from: page).day == .some("2026-09-15"))
    }

    @Test func oldConnectionsDecodeWithoutNewFields() throws {
        let json = #"{"databaseID":"db","databaseTitle":"Expenses","properties":{"title":"Name","amount":"Amount"}}"#
        let connection = try JSONDecoder().decode(NotionConnection.self, from: Data(json.utf8))
        #expect(connection.dataSourceID == nil)
        #expect(connection.properties.amount == "Amount")
        #expect(connection.properties.amountID == nil)
        #expect(connection.properties.keaserID == nil)
        #expect(connection.lastSyncedAt == nil)
    }
}
