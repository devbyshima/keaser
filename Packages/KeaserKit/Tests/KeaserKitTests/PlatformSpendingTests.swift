import Foundation
import Testing
@testable import KeaserKit

private let us = Locale(identifier: "en_US")

private func calendar(firstWeekday: Int = 1) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    c.locale = us
    c.firstWeekday = firstWeekday
    return c
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, in calendar: Calendar = calendar()) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// Saturday 26 Sep 2026, noon in New York.
private let now = date(2026, 9, 26)

/// Personal (selected) and Business, in USD.
private func sampleDatabase() -> Database {
    var personal = Account(name: "Personal")
    let food = personal.categories.first { $0.name == "Food & Drinks" }!
    let cash = personal.paymentMethods.first { $0.name == "Cash" }!
    let card = personal.paymentMethods.first { $0.name == "Credit Card" }!
    personal.expenses = [
        Expense(title: "Coffee", amount: Decimal(string: "4.50")!, categoryID: food.id, paymentMethodID: cash.id, date: date(2026, 9, 26)),
        Expense(title: "Dinner", amount: 45, categoryID: food.id, paymentMethodID: card.id, date: date(2026, 9, 25)),
        Expense(title: "Lunch", amount: 45, categoryID: food.id, paymentMethodID: cash.id, date: date(2026, 9, 24)),
        // Sunday: in a Sunday week, not in a Monday one.
        Expense(title: "Brunch", amount: Decimal(string: "53.63")!, paymentMethodID: card.id, date: date(2026, 9, 20)),
        Expense(title: "Rent", amount: 900, date: date(2026, 9, 1)),
        Expense(title: "Flight", amount: 300, date: date(2026, 3, 14)),
        Expense(title: "Old", amount: 20, date: date(2025, 12, 31)),
    ]
    var business = Account(name: "Business")
    business.expenses = [Expense(title: "Client lunch", amount: 80, date: date(2026, 9, 25))]
    return Database(accounts: [personal, business], preferences: Preferences(currencyCode: "USD", selectedAccountID: personal.id))
}

private func answer(_ question: SpendingQuestion, in database: Database = sampleDatabase(), isPro: Bool = true, firstWeekday: Int = 1) -> SpendingOutcome {
    question.answer(in: database, isPro: isPro, now: now, calendar: calendar(firstWeekday: firstWeekday))
}

private func total(_ outcome: SpendingOutcome) -> Decimal? {
    if case .answer(let answer) = outcome { return answer.total }
    return nil
}

struct SpendingQuestionTests {
    @Test func totalsEachPeriodOfTheSelectedAccount() {
        #expect(total(answer(SpendingQuestion(period: .today))) == Decimal(string: "4.50"))
        #expect(total(answer(SpendingQuestion(period: .thisWeek))) == Decimal(string: "148.13"))
        #expect(total(answer(SpendingQuestion(period: .thisMonth))) == Decimal(string: "1048.13"))
        #expect(total(answer(SpendingQuestion(period: .thisYear))) == Decimal(string: "1348.13"))
        #expect(total(answer(SpendingQuestion(period: .allTime))) == Decimal(string: "1368.13"))
    }

    @Test func weeksFollowTheChosenFirstWeekday() {
        // Monday weeks start on the 21st, so Sunday's brunch drops out.
        #expect(total(answer(SpendingQuestion(period: .thisWeek), firstWeekday: 2)) == Decimal(string: "94.50"))
    }

    @Test func anotherAccountCanBeAskedAbout() {
        let db = sampleDatabase()
        guard case .answer(let business) = answer(SpendingQuestion(period: .thisWeek, accountID: db.accounts[1].id), in: db) else {
            Issue.record("expected an answer")
            return
        }
        #expect(business.accountName == "Business")
        #expect(business.total == 80)
        #expect(business.count == 1)
    }

    @Test func labelsNarrowTheTotalAndAreMatchedByName() {
        let db = sampleDatabase()
        let personal = db.accounts[0]
        let business = db.accounts[1]
        // Picked from Business's own list: matched to Personal's by name.
        let food = business.categories.first { $0.name == "Food & Drinks" }!
        let cash = personal.paymentMethods.first { $0.name == "Cash" }!
        let question = SpendingQuestion(
            period: .thisWeek,
            category: .init(id: food.id, name: food.name),
            paymentMethod: .init(id: cash.id, name: cash.name)
        )
        guard case .answer(let answer) = answer(question, in: db) else {
            Issue.record("expected an answer")
            return
        }
        #expect(answer.total == Decimal(string: "49.50"))
        #expect(answer.categoryName == "Food & Drinks")
        #expect(answer.paymentMethodName == "Cash")
        #expect(answer.count == 2)
    }

    @Test func proFeaturesAreRefusedWithoutPro() {
        let db = sampleDatabase()
        let food = db.accounts[0].categories[0]
        #expect(answer(SpendingQuestion(period: .thisYear), isPro: false) == .needsPro(.longTermInsights))
        #expect(answer(SpendingQuestion(period: .allTime), isPro: false) == .needsPro(.longTermInsights))
        #expect(answer(SpendingQuestion(period: .today, category: .init(id: food.id, name: food.name)), in: db, isPro: false) == .needsPro(.moreFilters))
        // What Home shows without Pro is answered.
        #expect(total(answer(SpendingQuestion(period: .thisMonth), isPro: false)) == Decimal(string: "1048.13"))
        #expect(total(answer(SpendingQuestion(period: .thisWeek, accountID: db.accounts[1].id), in: db, isPro: false)) == 80)
    }

