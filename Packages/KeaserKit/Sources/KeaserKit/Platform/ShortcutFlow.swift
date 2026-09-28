import Foundation

/// The "Add Expense" shortcut's guided flow, as pure logic: which question
/// comes next, which ones are skipped, where Go Back leads, and the expense
/// it adds up to. The intent only asks the questions.
///
/// Questions come in a fixed order: title, amount, account, category,
/// payment method. One is never asked when the shortcut supplied its value up
/// front, nor when there is nothing to choose between (a single account, an
/// account without categories). With suggestions on, a category or payment
/// method guessed from the title is filled in without asking; Go Back still
/// shows that question, so a wrong guess can be put right, and a guess never
/// replaces what the person picked there, however often they go back and
/// forward again (until the title or account changes).
public struct ShortcutFlow: Hashable, Sendable {
    public enum Step: Int, CaseIterable, Comparable, Sendable {
        case title, amount, account, category, paymentMethod

        /// Account, category and payment method are picked from a list;
        /// only lists offer Go Back.
        public var isList: Bool { self >= .account }

        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Answer: Hashable, Sendable {
        case title(String)
        case amount(Decimal)
        case account(UUID)
        case category(UUID)
        case paymentMethod(UUID)
        /// The Go Back row at the end of a list.
        case goBack
    }

    /// The details on the confirmation card that open a list of options.
    public enum Field: String, CaseIterable, Sendable {
        case account, category, paymentMethod
    }

    /// A category or payment method chosen in a saved shortcut. It may
    /// belong to another account (the one selected when the shortcut was
    /// made), so it is matched by name in the account the expense goes to,
    /// like `QuickLog.category(id:name:in:)`.
    public struct Label: Hashable, Sendable {
        public var id: UUID
        public var name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Identifies the Go Back row the lists end with.
    public static let goBackID = UUID(uuidString: "6F8B7ED5-56D4-452D-A67C-2B48FD623764")!

    public let accounts: [Account]
    public let goBackEnabled: Bool
    public let suggestionsEnabled: Bool
    /// The expense's date: the one the shortcut supplied, otherwise when
    /// it started.
    public let date: Date
    /// When the shortcut started, which is when the expense was made even
    /// when it is dated another day.
    public let createdAt: Date

    /// As typed; empty means `QuickLog.defaultTitle`.
    public private(set) var title: String
    public private(set) var amount: Decimal?
    public private(set) var accountID: UUID
    public private(set) var categoryID: UUID?
    public private(set) var paymentMethodID: UUID?

    private let expenseID = UUID()
    /// The on-device model's category for a title, once it was asked (see
    /// `start(model:budget:)`).
    var modelAnswer: ModelAnswer?
    private let supplied: Set<Step>
    /// The category and payment method questions the person answered
    /// themselves: moving forward again keeps those answers rather than
    /// guessing over them. Cleared when the title or account changes, since
    /// guesses depend on both.
    private var picked: Set<Step> = []
    private let suppliedCategory: Label?
    private let suppliedPaymentMethod: Label?

    /// Nil when `accountID` is not one of `accounts`. Every value passed
    /// here was supplied by the shortcut and is never asked for; a nil one
    /// is. `accountID` is the account the expense goes to unless someone
    /// picks another, and counts as supplied only with `accountSupplied`.
    /// `date` is never asked for; `createdAt` defaults to `date`.
    public init?(
        accounts: [Account],
        accountID: UUID,
        accountSupplied: Bool = false,
        title: String? = nil,
        amount: Decimal? = nil,
        category: Label? = nil,
        paymentMethod: Label? = nil,
        goBackEnabled: Bool = true,
        suggestionsEnabled: Bool = true,
        date: Date = .now,
        createdAt: Date? = nil
    ) {
        guard accounts.contains(where: { $0.id == accountID }) else { return nil }
        self.accounts = accounts
        self.accountID = accountID
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.amount = amount
        self.suppliedCategory = category
        self.suppliedPaymentMethod = paymentMethod
        self.goBackEnabled = goBackEnabled
        self.suggestionsEnabled = suggestionsEnabled
        self.date = date
        self.createdAt = createdAt ?? date
        var supplied = Set<Step>()
        if title != nil { supplied.insert(.title) }
        if amount != nil { supplied.insert(.amount) }
        if accountSupplied { supplied.insert(.account) }
        if category != nil { supplied.insert(.category) }
        if paymentMethod != nil { supplied.insert(.paymentMethod) }
        self.supplied = supplied
    }

