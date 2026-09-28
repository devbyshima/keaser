import Foundation
import Testing
@testable import KeaserKit

/// Accounts with the default labels. `history` gives the first one past
/// expenses to learn from.
private func accounts(_ names: [String] = ["Personal"], history: [Expense] = []) -> [Account] {
    names.enumerated().map { index, name in
        var account = Account(name: name)
        if index == 0 { account.expenses = history }
        return account
    }
}

private func category(_ name: String, in account: Account) -> ExpenseCategory {
    account.categories.first { $0.name == name }!
}

private func method(_ name: String, in account: Account) -> PaymentMethod {
    account.paymentMethods.first { $0.name == name }!
}

/// A flow with nothing supplied and suggestions off, so every question
/// that can be asked is.
private func flow(
    _ accounts: [Account],
    title: String? = nil,
    amount: Decimal? = nil,
    accountSupplied: Bool = false,
    category: ShortcutFlow.Label? = nil,
    paymentMethod: ShortcutFlow.Label? = nil,
    goBack: Bool = true,
    suggestions: Bool = false
) -> ShortcutFlow {
    ShortcutFlow(
        accounts: accounts,
        accountID: accounts[0].id,
        accountSupplied: accountSupplied,
        title: title,
        amount: amount,
        category: category,
        paymentMethod: paymentMethod,
        goBackEnabled: goBack,
        suggestionsEnabled: suggestions
    )!
}

struct ShortcutFlowOrderTests {
    @Test func asksEverythingInOrder() {
        let all = accounts(["Personal", "Business"])
        var f = flow(all)
        let business = all[1]
        #expect(f.start() == .title)
        #expect(f.next(after: .title, answer: .title(" Coffee ")) == .amount)
        #expect(f.next(after: .amount, answer: .amount(5)) == .account)
        #expect(f.next(after: .account, answer: .account(business.id)) == .category)
        #expect(f.next(after: .category, answer: .category(category("Shopping", in: business).id)) == .paymentMethod)
        #expect(f.next(after: .paymentMethod, answer: .paymentMethod(method("Cash", in: business).id)) == nil)

        let expense = f.expense!
        #expect(f.account.id == business.id)
        #expect(expense.title == "Coffee")
        #expect(expense.amount == 5)
        #expect(expense.categoryID == category("Shopping", in: business).id)
        #expect(expense.paymentMethodID == method("Cash", in: business).id)
    }

    @Test func titleComesBeforeAmount() {
        var f = flow(accounts())
        #expect(f.start() == .title)
        #expect(f.next(after: .title, answer: .title("Lunch")) == .amount)
    }

    @Test func anEmptyTitleBecomesTheDefault() {
        var f = flow(accounts())
        _ = f.start()
        _ = f.next(after: .title, answer: .title("   "))
        _ = f.next(after: .amount, answer: .amount(3))
        #expect(f.displayTitle == QuickLog.defaultTitle)
        #expect(f.expense?.title == QuickLog.defaultTitle)
    }