    @Test func refusesWhatCannotBeAnswered() {
        #expect(answer(SpendingQuestion(period: .today), in: Database()) == .noAccount)
        #expect(answer(SpendingQuestion(period: .today, accountID: UUID())) == .accountGone)
        let travel = SpendingQuestion(period: .today, category: .init(id: UUID(), name: "Travel Insurance"))
        #expect(answer(travel) == .missingCategory(name: "Travel Insurance", account: "Personal"))
        let crypto = SpendingQuestion(period: .today, paymentMethod: .init(id: UUID(), name: "Crypto"))
        #expect(answer(crypto) == .missingPaymentMethod(name: "Crypto", account: "Personal"))
    }

    @Test func everyRefusalSaysSomething() {
        let refusals: [SpendingOutcome] = [
            .noAccount, .accountGone, .missingCategory(name: "Pets", account: "Personal"),
            .missingPaymentMethod(name: "Cash", account: "Business"),
            .needsPro(.longTermInsights), .needsPro(.moreFilters), .needsPro(.widgets),
        ]
        for outcome in refusals {
            #expect(outcome.refusal?.isEmpty == false)
        }
        #expect(SpendingOutcome.needsPro(.longTermInsights).refusal?.contains("Keaser Pro") == true)
        #expect(SpendingOutcome.missingCategory(name: "Pets", account: "Personal").refusal == "Personal has no category named Pets.")
        #expect(SpendingOutcome.answer(SpendingAnswer(period: .today, accountName: "Personal", total: 0, currencyCode: "USD", count: 0)).refusal == nil)
    }
}

struct SpendingAnswerPhrasingTests {
    private func week(total: String, count: Int, category: String? = nil, payment: String? = nil, period: Period = .thisWeek) -> SpendingAnswer {
        SpendingAnswer(
            period: period,
            accountName: "Personal",
            categoryName: category,
            paymentMethodName: payment,
            total: Decimal(string: total)!,
            currencyCode: "USD",
            count: count,
            largest: .init(title: "Dinner", amount: 45)
        )
    }

    @Test func saysTheTotalThePeriodAndTheAccount() {
        #expect(week(total: "148.13", count: 4).sentence(locale: us) == "You spent $148.13 this week in Personal.")
        #expect(week(total: "4.50", count: 1, period: .today).sentence(locale: us) == "You spent $4.50 today in Personal.")
        #expect(week(total: "1048.13", count: 5, period: .thisMonth).sentence(locale: us) == "You spent $1,048.13 this month in Personal.")
        #expect(week(total: "1348.13", count: 6, period: .thisYear).sentence(locale: us) == "You spent $1,348.13 this year in Personal.")
        #expect(week(total: "1368.13", count: 7, period: .allTime).sentence(locale: us) == "You've spent $1,368.13 in Personal altogether.")
    }

    @Test func namesTheFilters() {
        #expect(week(total: "49.50", count: 2, category: "Food & Drinks", payment: "Cash").sentence(locale: us)
            == "You spent $49.50 on Food & Drinks with Cash this week in Personal.")
        #expect(week(total: "49.50", count: 2, payment: "Cash").sentence(locale: us)
            == "You spent $49.50 with Cash this week in Personal.")
    }

    @Test func nothingSpentIsSaidPlainly() {
        #expect(week(total: "0", count: 0).sentence(locale: us) == "You haven't spent anything this week in Personal.")
        #expect(week(total: "0", count: 0, category: "Travel").sentence(locale: us) == "You haven't spent anything on Travel this week in Personal.")
        #expect(week(total: "0", count: 0, period: .allTime).sentence(locale: us) == "You haven't spent anything in Personal yet.")
    }

    @Test func theSpokenAnswerStandsOnItsOwn() {
        #expect(week(total: "148.13", count: 4).spokenSentence(locale: us)
            == "You spent $148.13 this week in Personal. That's 4 expenses. The largest was $45.00 for Dinner.")
        #expect(week(total: "4.50", count: 1, period: .today).spokenSentence(locale: us)
            == "You spent $4.50 today in Personal. That's 1 expense.")
        #expect(week(total: "0", count: 0).spokenSentence(locale: us) == "You haven't spent anything this week in Personal.")
    }

    @Test func theSnapshotIsTheMediumWidgets() {
        let snapshot = week(total: "148.13", count: 4).snapshot
        #expect(snapshot.state == .ready)
        #expect(snapshot.spentCaption == "Spent This Week")
        #expect(snapshot.total == Decimal(string: "148.13"))
        #expect(snapshot.currencyCode == "USD")
    }

    @Test func theLargestIsTheNewestOfEqualAmounts() {
        guard case .answer(let answer) = answer(SpendingQuestion(period: .thisWeek)) else {
            Issue.record("expected an answer")
            return
        }
        // Brunch is larger; Dinner and Lunch tie below it.
        #expect(answer.largest?.title == "Brunch")
        guard case .answer(let food) = SpendingQuestion(period: .thisWeek).answer(
            in: {
                var db = sampleDatabase()
                db.accounts[0].expenses.removeAll { $0.title == "Brunch" }
                return db
            }(),
            isPro: true, now: now, calendar: calendar()
        ) else {
            Issue.record("expected an answer")
            return
        }
        #expect(food.largest?.title == "Dinner")
    }
}
