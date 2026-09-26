import Foundation
import Testing
@testable import KeaserKit

struct HomeExpenseQueryTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Saturday 26 Sep 2026, noon UTC.
    private var now: Date { day(2026, 9, 26) }

    private let food = UUID()
    private let travel = UUID()
    private let cash = UUID()
    private let card = UUID()

    private var expenses: [Expense] {
        [
            Expense(title: "Café au lait", amount: 4, categoryID: food, paymentMethodID: cash, date: day(2026, 9, 26), createdAt: day(2026, 9, 26, hour: 8)),
            Expense(title: "Dinner", amount: 40, categoryID: food, paymentMethodID: card, date: day(2026, 9, 26), createdAt: day(2026, 9, 26, hour: 20)),
            Expense(title: "Flight", amount: 300, categoryID: travel, paymentMethodID: card, date: day(2026, 9, 21)),
            Expense(title: "Lunch", amount: 12, categoryID: food, paymentMethodID: cash, date: day(2026, 9, 2)),
            Expense(title: "Hotel", amount: 150, categoryID: travel, paymentMethodID: card, date: day(2026, 3, 14)),
            Expense(title: "Old cafe", amount: 3, paymentMethodID: cash, date: day(2024, 6, 1)),
        ]
    }

    private func titles(_ filter: ExpenseQuery.Filter) -> [String] {
        ExpenseQuery.apply(filter, to: expenses, now: now, calendar: calendar).map(\.title)
    }

    @Test func periodsNarrowTheWindowAndSortNewestFirst() {
        #expect(titles(.init(period: .today)) == ["Dinner", "Café au lait"])
        #expect(titles(.init(period: .thisWeek)) == ["Dinner", "Café au lait", "Flight"])
        #expect(titles(.init(period: .thisMonth)) == ["Dinner", "Café au lait", "Flight", "Lunch"])
        #expect(titles(.init(period: .thisYear)) == ["Dinner", "Café au lait", "Flight", "Lunch", "Hotel"])
        #expect(titles(.init(period: .allTime)).count == 6)
    }

    @Test func weekFollowsTheFirstWeekday() {
        // Monday 21 Sep is inside a Monday week but the Sunday week began on
        // the 20th, so both contain it; Sunday 20 Sep separates them.
        var sunday = calendar
        sunday.firstWeekday = 1
        var monday = calendar
        monday.firstWeekday = 2
        let onSunday = [Expense(title: "Brunch", amount: 10, date: day(2026, 9, 20))]
        #expect(ExpenseQuery.apply(.init(period: .thisWeek), to: onSunday, now: now, calendar: sunday).count == 1)
        #expect(ExpenseQuery.apply(.init(period: .thisWeek), to: onSunday, now: now, calendar: monday).isEmpty)
    }

    @Test func categoryAndPaymentFiltersCombine() {
        #expect(titles(.init(period: .allTime, categoryID: travel)) == ["Flight", "Hotel"])
        #expect(titles(.init(period: .allTime, paymentMethodID: cash)) == ["Café au lait", "Lunch", "Old cafe"])
        #expect(titles(.init(period: .allTime, categoryID: food, paymentMethodID: card)) == ["Dinner"])
        #expect(titles(.init(period: .thisMonth, categoryID: travel)) == ["Flight"])
    }

    @Test func searchIgnoresCaseDiacriticsAndSurroundingSpaces() {
        #expect(titles(.init(period: .allTime, searchText: "CAFE")) == ["Café au lait", "Old cafe"])
        #expect(titles(.init(period: .allTime, searchText: "  café ")) == ["Café au lait", "Old cafe"])
        #expect(titles(.init(period: .thisMonth, searchText: "cafe")) == ["Café au lait"])
        #expect(titles(.init(period: .allTime, searchText: "zzz")).isEmpty)
        #expect(titles(.init(period: .allTime, searchText: "   ")).count == 6)
    }

    @Test func totalsAreExactDecimals() {
        let small = [
            Expense(title: "a", amount: Decimal(string: "0.1")!),
            Expense(title: "b", amount: Decimal(string: "0.2")!),
        ]
        #expect(ExpenseQuery.total(of: small) == Decimal(string: "0.3")!)
        #expect(ExpenseQuery.total(of: []) == 0)
    }

    @Test func initialFilterDependsOnPro() {
        #expect(ExpenseQuery.Filter.initial(isPro: true).period == .allTime)
        #expect(ExpenseQuery.Filter.initial(isPro: false).period == .thisMonth)
        #expect(!ExpenseQuery.Filter.initial(isPro: true).narrowsByLabel)
        #expect(ExpenseQuery.Filter(period: .today, categoryID: food).narrowsByLabel)
        #expect(ExpenseQuery.Filter(period: .today, searchText: " x ").isSearching)
        #expect(!ExpenseQuery.Filter(period: .today, searchText: "  ").isSearching)
    }

    @Test func losingProDropsOnlyTheProFilters() {
        for period in [Period.thisYear, .allTime] {
            let lapsed = ExpenseQuery.Filter(period: period, categoryID: food, paymentMethodID: card, searchText: "tea").withoutPro
            #expect(lapsed == ExpenseQuery.Filter(period: .thisMonth, searchText: "tea"))
        }
        for period in [Period.today, .thisWeek, .thisMonth] {
            #expect(ExpenseQuery.Filter(period: period, categoryID: food).withoutPro == ExpenseQuery.Filter(period: period))
        }
    }

    @Test func menusListLabelsAlphabetically() {
        let names = ExpenseQuery.alphabetical(ExpenseCategory.defaults()).map(\.name)
        #expect(names == ["Entertainment", "Food & Drinks", "Health", "Services", "Shopping", "Transportation", "Travel"])
        let methods = ExpenseQuery.alphabetical(PaymentMethod.defaults()).map(\.name)
        #expect(methods == ["Bank Transfer", "Cash", "Credit Card", "Debit Card", "E-Wallet"])
    }
}