    @Test func aSingleAccountIsNotAsked() {
        var f = flow(accounts())
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == .category)
    }

    @Test func suppliedValuesAreNeverAsked() {
        let all = accounts(["Personal", "Business"])
        let personal = all[0]
        var f = flow(
            all,
            title: "Coffee",
            amount: 4,
            accountSupplied: true,
            category: .init(id: category("Food & Drinks", in: personal).id, name: "Food & Drinks"),
            paymentMethod: .init(id: method("Cash", in: personal).id, name: "Cash")
        )
        #expect(f.start() == nil)
        #expect(f.expense?.categoryID == category("Food & Drinks", in: personal).id)
        #expect(f.expense?.paymentMethodID == method("Cash", in: personal).id)
    }

    @Test func onlyTheMissingValuesAreAsked() {
        var f = flow(accounts(["Personal", "Business"]), amount: 9, accountSupplied: true)
        #expect(f.start() == .title)
        #expect(f.next(after: .title, answer: .title("Taxi")) == .category)
    }

    @Test func aSuppliedEmptyTitleIsNotAsked() {
        var f = flow(accounts(), title: "", amount: 2)
        #expect(f.start() == .category)
        #expect(f.displayTitle == QuickLog.defaultTitle)
    }

    @Test func anAccountWithoutLabelsSkipsThoseQuestions() {
        let bare = Account(name: "Bare", categories: [], paymentMethods: [])
        var f = flow([bare], title: "Coffee", amount: 3)
        #expect(f.start() == nil)
        #expect(f.expense?.categoryID == nil)
        #expect(f.expense?.paymentMethodID == nil)
    }

    @Test func aSuppliedLabelFromAnotherAccountIsFiledByName() {
        let all = accounts(["Personal", "Business"])
        let personal = all[0], business = all[1]
        var f = flow(
            all,
            title: "Taxi",
            amount: 20,
            category: .init(id: category("Transportation", in: personal).id, name: "Transportation")
        )
        #expect(f.start() == .account)
        #expect(f.next(after: .account, answer: .account(business.id)) == .paymentMethod)
        #expect(f.expense?.categoryID == category("Transportation", in: business).id)
    }

    @Test func aSuppliedLabelMissingFromTheAccountStaysEmpty() {
        var f = flow(accounts(), title: "Gift", amount: 20, category: .init(id: UUID(), name: "Presents"))
        #expect(f.start() == .paymentMethod)
        #expect(f.expense?.categoryID == nil)
    }

    @Test func unknownAnswersAskAgain() {
        var f = flow(accounts())
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        _ = f.next(after: .amount, answer: .amount(12))
        #expect(f.next(after: .category, answer: .category(UUID())) == .category)
        #expect(f.expense?.categoryID == nil)
    }
}

struct ShortcutFlowSuggestionTests {
    @Test func guessedLabelsAreFilledInWithoutAsking() {
        // "Lunch" names Food & Drinks, and a recognised title is paid in Cash.
        var f = flow(accounts(), suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == nil)
        let personal = f.account
        #expect(f.expense?.categoryID == category("Food & Drinks", in: personal).id)
        #expect(f.expense?.paymentMethodID == method("Cash", in: personal).id)
    }

