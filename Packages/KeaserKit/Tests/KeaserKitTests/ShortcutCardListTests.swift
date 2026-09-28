import Foundation
import Testing
@testable import KeaserKit

private func labels(_ names: [String]) -> [ShortcutFlow.Label] {
    names.map { ShortcutFlow.Label(id: UUID(), name: $0) }
}

private func labels(count: Int, prefix: String = "Label") -> [ShortcutFlow.Label] {
    labels((1...max(count, 1)).map { "\(prefix) \($0)" }).prefix(count).map { $0 }
}

struct ShortcutCardListTests {
    @Test func aShortListRunsDownOneColumn() {
        let methods = labels(["Credit Card", "Debit Card", "Cash", "Bank Transfer", "E-Wallet"])
        let list = ShortcutCardList(field: .paymentMethod, options: methods, current: methods[2].id, offersGoBack: true)
        #expect(list.columnCount == 1)
        #expect(list.options.map(\.name) == methods.map(\.name))
        #expect(list.options.map(\.isCurrent) == [false, false, true, false, false])
        #expect(!list.offersMore)
        #expect(list.offersGoBack)
        #expect(list.lineCount == 6)
    }

    @Test func theDefaultCategoriesTakeTwoColumnsWithGoBack() {
        let categories = ExpenseCategory.defaults().map { ShortcutFlow.Label(id: $0.id, name: $0.name) }
        let list = ShortcutCardList(field: .category, options: categories, current: categories[1].id, offersGoBack: true)
        #expect(list.columnCount == 2)
        #expect(list.columns.map(\.count) == [4, 3])
        #expect(list.columns[0].map(\.name) == Array(categories.prefix(4)).map(\.name))
        #expect(list.lineCount == 5)
        // Without Go Back the seven fit one column.
        let plain = ShortcutCardList(field: .category, options: categories, current: nil, offersGoBack: false)
        #expect(plain.columnCount == 1)
        #expect(plain.lineCount == 7)
        #expect(plain.options.allSatisfy { !$0.isCurrent })
    }

    @Test func aLongListPagesAndOpensOnTheCurrentOption() {
        let many = labels(count: 19)
        let list = ShortcutCardList(field: .category, options: many, current: many[12].id, offersGoBack: true)
        #expect(list.columnCount == 2)
        #expect(list.pageCount == 2)
        #expect(list.page == 1)
        #expect(list.options.map(\.name) == many[10...].map(\.name))
        #expect(list.options.contains { $0.isCurrent && $0.name == "Label 13" })
        #expect(list.offersMore)
        #expect(list.pageText == "2 of 2")
        #expect(list.lineCount == ShortcutCardList.maxLines)

        let next = ShortcutCardList(field: .category, options: many, current: many[12].id, offersGoBack: true, page: list.page + 1)
        #expect(next.page == 0)
        #expect(next.options.count == 10)
        #expect(next.options.allSatisfy { !$0.isCurrent })
    }

    @Test func longNamesStayInOneColumn() {
        let long = labels(count: 8, prefix: "Shared household")
        let list = ShortcutCardList(field: .account, options: long, current: long[0].id, offersGoBack: true)
        #expect(list.columnCount == 1)
        #expect(list.pageCount == 2)
        #expect(list.options.count == 5)
        #expect(list.lineCount == 7)
    }

    @Test func neverTallerThanTheCardAllows() {
        for count in 0...60 {
            for goBack in [false, true] {
                for prefix in ["", "A long name for a label"] {
                    let options = labels(count: count, prefix: prefix)
                    var seen = Set<UUID>()
                    let first = ShortcutCardList(field: .category, options: options, current: nil, offersGoBack: goBack)
                    #expect(first.lineCount <= ShortcutCardList.maxLines)
                    for page in 0..<first.pageCount {
                        let list = ShortcutCardList(field: .category, options: options, current: nil, offersGoBack: goBack, page: page)
                        #expect(list.lineCount <= ShortcutCardList.maxLines)
                        seen.formUnion(list.options.map(\.id))
                    }
                    // Every option is on some page.
                    #expect(seen == Set(options.map(\.id)))
                }
            }
        }
    }

    @Test func anEmptyListSaysSo() {
        let list = ShortcutCardList(field: .paymentMethod, options: [], current: nil, offersGoBack: true)
        #expect(list.options.isEmpty)
        #expect(list.emptyText == "No payment methods in this account.")
        #expect(list.pageCount == 1)
        #expect(list.lineCount == 2)
        #expect(ShortcutCardList(field: .category, options: labels(count: 2), current: nil, offersGoBack: false).emptyText == nil)
    }

    @Test func theFlowsListFollowsItsAccountAndGoBackSetting() {
        let personal = Account(name: "Personal")
        let travel = Account(name: "Travel", categories: [ExpenseCategory(name: "Flights", symbol: "airplane")])
        var flow = ShortcutFlow(accounts: [personal, travel], accountID: personal.id, accountSupplied: true, title: "Taxi", amount: 30, goBackEnabled: false, suggestionsEnabled: false)!
        _ = flow.start()
        #expect(ShortcutCardList(flow: flow, field: .account).options.map(\.name) == ["Personal", "Travel"])
        #expect(ShortcutCardList(flow: flow, field: .account).options.first?.isCurrent == true)
        #expect(!ShortcutCardList(flow: flow, field: .category).offersGoBack)
        flow.change(.account, to: travel.id)
        #expect(ShortcutCardList(flow: flow, field: .category).options.map(\.name) == ["Flights"])
    }
}