    // MARK: Steps

    /// The first question, filling in whatever is skipped before it. Nil
    /// when there is nothing to ask.
    public mutating func start() -> Step? {
        advance(after: nil)
    }

    /// Records the answer to `step` and returns the next question, or nil
    /// once the expense is complete. Go Back returns the question before.
    public mutating func next(after step: Step, answer: Answer) -> Step? {
        switch answer {
        case .goBack:
            return previous(before: step) ?? step
        case .title(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != title { picked = [] }
            title = trimmed
        case .amount(let value):
            amount = value
        case .account(let id):
            guard accounts.contains(where: { $0.id == id }) else { return step }
            if id != accountID { picked = [] }
            accountID = id
            // Labels belong to an account; the next questions pick them again.
            categoryID = nil
            paymentMethodID = nil
        case .category(let id):
            guard let category = account.category(id: id) else { return step }
            categoryID = category.id
            picked.insert(.category)
        case .paymentMethod(let id):
            guard let method = account.paymentMethod(id: id) else { return step }
            paymentMethodID = method.id
            picked.insert(.paymentMethod)
        }
        return advance(after: step)
    }

    /// Whether the list for `step` ends with Go Back: only when it is on
    /// and there is an earlier question to go back to.
    public func offersGoBack(at step: Step) -> Bool {
        goBackEnabled && step.isList && previous(before: step) != nil
    }

    /// The question Go Back leads to from `step`: the closest earlier one
    /// that can be asked, whether or not a suggestion answered it.
    public func previous(before step: Step) -> Step? {
        Step.allCases.reversed().first { $0 < step && canAsk($0) }
    }

    private mutating func advance(after step: Step?) -> Step? {
        for candidate in Step.allCases where step.map({ candidate > $0 }) ?? true {
            if asksOnTheWayForward(candidate) { return candidate }
        }
        return nil
    }

    /// Whether `step` can be asked at all: its value was not supplied and
    /// there is something to choose.
    private func canAsk(_ step: Step) -> Bool {
        guard !supplied.contains(step) else { return false }
        switch step {
        case .title, .amount: return true
        case .account: return accounts.count > 1
        case .category: return !account.categories.isEmpty
        case .paymentMethod: return !account.paymentMethods.isEmpty
        }
    }

    /// Whether `step` is asked when moving forward. When it is not, fills in
    /// what it stands for: the supplied label, a guess, or nothing. Where a
    /// guess would skip the question, the person's own earlier answer is
    /// kept instead of the guess.
    private mutating func asksOnTheWayForward(_ step: Step) -> Bool {
        switch step {
        case .title, .amount, .account:
            return canAsk(step)
        case .category:
            if let label = suppliedCategory {
                categoryID = QuickLog.category(id: label.id, name: label.name, in: account)?.id
                return false
            }
            guard canAsk(step) else { categoryID = nil; return false }
            guard let guess = guess().categoryID else { return true }
            if !picked.contains(.category) { categoryID = guess }
            return false
        case .paymentMethod:
            if let label = suppliedPaymentMethod {
                paymentMethodID = QuickLog.paymentMethod(id: label.id, name: label.name, in: account)?.id
                return false
            }
            guard canAsk(step) else { paymentMethodID = nil; return false }
            guard let guess = guess().paymentMethodID else { return true }
            if !picked.contains(.paymentMethod) { paymentMethodID = guess }
            return false
        }
    }

    /// Whether moving forward fills the category in with a guess, when
    /// there is one: suggestions are on, neither the shortcut nor the person
    /// chose the category, and the account has some.
    var guessesCategory: Bool {
        suggestionsEnabled && suppliedCategory == nil && !picked.contains(.category) && canAsk(.category)
    }

    private func guess() -> SmartSuggester.LabelGuess {
        guard suggestionsEnabled else { return SmartSuggester.LabelGuess() }
        return SmartSuggester.guessLabels(
            for: title,
            categories: account.categories,
            paymentMethods: account.paymentMethods,
            history: account.expenses,
            modelCategoryID: modelAnswer.flatMap { answer in
                answer.title == title ? CategoryPrompt.category(named: answer.categoryName, in: account.categories) : nil
            }
        )
    }

    // MARK: The expense

    /// The account the expense goes to.
    public var account: Account {
        // `init` and `next(after:answer:)` only ever store an existing ID.
        accounts.first { $0.id == accountID } ?? accounts[0]
    }

    public var displayTitle: String {
        title.isEmpty ? QuickLog.defaultTitle : title
    }

    /// The expense to save. Nil until it has an amount.
    public var expense: Expense? {
        guard let amount else { return nil }
        return Expense(
            id: expenseID,
            title: displayTitle,
            amount: amount,
            categoryID: categoryID,
            paymentMethodID: paymentMethodID,
            date: date,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    // MARK: Changing the card

    /// The options a detail of the confirmation card offers, in the user's
    /// order, and the one chosen now (nil for none).
    public func options(for field: Field) -> (options: [ShortcutFlow.Label], current: UUID?) {
        switch field {
        case .account:
            (accounts.map { Label(id: $0.id, name: $0.name) }, accountID)
        case .category:
            (account.categories.map { Label(id: $0.id, name: $0.name) }, categoryID)
        case .paymentMethod:
            (account.paymentMethods.map { Label(id: $0.id, name: $0.name) }, paymentMethodID)
        }
    }

    /// Sets a detail of the confirmation card. In another account the
    /// category and payment method stay the same by name where it has
    /// them, and are otherwise guessed again (or left empty).
    public mutating func change(_ field: Field, to id: UUID) {
        switch field {
        case .account:
            guard id != accountID, accounts.contains(where: { $0.id == id }) else { return }
            let previous = account
            accountID = id
            let guess = guess()
            let category = previous.category(id: categoryID)
            let method = previous.paymentMethod(id: paymentMethodID)
            categoryID = category.flatMap { QuickLog.category(id: $0.id, name: $0.name, in: account) }?.id ?? guess.categoryID
            paymentMethodID = method.flatMap { QuickLog.paymentMethod(id: $0.id, name: $0.name, in: account) }?.id ?? guess.paymentMethodID
        case .category:
            if let category = account.category(id: id) { categoryID = category.id }
        case .paymentMethod:
            if let method = account.paymentMethod(id: id) { paymentMethodID = method.id }
        }
    }
}

/// What the expense card of the "Add Expense" shortcut and the Wallet
/// automation shows, formatted: the amount on top, then title, account,
/// category, payment method and date.
public struct ShortcutCard: Hashable, Sendable {
    /// For a missing category or payment method, as in the expense editor.
    public static let noLabel = "None"

    public var amount: String
    public var title: String
    public var account: String
    public var category: String
    public var paymentMethod: String
    public var date: String

    public init(
        expense: Expense,
        in account: Account,
        currencyCode: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        amount = MoneyFormat.string(expense.amount, currencyCode: currencyCode, locale: locale)
        title = expense.title
        self.account = account.name
        category = account.category(id: expense.categoryID)?.name ?? Self.noLabel
        paymentMethod = account.paymentMethod(id: expense.paymentMethodID)?.name ?? Self.noLabel
        date = Self.dateText(expense.date, locale: locale, timeZone: timeZone)
    }

    /// Said before the confirmation when the shortcut passed an amount in
    /// another currency than Keaser's, which is then always confirmed: Keaser
    /// records the number as it is, in its own currency, and never converts
    /// it. Nil when the amount is in Keaser's currency or names none.
    public static func otherCurrencyNote(
        amount: Decimal,
        currencyCode given: String,
        recordedAs recorded: Decimal,
        appCurrencyCode: String,
        locale: Locale = .current
    ) -> String? {
        let code = given.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, code != appCurrencyCode.uppercased() else { return nil }
        let passed = MoneyFormat.string(amount, currencyCode: code, locale: locale)
        let added = MoneyFormat.string(recorded, currencyCode: appCurrencyCode, locale: locale)
        return "The shortcut passed \(passed), but Keaser records amounts in \(appCurrencyCode.uppercased()), so it will be added as \(added)."
    }

    /// Two-digit month and day in the locale's order: "04/08/2026" in the
    /// US, "08/04/2026" in the UK.
    public static func dateText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: locale.calendar, timeZone: timeZone)
            .year()
            .month(.twoDigits)
            .day(.twoDigits)
        return date.formatted(style)
    }
}
