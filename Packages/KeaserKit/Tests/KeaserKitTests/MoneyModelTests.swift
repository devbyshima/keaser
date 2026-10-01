import Foundation
import Testing
@testable import KeaserKit

/// The money model: wallets, income, transfers and the split rule, and how
/// a database from before them loads.
struct MoneyModelTests {
    /// A database exactly as the build before money tracking writes it (one
    /// account, a built-in and a custom category and payment method, one
    /// expense).
    static let currentBuildJSON = """
    {"accounts":[{"categories":[{"id":"A1B2C3D4-0001-4000-8000-000000000001","name":"Food & Drinks","symbol":"fork.knife","updatedAt":780000000},\
    {"id":"A1B2C3D4-0002-4000-8000-000000000002","name":"Pets","symbol":"pawprint.fill","updatedAt":780000001}],"categoriesOrderedAt":779600000,\
    "createdAt":779000000,"expenses":[\(expenseJSON)],"id":"6F1C2B0E-3A6D-4E57-9C1A-2B7D5E8F9A01","name":"Personal",\
    "paymentMethods":[{"id":"B1B2C3D4-0001-4000-8000-000000000001","name":"Credit Card","symbol":"creditcard.fill","updatedAt":780000000},\
    {"id":"B1B2C3D4-0002-4000-8000-000000000002","name":"MoMo","symbol":"phone.fill","updatedAt":780000002}],"paymentMethodsOrderedAt":779700000,\
    "updatedAt":779500000}],"accountsOrderedAt":779000000,"preferences":{"currencyCode":"RWF","firstWeekday":1,"hasCompletedOnboarding":false,\
    "hasProPurchase":false,"hasSeenWelcomeLetter":false,"selectedAccountID":"6F1C2B0E-3A6D-4E57-9C1A-2B7D5E8F9A01","settingsUpdatedAt":-63114076800,\
    "shortcutConfirmsDetails":true,"shortcutGoBackEnabled":true,"shortcutSmartSuggestionsEnabled":true,"smartSuggestionsEnabled":true,\
    "weeklySummaryEnabled":false},"version":1}
    """

    static let expenseJSON = """
    {"amount":12.5,"categoryID":"A1B2C3D4-0001-4000-8000-000000000001","createdAt":780050000.25,"date":780048000,\
    "id":"C1B2C3D4-0001-4000-8000-000000000001","paymentMethodID":"B1B2C3D4-0001-4000-8000-000000000001","title":"Lunch",\
    "updatedAt":780050000.25}
    """

