import Foundation
import Testing
@testable import KeaserKit

/// Wallet balances within one currency: the checkpoint rule on both sides,
/// adjustments, `asOf`, credit cards and the total
/// (`MoneyBalanceCurrencyTests` has the conversions).
struct MoneyBalanceTests {
    static func calendar(_ zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = 2
        return c
    }

    /// A moment of 2026 in UTC, in September unless said otherwise.
    static func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9) -> Date {
        Self.at(day, hour, minute, month: month)
    }

    /// 50,000 stated on 10 September at 09:00.
    private let cash = PaymentMethod(name: "Cash", symbol: "banknote.fill", trackingSince: Self.at(10, 9), openingBalance: 50_000)
    /// 200,000 stated on 1 September at 08:00.
    private let bank = PaymentMethod(name: "Bank Account", symbol: "building.columns.fill", trackingSince: Self.at(1, 8), openingBalance: 200_000)
    /// Not tracking a balance.
    private let debit = PaymentMethod(name: "Debit Card", symbol: "creditcard.and.123")
    /// Owes 50,000 on 1 September at 08:00, with a limit of 500,000.
    private let card = PaymentMethod(name: "Credit Card", symbol: "creditcard.fill", trackingSince: Self.at(1, 8), openingBalance: -50_000, creditLimit: 500_000)

    private func account(
        wallets: [PaymentMethod]? = nil,
        expenses: [Expense] = [],
        incomes: [Income] = [],
        transfers: [Transfer] = [],
        adjustments: [BalanceAdjustment] = []
    ) -> Account {
        Account(
            name: "Personal", paymentMethods: wallets ?? [cash, bank, debit, card], expenses: expenses,
            incomes: incomes, transfers: transfers, balanceAdjustments: adjustments
        )
    }

    /// Sums it is compared with are written `Decimal(...)`: next to a
    /// `Decimal?`, literal arithmetic is Int, compared through AnyHashable,
    /// and never equal.
    private func balance(of wallet: UUID, in account: Account, asOf: Date? = nil, calendar: Calendar? = nil) -> Decimal? {
        WalletBalances.balance(
            of: wallet, in: account, display: "RWF", converter: CurrencyConverter(displayCurrency: "RWF", rates: nil),
            calendar: calendar ?? Self.calendar(), asOf: asOf
        )?.amount
    }

    private func expense(_ amount: Decimal, from wallet: UUID?, on date: Date, loggedAt: Date? = nil) -> Expense {
        Expense(title: "Spend", amount: amount, paymentMethodID: wallet, date: date, createdAt: loggedAt ?? date, updatedAt: loggedAt ?? date)
    }

    private func income(_ amount: Decimal, into wallet: UUID?, on date: Date, loggedAt: Date? = nil) -> Income {
        Income(title: "Pay", amount: amount, walletID: wallet, date: date, createdAt: loggedAt ?? date, updatedAt: loggedAt ?? date)
    }

    private func transfer(
        _ amount: Decimal, from: UUID?, to: UUID?, on date: Date, loggedAt: Date? = nil, kind: TransferKind = .manual
    ) -> Transfer {
        Transfer(kind: kind, fromWalletID: from, toWalletID: to, amountOut: amount, date: date, createdAt: loggedAt ?? date, updatedAt: loggedAt ?? date)
    }

    private func adjustment(_ balance: Decimal, of wallet: UUID?, at date: Date, madeAt: Date? = nil, id: UUID = UUID()) -> BalanceAdjustment {
        BalanceAdjustment(id: id, walletID: wallet, balance: balance, date: date, createdAt: madeAt ?? date, updatedAt: madeAt ?? date)
    }

    // MARK: Tracking

    @Test func aWalletNotTrackingOrNotInTheAccountHasNoBalance() {
        let spent = account(expenses: [expense(1_000, from: debit.id, on: at(12))])
        #expect(balance(of: debit.id, in: spent) == nil)
        #expect(balance(of: UUID(), in: spent) == nil)
        // A wallet of another account.
        let other = PaymentMethod(name: "Cash", symbol: "banknote.fill", trackingSince: at(1), openingBalance: 5)
        #expect(balance(of: other.id, in: spent) == nil)
    }

    @Test func theOpeningBalanceAloneIsTheBalance() {
        let full = WalletBalances.balance(
            of: cash.id, in: account(), display: "RWF",
            converter: CurrencyConverter(displayCurrency: "RWF", rates: nil), calendar: Self.calendar()
        )
        #expect(full == WalletBalance(amount: 50_000, unconverted: 0))
        // Entries of other wallets, or of none, never touch it.
        let others = account(
            expenses: [expense(1_000, from: bank.id, on: at(12)), expense(2_000, from: nil, on: at(12))],
            incomes: [income(5_000, into: nil, on: at(12)), income(7_000, into: debit.id, on: at(12))],
            transfers: [transfer(3_000, from: bank.id, to: debit.id, on: at(12))]
        )
        #expect(balance(of: cash.id, in: others) == 50_000)
    }

    @Test func incomesAndTransfersInAddExpensesAndTransfersOutSubtract() {
        let moved = account(
            expenses: [expense(3_000, from: cash.id, on: at(11)), expense(1_500, from: cash.id, on: at(12))],
            incomes: [income(20_000, into: cash.id, on: at(13))],
            transfers: [
                transfer(10_000, from: bank.id, to: cash.id, on: at(14)),
                transfer(4_000, from: cash.id, to: bank.id, on: at(15)),
                // From the wallet to itself: nothing, even with amounts
                // that do not match.
                Transfer(fromWalletID: cash.id, toWalletID: cash.id, amountOut: 7_000, amountIn: 6_500, date: at(16), createdAt: at(16)),
                // The other wallet deleted: the side still here counts.
                transfer(2_000, from: cash.id, to: nil, on: at(16)),
                transfer(1_000, from: nil, to: cash.id, on: at(16)),
            ]
        )
        #expect(balance(of: cash.id, in: moved) == Decimal(50_000 - 3_000 - 1_500 + 20_000 + 10_000 - 4_000 - 2_000 + 1_000))
        #expect(balance(of: bank.id, in: moved) == Decimal(200_000 - 10_000 + 4_000))
    }

    // MARK: The checkpoint rule

    @Test func anEntryDatedBeforeTheCheckpointDayIsAlreadyInTheBalance() {
        // Cash was stated on 10 September at 09:00.
        let before = account(
            expenses: [
                expense(1_000, from: cash.id, on: at(9, 12)),
                // Backdated: logged after the checkpoint, for a day before it.
                expense(2_000, from: cash.id, on: at(9, 23, 59), loggedAt: at(20)),
                expense(4_000, from: cash.id, on: at(1), loggedAt: at(10, 10)),
            ],
            incomes: [income(8_000, into: cash.id, on: at(9, 0), loggedAt: at(12))],
            transfers: [
                transfer(16_000, from: bank.id, to: cash.id, on: at(9), loggedAt: at(11)),
                transfer(32_000, from: cash.id, to: bank.id, on: at(9), loggedAt: at(11)),
            ]
        )
        #expect(balance(of: cash.id, in: before) == 50_000)
        // The bank, stated on the 1st, counts the same transfers.
        #expect(balance(of: bank.id, in: before) == Decimal(200_000 - 16_000 + 32_000))
    }

    @Test func anEntryDatedAfterTheCheckpointDayCountsWheneverItWasLogged() {
        // Logged before the wallet started tracking, for a later day.
        let planned = account(
            expenses: [expense(1_000, from: cash.id, on: at(11, 0), loggedAt: at(5))],
            incomes: [income(500, into: cash.id, on: at(1, 0, month: 10), loggedAt: at(10, 8))],
            transfers: [transfer(250, from: cash.id, to: bank.id, on: at(11, 0), loggedAt: at(10, 8, 59))]
        )
        #expect(balance(of: cash.id, in: planned) == Decimal(50_000 - 1_000 + 500 - 250))
    }

    @Test func onTheCheckpointDayTheTimeItWasLoggedDecides() {
        // Cash was stated on 10 September at 09:00. The time of an entry's
        // date means nothing; only its day and when it was logged.
        let sameDay = account(
            expenses: [
                expense(1_000, from: cash.id, on: at(10, 0), loggedAt: at(10, 8)),
                // Logged at the very moment of the checkpoint: in it.
                expense(2_000, from: cash.id, on: at(10, 0), loggedAt: at(10, 9)),
                expense(4_000, from: cash.id, on: at(10, 0), loggedAt: at(10, 9, 1)),
                // Dated late in the day but logged before: in it.
                expense(8_000, from: cash.id, on: at(10, 23, 59), loggedAt: at(10, 7)),
            ],
            incomes: [
                income(100, into: cash.id, on: at(10, 0), loggedAt: at(10, 8, 59)),
                income(200, into: cash.id, on: at(10, 0), loggedAt: at(10, 18)),
            ],
            transfers: [
                transfer(10, from: bank.id, to: cash.id, on: at(10, 0), loggedAt: at(10, 6)),
                transfer(20, from: bank.id, to: cash.id, on: at(10, 0), loggedAt: at(10, 10)),
                transfer(40, from: cash.id, to: bank.id, on: at(10, 0), loggedAt: at(10, 10)),
                transfer(80, from: cash.id, to: bank.id, on: at(10, 0), loggedAt: at(10, 8)),
            ]
        )
        #expect(balance(of: cash.id, in: sameDay) == Decimal(50_000 - 4_000 + 200 + 20 - 40))
        // Seen from the bank, stated on the 1st, every one of them counts.
        #expect(balance(of: bank.id, in: sameDay) == Decimal(200_000 - 10 - 20 + 40 + 80))
    }

    @Test func theCheckpointDayIsTheCalendarsDay() {
        // Stated at 21:00 UTC on 10 September, 23:00 that day in Kigali.
        let wallet = PaymentMethod(name: "Bank", symbol: "building.columns.fill", trackingSince: at(10, 21), openingBalance: 1_000)
        // Dated 22:30 UTC on the 10th, the 11th in Kigali, and logged
        // before the checkpoint.
        let late = account(wallets: [wallet], expenses: [expense(100, from: wallet.id, on: at(10, 22, 30), loggedAt: at(10, 20))])
        #expect(balance(of: wallet.id, in: late, calendar: Self.calendar()) == 1_000)
        #expect(balance(of: wallet.id, in: late, calendar: Self.calendar("Africa/Kigali")) == 900)
    }

    // MARK: Adjustments

    @Test func aLaterAdjustmentIsTheNewBase() {
        // Set Balance: 30,000 on 20 September at 18:00.
        let spending = [
            expense(5_000, from: cash.id, on: at(15)),
            expense(1_000, from: cash.id, on: at(20, 0), loggedAt: at(20, 17)),
            expense(2_000, from: cash.id, on: at(20, 0), loggedAt: at(20, 19)),
            expense(4_000, from: cash.id, on: at(21)),
            // Backdated after the adjustment, for a day before it.
            expense(8_000, from: cash.id, on: at(19), loggedAt: at(22)),
        ]
        let adjusted = account(expenses: spending, adjustments: [adjustment(30_000, of: cash.id, at: at(20, 18))])
        #expect(balance(of: cash.id, in: adjusted) == Decimal(30_000 - 2_000 - 4_000))
        // Without it, everything after the opening counts.
        #expect(balance(of: cash.id, in: account(expenses: spending)) == Decimal(50_000 - 5_000 - 1_000 - 2_000 - 4_000 - 8_000))
    }

    @Test func onlyTheWalletsOwnAdjustmentsSinceItStartedTrackingCount() {
        let others = account(adjustments: [
            adjustment(1, of: bank.id, at: at(20)),
            adjustment(2, of: nil, at: at(20)),
            // Before it started tracking (a wallet set up again): ignored.
            adjustment(3, of: cash.id, at: at(10, 8, 59)),
            // For a wallet not tracking: ignored with it.
            adjustment(4, of: debit.id, at: at(20)),
        ])
        #expect(balance(of: cash.id, in: others) == 50_000)
        #expect(balance(of: bank.id, in: others) == 1)
        #expect(balance(of: debit.id, in: others) == nil)
    }

    @Test func theLatestAdjustmentByDateWinsNotTheLastOneMade() {
        let adjusted = account(
            expenses: [expense(500, from: cash.id, on: at(18))],
            adjustments: [
                adjustment(10_000, of: cash.id, at: at(20), madeAt: at(25)),
                // Made later, for an earlier moment.
                adjustment(20_000, of: cash.id, at: at(15), madeAt: at(26)),
            ]
        )
        #expect(balance(of: cash.id, in: adjusted) == 10_000)
    }

    @Test func tiesAreDecidedTheSameWayOnEveryDevice() {
        let low = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        // The same moment: the one made later wins, whatever the order.
        let first = adjustment(10_000, of: cash.id, at: at(20), madeAt: at(20, 13), id: high)
        let second = adjustment(20_000, of: cash.id, at: at(20), madeAt: at(20, 14), id: low)
        #expect(balance(of: cash.id, in: account(adjustments: [first, second])) == 20_000)
        #expect(balance(of: cash.id, in: account(adjustments: [second, first])) == 20_000)
        // Made at the same moment too: the greater ID.
        var twin = second
        twin.createdAt = first.createdAt
        #expect(balance(of: cash.id, in: account(adjustments: [first, twin])) == 10_000)
        #expect(balance(of: cash.id, in: account(adjustments: [twin, first])) == 10_000)
        // An adjustment at the opening moment wins over the opening balance.
        let atOpening = adjustment(7, of: cash.id, at: cash.trackingSince!, madeAt: .distantPast)
        #expect(balance(of: cash.id, in: account(adjustments: [atOpening])) == 7)
    }

    // MARK: As of

    @Test func asOfGivesTheBalanceOnAnEarlierDay() {
        let history = account(
            expenses: [
                expense(1_000, from: cash.id, on: at(12)),
                // Dated the 15th, logged on the 16th.
                expense(2_000, from: cash.id, on: at(15, 0), loggedAt: at(16)),
                expense(4_000, from: cash.id, on: at(16)),
            ],
            adjustments: [
                adjustment(30_000, of: cash.id, at: at(14, 20)),
                adjustment(10_000, of: cash.id, at: at(15, 18)),
            ]
        )
        // Today: the adjustment of the 15th, then what came after it.
        #expect(balance(of: cash.id, in: history) == Decimal(10_000 - 2_000 - 4_000))
        // At noon on the 15th the second adjustment was not stated yet, and
        // what is dated that day counts, whenever it was logged.
        #expect(balance(of: cash.id, in: history, asOf: at(15, 12)) == Decimal(30_000 - 2_000))
        // Before any adjustment.
        #expect(balance(of: cash.id, in: history, asOf: at(13)) == Decimal(50_000 - 1_000))
        // The moment it started tracking, and just before.
        #expect(balance(of: cash.id, in: history, asOf: at(10, 9)) == 50_000)
        #expect(balance(of: cash.id, in: history, asOf: at(10, 8, 59)) == nil)
    }

    // MARK: Credit cards

    @Test func aCardsBalanceIsBelowZeroWhileItOwes() {
        let spent = account(expenses: [expense(30_000, from: card.id, on: at(5))])
        #expect(card.isCreditCard)
        #expect(balance(of: card.id, in: spent) == -80_000)
        let status = CreditCardStatus(balance: -80_000, creditLimit: card.creditLimit)
        #expect(status.owed == 80_000)
        #expect(status.available == 420_000)
    }

    @Test func payingACardIsATransferIntoIt() {
        let expenses = [expense(30_000, from: card.id, on: at(5))]
        let paid = account(expenses: expenses, transfers: [transfer(80_000, from: bank.id, to: card.id, on: at(6), kind: .cardPayment)])
        #expect(balance(of: card.id, in: paid) == 0)
        #expect(balance(of: bank.id, in: paid) == 120_000)
        let status = CreditCardStatus(balance: 0, creditLimit: 500_000)
        #expect(status.owed == 0 && status.available == 500_000)
    }

    @Test func anOverpaidCardHasMoreThanItsLimitAvailable() {
        let overpaid = account(transfers: [transfer(70_000, from: bank.id, to: card.id, on: at(6), kind: .cardPayment)])
        let balance = balance(of: card.id, in: overpaid)
        #expect(balance == 20_000)
        let status = CreditCardStatus(balance: 20_000, creditLimit: 500_000)
        #expect(status.owed == 0)
        #expect(status.available == 520_000)
    }

    @Test func overTheLimitNothingIsAvailable() {
        let over = account(expenses: [expense(480_000, from: card.id, on: at(5))])
        #expect(balance(of: card.id, in: over) == -530_000)
        let status = CreditCardStatus(balance: -530_000, creditLimit: 500_000)
        #expect(status.owed == 530_000)
        #expect(status.available == -30_000)
        // Exactly at the limit.
        #expect(CreditCardStatus(balance: -500_000, creditLimit: 500_000).available == 0)
    }

    @Test func aCardWithoutALimitHasNothingAvailableToShow() {
        let status = CreditCardStatus(balance: -1_000, creditLimit: nil)
        #expect(status.owed == 1_000)
        #expect(status.available == nil)
    }

    // MARK: The total

    @Test func theTotalAddsTrackedVisibleWalletsAndCardsCountAgainstIt() {
        let hidden = PaymentMethod(name: "Old Wallet", symbol: "wallet.bifold.fill", trackingSince: at(1), openingBalance: 1_000_000, isHidden: true)
        let wallets = [cash, bank, debit, card, hidden]
        let spent = account(
            wallets: wallets,
            expenses: [expense(10_000, from: debit.id, on: at(12)), expense(5_000, from: cash.id, on: at(12))]
        )
        let total = WalletBalances.total(
            in: spent, display: "RWF", converter: CurrencyConverter(displayCurrency: "RWF", rates: nil), calendar: Self.calendar()
        )
        // Cash 45,000, the bank 200,000 and the card -50,000; the debit
        // card (not tracking) and the hidden wallet are left out.
        #expect(total.amount == 195_000)
        #expect(total.unconverted == 0)
        // A hidden wallet still has its own balance.
        #expect(balance(of: hidden.id, in: spent) == 1_000_000)
    }

    @Test func anAccountWithoutTrackedWalletsTotalsNothing() {
        let total = WalletBalances.total(
            in: Account(name: "New"), display: "RWF",
            converter: CurrencyConverter(displayCurrency: "RWF", rates: nil), calendar: Self.calendar()
        )
        #expect(total.amount == 0)
        #expect(total.unconverted == 0)
    }
}
