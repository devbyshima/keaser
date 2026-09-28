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
        for lines in ShortcutCardList.minLines...ShortcutCardList.maxLines {
            for count in 0...60 {
                for goBack in [false, true] {
                    for prefix in ["", "A long name for a label"] {
                        let options = labels(count: count, prefix: prefix)
                        var seen = Set<UUID>()
                        let first = ShortcutCardList(field: .category, options: options, current: nil, offersGoBack: goBack, lines: lines)
                        #expect(first.lineCount <= lines)
                        for page in 0..<first.pageCount {
                            let list = ShortcutCardList(field: .category, options: options, current: nil, offersGoBack: goBack, page: page, lines: lines)
                            #expect(list.lineCount <= lines)
                            #expect(!list.options.isEmpty || options.isEmpty)
                            seen.formUnion(list.options.map(\.id))
                        }
                        // Every option is on some page.
                        #expect(seen == Set(options.map(\.id)))
                    }
                }
            }
        }
    }

    /// Callout's line height at each text size, xSmall to AX5, as the card
    /// scales it from 21 points.
    private static let calloutLineHeights: [Double] = [15.8, 17.1, 18.4, 21, 23.6, 26.3, 28.9, 34.1, 42, 49.9, 57.8, 66.9]

    @Test func largerTextGetsFewerLines() {
        let budgets = Self.calloutLineHeights.map(ShortcutCardList.lines(forLineHeight:))
        #expect(budgets == [7, 7, 7, 7, 6, 6, 5, 5, 4, 3, 3, 3])
        #expect(budgets == budgets.sorted(by: >))
    }

    @Test func theFittedCardStaysUnder340Points() {
        for height in Self.calloutLineHeights {
            let lines = ShortcutCardList.lines(forLineHeight: height)
            let card = ShortcutCardList.cardChrome + height + Double(lines) * (height + ShortcutCardList.linePadding)
            // The largest accessibility sizes keep the three lines a
            // paged list needs, a little over.
            if lines > ShortcutCardList.minLines {
                #expect(card <= ShortcutCardList.cardHeightLimit, "at \(height) points")
            }
        }
    }

    @Test func aSmallBudgetPagesSooner() {
        let categories = ExpenseCategory.defaults().map { ShortcutFlow.Label(id: $0.id, name: $0.name) }
        // Seven short names, Go Back on: two columns in the default seven
        // lines; three lines give two rows of options, More and Go Back.
        let roomy = ShortcutCardList(field: .category, options: categories, current: categories[6].id, offersGoBack: true)
        #expect(roomy.pageCount == 1)
        let tight = ShortcutCardList(field: .category, options: categories, current: categories[6].id, offersGoBack: true, lines: 3)
        #expect(tight.lineBudget == 3)
        #expect(tight.columnCount == 2)
        #expect(tight.pageCount == 4)
        #expect(tight.page == 3)
        #expect(tight.options.map(\.name) == [categories[6].name])
        #expect(tight.lineCount == 3)
        // A budget below the minimum is raised to it.
        #expect(ShortcutCardList(field: .category, options: categories, current: nil, offersGoBack: true, lines: 1).lineBudget == ShortcutCardList.minLines)
    }

    @Test func anEmptyListSaysSo() {
        let list = ShortcutCardList(field: .paymentMethod, options: [], current: nil, offersGoBack: true)
        #expect(list.options.isEmpty)
        #expect(list.emptyText == "No payment methods in this account.")
        #expect(list.pageCount == 1)
        #expect(list.lineCount == 2)
        #expect(ShortcutCardList(field: .category, options: labels(count: 2), current: nil, offersGoBack: false).emptyText == nil)
    }

    @Test func aSourceMakesTheSameListAsTheFlow() {
        let personal = Account(name: "Personal")
        var flow = ShortcutFlow(accounts: [personal], accountID: personal.id, title: "Taxi", amount: 30, suggestionsEnabled: false)!
        _ = flow.start()
        let source = ShortcutCardList.Source(flow: flow, field: .category, page: 0)
        #expect(source.list() == ShortcutCardList(flow: flow, field: .category, page: 0))
        #expect(source.list(lines: 4) == ShortcutCardList(flow: flow, field: .category, page: 0, lines: 4))
        #expect(source.list(lines: 4).lineBudget == 4)
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