    static let accountID = UUID(uuidString: "6F1C2B0E-3A6D-4E57-9C1A-2B7D5E8F9A01")!

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try DatabaseFile.makeDecoder().decode(type, from: Data(json.utf8))
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try DatabaseFile.makeEncoder().encode(value), as: UTF8.self)
    }

    // MARK: Migration

    @Test func aDatabaseFromTheBuildBeforeLoadsWithGuessesAndDefaults() throws {
        let database = try decode(Database.self, Self.currentBuildJSON)
        let account = try #require(database.accounts.first)
        #expect(account.categories.map(\.role) == [.expenses, .expenses])
        #expect(account.paymentMethods.map(\.kind) == [.creditCard, .mobileMoney])
        for wallet in account.paymentMethods {
            #expect(!wallet.isTracking)
            #expect(wallet.currencyCode == nil)
            #expect(wallet.openingBalance == 0)
            #expect(wallet.creditLimit == nil)
            #expect(!wallet.isSavings && !wallet.isHidden)
        }
        #expect(account.incomeCategories == IncomeCategory.defaults(for: Self.accountID))
        #expect(account.incomeCategories.map(\.name) == ["Salary", "Business", "Gifts", "Refunds"])
        #expect(account.incomeCategories.allSatisfy { $0.updatedAt == .distantPast })
        #expect(account.incomeCategoriesOrderedAt == .distantPast)
        #expect(account.incomes.isEmpty && account.transfers.isEmpty && account.balanceAdjustments.isEmpty)
        #expect(account.splitRule == SplitRule())
        let expense = try #require(account.expenses.first)
        #expect(expense.currencyCode == nil && expense.rate == nil)
        #expect(expense.amount == Decimal(string: "12.5"))
        // Everything that was there is as it was.
        #expect(account.name == "Personal")
        #expect(account.paymentMethodsOrderedAt == Date(timeIntervalSinceReferenceDate: 779_700_000))
        #expect(database.preferences.currencyCode == "RWF")
    }

    @Test func anUnchangedExpenseIsWrittenByteForByteAsBefore() throws {
        let expense = try decode(Expense.self, Self.expenseJSON)
        #expect(try encode(expense) == Self.expenseJSON)
    }

    @Test func labelsAreWrittenAsBeforePlusTheirGuess() throws {
        let category = try decode(ExpenseCategory.self, #"{"id":"A1B2C3D4-0002-4000-8000-000000000002","name":"Shopping","symbol":"cart.fill","updatedAt":780000001}"#)
        #expect(try encode(category) == #"{"id":"A1B2C3D4-0002-4000-8000-000000000002","name":"Shopping","role":"freeMoney","symbol":"cart.fill","updatedAt":780000001}"#)
        let method = try decode(PaymentMethod.self, #"{"id":"B1B2C3D4-0001-4000-8000-000000000001","name":"Credit Card","symbol":"creditcard.fill","updatedAt":780000000}"#)
        #expect(try encode(method) == #"{"id":"B1B2C3D4-0001-4000-8000-000000000001","kind":"creditCard","name":"Credit Card","symbol":"creditcard.fill","updatedAt":780000000}"#)
    }

    @Test func theGuessIsPinnedSoARenameKeepsIt() throws {
        var cash = try decode(PaymentMethod.self, #"{"id":"B1B2C3D4-0001-4000-8000-000000000001","name":"Cash","symbol":"banknote.fill"}"#)
        #expect(cash.kind == .cash)
        cash.name = "Pocket"
        #expect(try decode(PaymentMethod.self, try encode(cash)).kind == .cash)
        var travel = try decode(ExpenseCategory.self, #"{"id":"A1B2C3D4-0001-4000-8000-000000000001","name":"Travel","symbol":"airplane"}"#)
        #expect(travel.role == .freeMoney)
        travel.name = "Trips"
        #expect(try decode(ExpenseCategory.self, try encode(travel)).role == .freeMoney)
    }

    @Test func aStoredEmptyIncomeCategoryListStaysEmpty() throws {
        var account = Account(name: "Personal", incomeCategories: [])
        account.incomes = [Income(title: "Gift", amount: 5)]
        let read = try decode(Account.self, try encode(account))
        #expect(read.incomeCategories.isEmpty)
        #expect(read.incomes == account.incomes)
    }

    // MARK: Open sets

    @Test func kindsFromALaterVersionSurviveARoundTrip() throws {
        let method = try decode(PaymentMethod.self, #"{"id":"B1B2C3D4-0001-4000-8000-000000000001","name":"Ledger","symbol":"bitcoinsign","kind":"crypto"}"#)
        #expect(method.kind == WalletKind("crypto"))
        #expect(!WalletKind.known.contains(method.kind))
        #expect(try encode(method).contains(#""kind":"crypto""#))

        let category = try decode(ExpenseCategory.self, #"{"id":"A1B2C3D4-0001-4000-8000-000000000001","name":"Stocks","symbol":"chart.line.uptrend.xyaxis","role":"investments"}"#)
        #expect(category.role == CategoryRole(rawValue: "investments"))
        #expect(try encode(category).contains(#""role":"investments""#))

        let transfer = try decode(Transfer.self, #"{"id":"D1B2C3D4-0001-4000-8000-000000000001","kind":"loanRepayment","amountOut":5}"#)
        #expect(transfer.kind.rawValue == "loanRepayment")
        #expect(try encode(transfer).contains(#""kind":"loanRepayment""#))
    }

    @Test func walletKindsAreGuessedFromBuiltInNames() {
        #expect(WalletKind.guess(forName: "Credit Card") == .creditCard)
        #expect(WalletKind.guess(forName: " credit card ") == .creditCard)
        for name in ["Debit Card", "Bank Transfer", "Bank Account", "BANK"] {
            #expect(WalletKind.guess(forName: name) == .bank, "\(name)")
        }
        #expect(WalletKind.guess(forName: "Cash") == .cash)
        for name in ["E-Wallet", "Mobile Money", "MoMo", "e-wallet"] {
            #expect(WalletKind.guess(forName: name) == .mobileMoney, "\(name)")
        }
        #expect(WalletKind.guess(forName: "Piggy Bank") == .other)
        #expect(WalletKind.guess(forName: "") == .other)
        #expect(WalletKind.known == [.cash, .bank, .mobileMoney, .creditCard, .other])
        #expect(PaymentMethod.defaults().map(\.kind) == [.creditCard, .bank, .cash, .bank, .mobileMoney])
        #expect(PaymentMethod(name: "Visa", symbol: "creditcard", kind: .creditCard).kind == .creditCard)
    }

    @Test func categoryRolesAreGuessedFromBuiltInNames() {
        let roles = Dictionary(uniqueKeysWithValues: ExpenseCategory.defaults().map { ($0.name, $0.role) })
        #expect(roles == [
            "Food & Drinks": .expenses, "Transportation": .expenses, "Health": .expenses, "Services": .expenses,
            "Shopping": .freeMoney, "Entertainment": .freeMoney, "Travel": .freeMoney,
        ])
        #expect(CategoryRole.guess(forName: " ENTERTAINMENT ") == .freeMoney)
        #expect(CategoryRole.guess(forName: "Pets") == .expenses)
        #expect(ExpenseCategory(name: "Travel", symbol: "airplane", role: .expenses).role == .expenses)
    }

    // MARK: Rates

    @Test func aCorruptRateLosesOnlyTheRate() throws {
        let id = "C1B2C3D4-0001-4000-8000-000000000001"
        for rate in [#""nonsense""#, "[1,2]", "7", #"{"rate":"lots"}"#] {
            let expense = try decode(Expense.self, #"{"id":"\#(id)","title":"Lunch","amount":12,"currencyCode":"EUR","rate":\#(rate)}"#)
            #expect(expense.rate == nil, "\(rate)")
            #expect(expense.title == "Lunch" && expense.amount == 12 && expense.currencyCode == "EUR")
            #expect(try decode(Income.self, #"{"id":"\#(id)","title":"Pay","amount":3,"rate":\#(rate)}"#).rate == nil)
            #expect(try decode(Transfer.self, #"{"id":"\#(id)","amountOut":3,"rate":\#(rate)}"#).rate == nil)
        }
    }

    @Test func aSavedRateRoundTripsAndAnEmptyOneIsNotUsable() throws {
        let rate = ExchangeRate(rate: Decimal(string: "1385.37")!, currencyCode: "RWF", date: Date(timeIntervalSinceReferenceDate: 780_000_000), isTyped: true)
        let expense = Expense(title: "Dinner", amount: 30, currencyCode: "USD", rate: rate)
        let read = try decode(Expense.self, try encode(expense))
        #expect(read.rate == rate)
        #expect(read.currencyCode == "USD")
        #expect(rate.isUsable)
        let empty = try decode(ExchangeRate.self, "{}")
        #expect(empty.rate == 0 && empty.currencyCode.isEmpty && empty.date == .distantPast && !empty.isTyped)
        #expect(!empty.isUsable)
        #expect(!ExchangeRate(rate: 2, currencyCode: "", date: .now).isUsable)
        #expect(!ExchangeRate(rate: -1, currencyCode: "EUR", date: .now).isUsable)
    }

    // MARK: New models

    @Test func newModelsReadWithDefaultsForWhatIsMissing() throws {
        let id = UUID(uuidString: "D1B2C3D4-0001-4000-8000-000000000001")!
        let income = try decode(Income.self, #"{"id":"\#(id.uuidString)","date":780000000}"#)
        #expect(income.title == "" && income.amount == 0)
        #expect(income.currencyCode == nil && income.rate == nil && income.categoryID == nil && income.walletID == nil)
        #expect(income.createdAt == income.date && income.updatedAt == income.date)
        #expect(income.savingsPercent == nil && income.savingsTransferID == nil && !income.savingsSkipped)

        let transfer = try decode(Transfer.self, #"{"id":"\#(id.uuidString)","amountOut":12.5,"date":780000000}"#)
        #expect(transfer.kind == .manual)
        #expect(transfer.amountIn == Decimal(string: "12.5"))
        #expect(transfer.note == "" && transfer.fromWalletID == nil && transfer.toWalletID == nil && transfer.incomeID == nil)

        let adjustment = try decode(BalanceAdjustment.self, #"{"id":"\#(id.uuidString)"}"#)
        #expect(adjustment.balance == 0 && adjustment.walletID == nil)

        let category = try decode(IncomeCategory.self, #"{"id":"\#(id.uuidString)"}"#)
        #expect(category.name == "" && category.updatedAt == .distantPast)

        #expect(try decode(SplitRule.self, "{}") == SplitRule())
        let rule = try decode(SplitRule.self, #"{"isEnabled":true,"savingsPercent":10}"#)
        #expect(rule.isEnabled && rule.savingsPercent == 10 && rule.expensesPercent == 50 && rule.freeMoneyPercent == 30)

        #expect(throws: (any Error).self) { try decode(Income.self, #"{"title":"No ID"}"#) }
    }

    @Test func newModelsWriteOnlyWhatTheyHold() throws {
        let plainIncome = try encode(Income(title: "Pay", amount: 1))
        for key in ["currencyCode", "rate", "categoryID", "walletID", "savingsPercent", "savingsTransferID", "savingsSkipped"] {
            #expect(!plainIncome.contains("\"\(key)\""), "\(key)")
        }
        #expect(try encode(Income(title: "Pay", amount: 1, savingsSkipped: true)).contains(#""savingsSkipped":true"#))

        let plainWallet = try encode(PaymentMethod(name: "Cash", symbol: "banknote.fill"))
        for key in ["currencyCode", "trackingSince", "openingBalance", "creditLimit", "isSavings", "isHidden"] {
            #expect(!plainWallet.contains("\"\(key)\""), "\(key)")
        }
        let wallet = PaymentMethod(
            name: "Visa", symbol: "creditcard.fill", kind: .creditCard, currencyCode: "EUR",
            trackingSince: Date(timeIntervalSinceReferenceDate: 780_000_000), openingBalance: -120,
            creditLimit: 1000, isSavings: true, isHidden: true
        )
        #expect(try decode(PaymentMethod.self, try encode(wallet)) == wallet)

        let transfer = Transfer(kind: .cardPayment, fromWalletID: UUID(), toWalletID: nil, amountOut: 5, currencyOut: "EUR", amountIn: 6, currencyIn: "USD", note: "Card")
        #expect(try decode(Transfer.self, try encode(transfer)) == transfer)
    }

    @Test func walletHelpersReadItsFields() {
        var wallet = PaymentMethod(name: "Visa", symbol: "creditcard.fill", kind: .creditCard)
        #expect(!wallet.isTracking)
        #expect(wallet.isCreditCard)
        #expect(wallet.effectiveCurrency(display: "RWF") == "RWF")
        wallet.currencyCode = "USD"
        wallet.trackingSince = .now
        #expect(wallet.isTracking)
        #expect(wallet.effectiveCurrency(display: "RWF") == "USD")
        #expect(!PaymentMethod(name: "Cash", symbol: "banknote.fill").isCreditCard)
    }

    @Test func aSplitRuleIsValidWhenItAddsUpTo100() {
        #expect(SplitRule().isValid)
        #expect(SplitRule(savingsPercent: 0, expensesPercent: 100, freeMoneyPercent: 0).isValid)
        #expect(!SplitRule(savingsPercent: 30, expensesPercent: 50, freeMoneyPercent: 30).isValid)
        #expect(!SplitRule(savingsPercent: -10, expensesPercent: 80, freeMoneyPercent: 30).isValid)
        #expect(!SplitRule(savingsPercent: 120, expensesPercent: -10, freeMoneyPercent: -10).isValid)
    }

    @Test func accountLookupsFindTheirItems() {
        let income = Income(title: "Pay", amount: 1)
        let transfer = Transfer(fromWalletID: nil, toWalletID: nil, amountOut: 1)
        let account = Account(name: "Personal", incomes: [income], transfers: [transfer])
        #expect(account.income(id: income.id) == income)
        #expect(account.transfer(id: transfer.id) == transfer)
        #expect(account.incomeCategory(id: account.incomeCategories[0].id)?.name == "Salary")
        #expect(account.income(id: nil) == nil && account.transfer(id: UUID()) == nil && account.incomeCategory(id: nil) == nil)
    }
}

/// Built-in income categories get IDs derived from their account, so two
/// devices giving the same account its defaults agree.
struct MoneyDerivedIDTests {
    @Test func theSameAccountGetsTheSameIDsEveryTime() throws {
        let json = MoneyModelTests.currentBuildJSON
        let first = try DatabaseFile.makeDecoder().decode(Database.self, from: Data(json.utf8)).accounts[0].incomeCategories
        let second = try DatabaseFile.makeDecoder().decode(Database.self, from: Data(json.utf8)).accounts[0].incomeCategories
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Account(id: MoneyModelTests.accountID, name: "Elsewhere").incomeCategories.map(\.id) == first.map(\.id))
        // Pinned, so a change to the derivation can never slip by: these
        // are the IDs every device has already made.
        #expect(first.map(\.id.uuidString) == [
            "33A281AD-A345-86A8-A83D-F585C79CFE9D",
            "3A7B1F84-4BDC-8DC4-9AE6-61D4FCAA8221",
            "1704F258-4EE3-86D5-8D08-0E12CEF03D8E",
            "50541E87-0137-8315-A830-C7484D9BC29A",
        ])
    }

    @Test func differentAccountsGetDifferentIDs() {
        let a = IncomeCategory.defaults(for: UUID()).map(\.id)
        let b = IncomeCategory.defaults(for: UUID()).map(\.id)
        #expect(Set(a).isDisjoint(with: b))
        #expect(Set(a).count == 4)
    }

    @Test func derivedIDsAreVersion8RFC9562() {
        for text in ["", "a", "Salary", String(repeating: "é", count: 300)] {
            let uuid = UUID.derived(from: text).uuid
            #expect(uuid.6 >> 4 == 8, "\(text)")
            #expect(uuid.8 >> 6 == 0b10, "\(text)")
        }
        #expect(UUID.derived(from: "x") == UUID.derived(from: "x"))
        #expect(UUID.derived(from: "x") != UUID.derived(from: "y"))
    }

    @Test func builtInIncomeCategoriesRememberTheirIcon() {
        let defaults = IncomeCategory.defaults(for: UUID())
        #expect(defaults.map(\.symbol) == ["briefcase.fill", "storefront.fill", "gift.fill", "arrow.uturn.backward.circle.fill"])
        #expect(IncomeCategory.defaultSymbol(forName: " salary ") == "briefcase.fill")
        #expect(IncomeCategory.defaultSymbol(forName: "Refunds") == "arrow.uturn.backward.circle.fill")
        #expect(IncomeCategory.defaultSymbol(forName: "Lottery") == nil)
    }
}