    @Test func withSuggestionsOffTheyAreAsked() {
        var f = flow(accounts(), suggestions: false)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == .category)
    }

    @Test func onlyTheUnguessedLabelIsAsked() {
        // Past expenses teach the payment method, while an unknown title
        // gives no category.
        var personal = Account(name: "Personal")
        let card = method("Credit Card", in: personal)
        personal.expenses = [Expense(title: "Rent", amount: 900, paymentMethodID: card.id)]
        var f = flow([personal], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Zorbex"))
        #expect(f.next(after: .amount, answer: .amount(12)) == .category)
        #expect(f.next(after: .category, answer: .category(category("Shopping", in: personal).id)) == nil)
        #expect(f.expense?.paymentMethodID == card.id)
    }

    @Test func goingBackShowsAGuessedQuestion() {
        // "Lunch" guesses Food & Drinks. Without history or a Cash method
        // there is no payment guess, so that is asked.
        let account = Account(name: "Personal", paymentMethods: [
            PaymentMethod(name: "Credit Card", symbol: "creditcard.fill"),
            PaymentMethod(name: "Voucher", symbol: "ticket"),
        ])
        var f = flow([account], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == .paymentMethod)
        #expect(f.expense?.categoryID == category("Food & Drinks", in: account).id)
        #expect(f.next(after: .paymentMethod, answer: .goBack) == .category)
        let shopping = category("Shopping", in: account)
        #expect(f.next(after: .category, answer: .category(shopping.id)) == .paymentMethod)
        #expect(f.expense?.categoryID == shopping.id)
    }

    /// No Cash method, so the payment question is asked and Go Back leads
    /// from it to the guessed category.
    private func cardsOnly() -> Account {
        Account(name: "Personal", paymentMethods: [
            PaymentMethod(name: "Credit Card", symbol: "creditcard.fill"),
            PaymentMethod(name: "Voucher", symbol: "ticket"),
        ])
    }

    @Test func aPickedCategoryIsNotGuessedOverWhenMovingForwardAgain() {
        let account = cardsOnly()
        let shopping = category("Shopping", in: account).id
        var f = flow([account], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == .paymentMethod)
        #expect(f.next(after: .paymentMethod, answer: .goBack) == .category)
        #expect(f.next(after: .category, answer: .category(shopping)) == .paymentMethod)
        // Back past the category to the amount, then forward again: the
        // category question is skipped as before, keeping Shopping rather
        // than the guess (Food & Drinks).
        #expect(f.next(after: .paymentMethod, answer: .goBack) == .category)
        #expect(f.next(after: .category, answer: .goBack) == .amount)
        #expect(f.next(after: .amount, answer: .amount(13)) == .paymentMethod)
        #expect(f.expense?.categoryID == shopping)
        #expect(f.expense?.amount == 13)
    }

    @Test func aPickedPaymentMethodIsNotGuessedOverEither() {
        // "Lunch" guesses Cash; the person picks Credit Card instead.
        let account = Account(name: "Personal")
        let card = method("Credit Card", in: account).id
        var f = flow([account], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        #expect(f.next(after: .amount, answer: .amount(12)) == nil)
        #expect(f.expense?.paymentMethodID == method("Cash", in: account).id)
        // Put right from the question Go Back leads to.
        var fixed = flow([account], title: "Lunch", amount: 12, suggestions: true)
        #expect(fixed.start() == nil)
        _ = fixed.next(after: .category, answer: .category(category("Food & Drinks", in: account).id))
        _ = fixed.next(after: .paymentMethod, answer: .paymentMethod(card))
        #expect(fixed.next(after: .category, answer: .category(category("Shopping", in: account).id)) == nil)
        #expect(fixed.expense?.paymentMethodID == card)
    }

    @Test func aNewTitleIsGuessedAfresh() {
        let account = cardsOnly()
        var f = flow([account], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        _ = f.next(after: .amount, answer: .amount(12))
        _ = f.next(after: .paymentMethod, answer: .goBack)
        _ = f.next(after: .category, answer: .category(category("Shopping", in: account).id))
        // Back to the title: a picked category belonged to the old one.
        #expect(f.next(after: .paymentMethod, answer: .goBack) == .category)
        #expect(f.next(after: .category, answer: .goBack) == .amount)
        #expect(f.next(after: .amount, answer: .goBack) == .title)
        #expect(f.next(after: .title, answer: .title("Taxi")) == .amount)
        #expect(f.next(after: .amount, answer: .amount(20)) == .paymentMethod)
        #expect(f.expense?.categoryID == category("Transportation", in: account).id)
    }

    @Test func theSameTitleAgainKeepsThePick() {
        let account = cardsOnly()
        let shopping = category("Shopping", in: account).id
        var f = flow([account], suggestions: true)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Lunch"))
        _ = f.next(after: .amount, answer: .amount(12))
        _ = f.next(after: .paymentMethod, answer: .goBack)
        _ = f.next(after: .category, answer: .category(shopping))
        _ = f.next(after: .paymentMethod, answer: .goBack)
        _ = f.next(after: .category, answer: .goBack)
        _ = f.next(after: .amount, answer: .goBack)
        _ = f.next(after: .title, answer: .title(" Lunch "))
        #expect(f.next(after: .amount, answer: .amount(12)) == .paymentMethod)
        #expect(f.expense?.categoryID == shopping)
    }
}

struct ShortcutFlowGoBackTests {
    @Test func eachListGoesBackToTheQuestionBefore() {
        let two = flow(accounts(["Personal", "Business"]))
        #expect(two.previous(before: .paymentMethod) == .category)
        #expect(two.previous(before: .category) == .account)
        #expect(two.previous(before: .account) == .amount)
        #expect(two.previous(before: .amount) == .title)
        #expect(two.previous(before: .title) == nil)
    }

    @Test func withOneAccountCategoryGoesBackToAmount() {
        #expect(flow(accounts()).previous(before: .category) == .amount)
    }

    @Test func suppliedQuestionsAreSteppedOver() {
        let all = accounts(["Personal", "Business"])
        #expect(flow(all, amount: 5).previous(before: .account) == .title)
        #expect(flow(all, amount: 5, accountSupplied: true).previous(before: .category) == .title)
        let personal = all[0]
        let food = ShortcutFlow.Label(id: category("Food & Drinks", in: personal).id, name: "Food & Drinks")
        #expect(flow(all, category: food).previous(before: .paymentMethod) == .account)
    }

    @Test func aCategoryLessAccountIsSteppedOver() {
        let bare = Account(name: "Bare", categories: [])
        #expect(flow([bare]).previous(before: .paymentMethod) == .amount)
    }

    @Test func goBackIsOfferedOnlyOnListsWithSomewhereToGo() {
        let all = accounts(["Personal", "Business"])
        let open = flow(all)
        #expect(open.offersGoBack(at: .account))
        #expect(open.offersGoBack(at: .category))
        #expect(open.offersGoBack(at: .paymentMethod))
        #expect(!open.offersGoBack(at: .title))
        #expect(!open.offersGoBack(at: .amount))

        let off = flow(all, goBack: false)
        #expect(!off.offersGoBack(at: .category))

        // Title and amount supplied, one account: the category list is
        // the first question.
        let first = flow(accounts(), title: "Coffee", amount: 3)
        #expect(!first.offersGoBack(at: .category))
        #expect(first.offersGoBack(at: .paymentMethod))
    }

    @Test func goingBackAsksTheEarlierQuestionAgain() {
        let all = accounts(["Personal", "Business"])
        var f = flow(all)
        _ = f.start()
        _ = f.next(after: .title, answer: .title("Coffee"))
        _ = f.next(after: .amount, answer: .amount(4))
        #expect(f.next(after: .account, answer: .goBack) == .amount)
        #expect(f.next(after: .amount, answer: .amount(6)) == .account)
        #expect(f.next(after: .account, answer: .account(all[0].id)) == .category)
        #expect(f.next(after: .category, answer: .goBack) == .account)
        #expect(f.expense?.amount == 6)
    }

    @Test func goBackWithNowhereToGoStays() {
        var f = flow(accounts(), title: "Coffee", amount: 3)
        #expect(f.start() == .category)
        #expect(f.next(after: .category, answer: .goBack) == .category)
    }

    @Test func pickingAnotherAccountAsksItsLabels() {
        let all = accounts(["Personal", "Business"])
        var f = flow(all, title: "Lunch", amount: 12)
        #expect(f.start() == .account)
        _ = f.next(after: .account, answer: .account(all[0].id))
        _ = f.next(after: .category, answer: .category(category("Shopping", in: all[0]).id))
        #expect(f.next(after: .paymentMethod, answer: .goBack) == .category)
        #expect(f.next(after: .category, answer: .goBack) == .account)
        #expect(f.next(after: .account, answer: .account(all[1].id)) == .category)
        #expect(f.expense?.categoryID == nil)
    }
}

struct ShortcutCardEditTests {
    private func finished(_ all: [Account]) -> ShortcutFlow {
        var f = flow(all, title: "Coffee", amount: 4, category: nil)
        _ = f.start()
        if all.count > 1 { _ = f.next(after: .account, answer: .account(all[0].id)) }
        _ = f.next(after: .category, answer: .category(category("Food & Drinks", in: all[0]).id))
        _ = f.next(after: .paymentMethod, answer: .paymentMethod(method("Cash", in: all[0]).id))
        return f
    }

    @Test func pickingAnOptionSetsIt() {
        var f = finished(accounts())
        let personal = f.account
        f.change(.category, to: category("Shopping", in: personal).id)
        #expect(f.categoryID == category("Shopping", in: personal).id)
        f.change(.paymentMethod, to: method("Bank Transfer", in: personal).id)
        #expect(f.paymentMethodID == method("Bank Transfer", in: personal).id)
        // An option of another account changes nothing.
        f.change(.category, to: UUID())
        #expect(f.categoryID == category("Shopping", in: personal).id)
    }

    @Test func eachDetailOffersItsAccountsOptions() {
        let all = accounts(["Personal", "Business"])
        let f = finished(all)
        let accountChoice = f.options(for: .account)
        #expect(accountChoice.options.map(\.name) == ["Personal", "Business"])
        #expect(accountChoice.current == all[0].id)
        let categoryChoice = f.options(for: .category)
        #expect(categoryChoice.options.map(\.id) == all[0].categories.map(\.id))
        #expect(categoryChoice.current == category("Food & Drinks", in: all[0]).id)
        let empty = flow(accounts(), title: "Coffee", amount: 4, category: .init(id: UUID(), name: "Nothing"))
        #expect(empty.options(for: .category).current == nil)
    }

    @Test func anotherAccountKeepsTheLabelsByName() {
        let all = accounts(["Personal", "Business"])
        var f = finished(all)
        f.change(.account, to: all[1].id)
        #expect(f.account.id == all[1].id)
        #expect(f.categoryID == category("Food & Drinks", in: all[1]).id)
        #expect(f.paymentMethodID == method("Cash", in: all[1]).id)
        #expect(f.options(for: .category).options.map(\.id) == all[1].categories.map(\.id))
        f.change(.account, to: all[0].id)
        #expect(f.account.id == all[0].id)
    }

    @Test func labelsMissingFromTheNewAccountAreGuessedOrEmpty() {
        let personal = Account(name: "Personal")
        let travel = Account(name: "Travel", categories: [ExpenseCategory(name: "Flights", symbol: "airplane")], paymentMethods: [])
        var f = flow([personal, travel], title: "Coffee", amount: 4, suggestions: true)
        _ = f.start()
        _ = f.next(after: .account, answer: .account(personal.id))
        f.change(.account, to: travel.id)
        #expect(f.categoryID == nil)
        #expect(f.paymentMethodID == nil)
        f.change(.account, to: personal.id)
        // "Coffee" names Food & Drinks, paid in Cash.
        #expect(f.categoryID == category("Food & Drinks", in: personal).id)
        #expect(f.paymentMethodID == method("Cash", in: personal).id)
    }
}

struct ShortcutCardTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func formatsTheAmountAndTheDetails() {
        let account = Account(name: "Personal")
        let expense = Expense(
            title: "Uniqlo",
            amount: Decimal(string: "19.9")!,
            categoryID: category("Shopping", in: account).id,
            paymentMethodID: method("Credit Card", in: account).id,
            date: date(2026, 4, 8)
        )
        let card = ShortcutCard(expense: expense, in: account, currencyCode: "USD", locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(card.amount == "$19.90")
        #expect(card.title == "Uniqlo")
        #expect(card.account == "Personal")
        #expect(card.category == "Shopping")
        #expect(card.paymentMethod == "Credit Card")
        #expect(card.date == "04/08/2026")
    }

    @Test func missingLabelsReadNone() {
        let account = Account(name: "Personal")
        let card = ShortcutCard(expense: Expense(title: "Expense", amount: 3), in: account, currencyCode: "USD")
        #expect(card.category == ShortcutCard.noLabel)
        #expect(card.paymentMethod == ShortcutCard.noLabel)
    }

    @Test(arguments: [
        ("en_US", "04/08/2026"),
        ("en_GB", "08/04/2026"),
        ("de_DE", "08.04.2026"),
    ])
    func datesHaveTwoDigitMonthAndDayInLocaleOrder(locale: String, expected: String) {
        #expect(ShortcutCard.dateText(date(2026, 4, 8), locale: Locale(identifier: locale), timeZone: utc) == expected)
    }

    @Test func amountsFollowTheCurrency() {
        let account = Account(name: "Personal")
        let us = Locale(identifier: "en_US")
        #expect(ShortcutCard(expense: Expense(title: "A", amount: 1500), in: account, currencyCode: "JPY", locale: us).amount == "¥1,500")
        #expect(ShortcutCard(expense: Expense(title: "A", amount: 5), in: account, currencyCode: "USD", locale: us).amount == "$5.00")
    }

    @Test func theExpenseIsDatedWhenTheShortcutStarted() {
        let started = date(2026, 3, 24)
        let all = accounts()
        let f = ShortcutFlow(accounts: all, accountID: all[0].id, title: "Watsons", amount: 2, date: started)
        #expect(f?.expense?.date == started)
        #expect(f?.expense?.createdAt == started)
    }

    @Test func aSuppliedDateDatesTheExpenseButNotItsCreation() {
        let paid = date(2026, 3, 20)
        let started = date(2026, 3, 24)
        let all = accounts()
        let f = ShortcutFlow(accounts: all, accountID: all[0].id, title: "Watsons", amount: 2, date: paid, createdAt: started)!
        #expect(f.expense?.date == paid)
        #expect(f.expense?.createdAt == started)
        #expect(f.expense?.updatedAt == started)
        let card = ShortcutCard(expense: f.expense!, in: all[0], currencyCode: "USD", locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(card.date == "03/20/2026")
    }

    @Test func anUnknownAccountMakesNoFlow() {
        #expect(ShortcutFlow(accounts: accounts(), accountID: UUID()) == nil)
        #expect(ShortcutFlow(accounts: [], accountID: UUID()) == nil)
    }
}

struct ShortcutCurrencyNoteTests {
    private let us = Locale(identifier: "en_US")

    @Test func anAmountInAnotherCurrencySaysWhatWillBeAdded() {
        let note = ShortcutCard.otherCurrencyNote(amount: 1500, currencyCode: "JPY", recordedAs: 1500, appCurrencyCode: "USD", locale: us)
        #expect(note == "The shortcut passed ¥1,500, but Keaser records amounts in USD, so it will be added as $1,500.00.")
        let dollars = ShortcutCard.otherCurrencyNote(amount: Decimal(string: "4.99")!, currencyCode: "usd", recordedAs: 5, appCurrencyCode: "JPY", locale: us)
        #expect(dollars == "The shortcut passed $4.99, but Keaser records amounts in JPY, so it will be added as ¥5.")
    }

    @Test func keasersOwnCurrencyOrNoneSaysNothing() {
        #expect(ShortcutCard.otherCurrencyNote(amount: 5, currencyCode: "USD", recordedAs: 5, appCurrencyCode: "USD") == nil)
        #expect(ShortcutCard.otherCurrencyNote(amount: 5, currencyCode: "usd", recordedAs: 5, appCurrencyCode: "USD") == nil)
        #expect(ShortcutCard.otherCurrencyNote(amount: 5, currencyCode: "", recordedAs: 5, appCurrencyCode: "USD") == nil)
        #expect(ShortcutCard.otherCurrencyNote(amount: 5, currencyCode: " ", recordedAs: 5, appCurrencyCode: "USD") == nil)
    }
}

struct ShortcutAmountTests {
    @Test func currencyAmountsAreRoundedToTheCurrency() {
        #expect(QuickLog.amount(fromDecimal: Decimal(string: "19.899")!, currencyCode: "USD") == Decimal(string: "19.9"))
        #expect(QuickLog.amount(fromDecimal: Decimal(string: "1500.4")!, currencyCode: "JPY") == 1500)
        #expect(QuickLog.amount(fromDecimal: Decimal(0), currencyCode: "USD") == nil)
        #expect(QuickLog.amount(fromDecimal: Decimal(string: "0.004")!, currencyCode: "USD") == nil)
        #expect(QuickLog.amount(fromDecimal: Decimal(-5), currencyCode: "USD") == nil)
    }
}

struct ShortcutPreferencesTests {
    @Test func defaultsAreOn() {
        let prefs = Preferences()
        #expect(prefs.shortcutConfirmsDetails)
        #expect(prefs.shortcutGoBackEnabled)
        #expect(prefs.shortcutSmartSuggestionsEnabled)
    }

    @Test func olderFilesDecodeToTheDefaults() throws {
        let json = #"{"currencyCode":"EUR","firstWeekday":2,"smartSuggestionsEnabled":false}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(prefs.currencyCode == "EUR")
        #expect(!prefs.smartSuggestionsEnabled)
        #expect(prefs.shortcutConfirmsDetails)
        #expect(prefs.shortcutGoBackEnabled)
        // Its own switch: New Expense's being off does not turn it off.
        #expect(prefs.shortcutSmartSuggestionsEnabled)
    }

    @Test func choicesSurviveARoundTrip() throws {
        var prefs = Preferences()
        prefs.shortcutConfirmsDetails = false
        prefs.shortcutGoBackEnabled = false
        prefs.shortcutSmartSuggestionsEnabled = false
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded == prefs)
        #expect(!decoded.shortcutConfirmsDetails)
        #expect(!decoded.shortcutGoBackEnabled)
        #expect(!decoded.shortcutSmartSuggestionsEnabled)
    }

    @Test func aWholeOlderDatabaseStillOpens() throws {
        let json = #"{"version":1,"accounts":[],"preferences":{"currencyCode":"USD"}}"#
        let database = try JSONDecoder().decode(Database.self, from: Data(json.utf8))
        #expect(database.preferences.shortcutConfirmsDetails)
        #expect(database.preferences.shortcutGoBackEnabled)
        #expect(database.preferences.shortcutSmartSuggestionsEnabled)
    }
}
