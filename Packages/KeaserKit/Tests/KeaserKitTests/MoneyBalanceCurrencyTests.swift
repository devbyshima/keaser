import Foundation
import Testing
@testable import KeaserKit

/// Wallet balances across currencies: entries converted at their saved
/// rates or today's table, what cannot be converted, rounding to the
/// wallet's places, transfers between currencies, and the total in the
/// display currency.
struct MoneyBalanceCurrencyTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A day of September 2026, noon UTC.
    private static func at(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// Every wallet starts tracking on 2 September at 08:00.
    private static let since = at(2, 8)

    private let dollars = PaymentMethod(name: "Dollars", symbol: "dollarsign", kind: .bank, currencyCode: "USD", trackingSince: since, openingBalance: 100)
    /// In the display currency, whatever it is.
    private let francs = PaymentMethod(name: "Cash", symbol: "banknote.fill", trackingSince: since, openingBalance: 50_000)
    private let yen = PaymentMethod(name: "Yen", symbol: "yensign", kind: .cash, currencyCode: "JPY", trackingSince: since)
    private let dinars = PaymentMethod(name: "Dinars", symbol: "banknote.fill", kind: .bank, currencyCode: "KWD", trackingSince: since)

    /// 1 USD = 0.9 EUR = 1400 RWF = 150 JPY = 0.3 KWD, and no GBP.
    private func table(rwf: Decimal = 1400) -> ExchangeRates {
        ExchangeRates(base: "USD", rates: ["EUR": d("0.9"), "RWF": rwf, "JPY": 150, "KWD": d("0.3")], date: Self.at(30), fetchedAt: Self.at(30))
    }

    private func d(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    private func rate(_ value: String, to code: String) -> ExchangeRate {
        ExchangeRate(rate: d(value), currencyCode: code, date: Self.at(10))
    }

    private func account(
        wallets: [PaymentMethod]? = nil,
        expenses: [Expense] = [],
        incomes: [Income] = [],
        transfers: [Transfer] = []
    ) -> Account {
        Account(name: "Personal", paymentMethods: wallets ?? [dollars, francs, yen, dinars], expenses: expenses, incomes: incomes, transfers: transfers)
    }

    private func expense(_ amount: String, _ currency: String?, from wallet: UUID?, rate: ExchangeRate? = nil, on day: Int = 10) -> Expense {
        Expense(title: "Spend", amount: d(amount), paymentMethodID: wallet, date: Self.at(day), createdAt: Self.at(day), currencyCode: currency, rate: rate)
    }

    private func income(_ amount: String, _ currency: String?, into wallet: UUID?, rate: ExchangeRate? = nil) -> Income {
        Income(title: "Pay", amount: d(amount), currencyCode: currency, rate: rate, walletID: wallet, date: Self.at(10), createdAt: Self.at(10))
    }

    private func balance(of wallet: UUID, in account: Account, display: String = "RWF", rates: ExchangeRates?) -> WalletBalance? {
        WalletBalances.balance(
            of: wallet, in: account, display: display,
            converter: CurrencyConverter(displayCurrency: display, rates: rates), calendar: Self.calendar
        )
    }

    private func total(of account: Account, display: String = "RWF", rates: ExchangeRates?) -> (amount: Decimal, unconverted: Int) {
        WalletBalances.total(in: account, display: display, converter: CurrencyConverter(displayCurrency: display, rates: rates), calendar: Self.calendar)
    }

    // MARK: Converting entries

    @Test func entriesInTheWalletsCurrencyAreNeverConverted() {
        let same = account(
            expenses: [expense("20", nil, from: dollars.id), expense("5", "usd", from: dollars.id)],
            incomes: [income("50", "USD", into: dollars.id)]
        )
        #expect(balance(of: dollars.id, in: same, rates: nil) == WalletBalance(amount: 125, unconverted: 0))
    }

    @Test func aWalletWithoutACurrencyFollowsTheDisplayCurrency() {
        let spent = account(expenses: [expense("1000", nil, from: francs.id)])
        #expect(balance(of: francs.id, in: spent, rates: nil) == WalletBalance(amount: 49_000))
        // The display currency changed: the same numbers, relabelled.
        #expect(balance(of: francs.id, in: spent, display: "EUR", rates: nil) == WalletBalance(amount: 49_000))
        // An entry pinned to the old currency is converted: 1,400 RWF is
        // 0.90 EUR.
        let pinned = account(expenses: [expense("1400", "RWF", from: francs.id)])
        #expect(balance(of: francs.id, in: pinned, display: "EUR", rates: table())?.amount == d("49999.1"))
        #expect(balance(of: francs.id, in: pinned, display: "EUR", rates: nil) == WalletBalance(amount: 50_000, unconverted: 1))
    }

    @Test func anEntryInAnotherCurrencyUsesItsSavedRate() {
        let saved = account(expenses: [
            // Saved while the display currency was USD: 10 EUR is 12 USD.
            expense("10", "EUR", from: dollars.id, rate: rate("1.2", to: "USD")),
            // Saved into RWF: 15,000 RWF, which today's table makes 10.71 USD.
            expense("10", "EUR", from: dollars.id, rate: rate("1500", to: "RWF")),
        ])
        #expect(balance(of: dollars.id, in: saved, rates: table()) == WalletBalance(amount: d("77.29")))
        // A new day's table moves only the part it converts: 15,000 RWF is
        // now 10 USD, and the 12 USD stays.
        #expect(balance(of: dollars.id, in: saved, rates: table(rwf: 1500)) == WalletBalance(amount: 78))
        // A saved rate into the wallet's own currency needs no table.
        let direct = account(expenses: [expense("10", "EUR", from: dollars.id, rate: rate("1.2", to: "USD"))])
        #expect(balance(of: dollars.id, in: direct, rates: nil) == WalletBalance(amount: 88))
    }

    @Test func withoutAUsableSavedRateTodaysTableConverts() {
        // 10 EUR is 11.11 USD today.
        for saved in [nil, rate("0", to: "RWF"), rate("1500", to: ""), rate("-2", to: "USD")] {
            let spent = account(expenses: [expense("10", "EUR", from: dollars.id, rate: saved)])
            #expect(balance(of: dollars.id, in: spent, rates: table()) == WalletBalance(amount: d("88.89")))
        }
    }

    @Test func whatCannotBeConvertedIsLeftOutAndCounted() {
        let unknown = account(
            expenses: [
                // No GBP in the table, and no saved rate.
                expense("10", "GBP", from: dollars.id),
                // Saved into RWF, but no table to take RWF to USD.
                expense("10", "EUR", from: dollars.id, rate: rate("1500", to: "RWF")),
                // Before the checkpoint: not counted at all.
                expense("99", "GBP", from: dollars.id, on: 1),
                // A saved rate into USD converts what the table cannot.
                expense("8", "GBP", from: dollars.id, rate: rate("1.25", to: "USD")),
            ],
            incomes: [income("5", "GBP", into: dollars.id)]
        )
        #expect(balance(of: dollars.id, in: unknown, rates: nil) == WalletBalance(amount: 90, unconverted: 3))
        // With the table, only the GBP ones without a rate are left out.
        #expect(balance(of: dollars.id, in: unknown, rates: table()) == WalletBalance(amount: d("79.29"), unconverted: 2))
    }

    @Test func convertedEntriesAreRoundedToTheWalletsPlaces() {
        let rounded = account(
            expenses: [
                // 3.33 USD is 499.5 JPY: 500, halves away from zero.
                expense("3.33", "USD", from: yen.id),
                // 10 EUR is 3.3333 KWD: 3.333.
                expense("10", "EUR", from: dinars.id),
                // 2 EUR is 3,111.11 RWF: 3,111.
                expense("2", "EUR", from: francs.id),
            ],
            // 3.31 USD is 496.5 JPY: 497.
            incomes: [income("3.31", "USD", into: yen.id)]
        )
        #expect(balance(of: yen.id, in: rounded, rates: table())?.amount == -3)
        #expect(balance(of: dinars.id, in: rounded, rates: table())?.amount == d("-3.333"))
        #expect(balance(of: francs.id, in: rounded, rates: table())?.amount == 46_889)
    }

    // MARK: Transfers between currencies

    @Test func aTransferBetweenCurrenciesMovesWhatLeftAndWhatArrived() {
        // 140,000 RWF left the cash and 98 USD arrived, after fees.
        let moved = account(transfers: [
            Transfer(fromWalletID: francs.id, toWalletID: dollars.id, amountOut: 140_000, amountIn: 98, date: Self.at(10), createdAt: Self.at(10)),
        ])
        #expect(balance(of: francs.id, in: moved, rates: nil) == WalletBalance(amount: -90_000))
        #expect(balance(of: dollars.id, in: moved, rates: nil) == WalletBalance(amount: 198))
    }

    @Test func whatArrivedInAnotherCurrencyKeepsTheTransfersValue() {
        // Made while the dollar wallet was in EUR (its currency pinned on
        // the transfer), and the wallet has been in USD since. The from
        // wallet is gone, its currency pinned too.
        func arrived(out: String, _ amountOut: String, in amountIn: String, rate: ExchangeRate?) -> Decimal? {
            let transfer = Transfer(
                fromWalletID: nil, toWalletID: dollars.id, amountOut: d(amountOut), currencyOut: out,
                amountIn: d(amountIn), currencyIn: "EUR", rate: rate, date: Self.at(10), createdAt: Self.at(10)
            )
            return balance(of: dollars.id, in: account(transfers: [transfer]), rates: table())?.amount
        }
        // One currency: the saved rate is the rate of what arrived. 90 EUR
        // at 1,500 RWF is 135,000 RWF, 96.43 USD today.
        #expect(arrived(out: "EUR", "90", in: "90", rate: rate("1500", to: "RWF")) == d("196.43"))
        // Two: what arrived was worth what left. 50 GBP at 1,800 RWF is
        // 90,000 RWF, 64.29 USD today, whatever today's EUR rate says.
        #expect(arrived(out: "GBP", "50", in: "60", rate: rate("1800", to: "RWF")) == d("164.29"))
        // No saved rate: today's table, 60 EUR is 66.67 USD.
        #expect(arrived(out: "GBP", "50", in: "60", rate: nil) == d("166.67"))
        // Nothing arrived to derive a rate from: today's table again.
        #expect(arrived(out: "GBP", "50", in: "0", rate: rate("1800", to: "RWF")) == 100)
    }

    // MARK: The total

    @Test func theTotalIsInTheDisplayCurrencyAtTodaysRates() {
        let pinnedFrancs = PaymentMethod(name: "Bank", symbol: "building.columns.fill", currencyCode: "RWF", trackingSince: Self.since, openingBalance: 50_000)
        // A rate saved on an entry does not convert a balance.
        let wallets = account(
            wallets: [dollars, pinnedFrancs],
            expenses: [expense("10", nil, from: dollars.id, rate: rate("1000", to: "RWF"))]
        )
        // 90 USD and 50,000 RWF.
        #expect(total(of: wallets, rates: table()) == (amount: 176_000, unconverted: 0))
        #expect(total(of: wallets, rates: table(rwf: 1500)) == (amount: 185_000, unconverted: 0))
        // Shown in dollars: 50,000 RWF is 35.71 USD.
        #expect(total(of: wallets, display: "USD", rates: table()) == (amount: d("125.71"), unconverted: 0))
    }

    @Test func aBalanceThatCannotBeConvertedIsLeftOutOfTheTotal() {
        let pounds = PaymentMethod(name: "Pounds", symbol: "sterlingsign", kind: .bank, currencyCode: "GBP", trackingSince: Self.since, openingBalance: 10)
        let hiddenPounds = PaymentMethod(name: "Old Pounds", symbol: "sterlingsign", currencyCode: "GBP", trackingSince: Self.since, openingBalance: 10, isHidden: true)
        let notTracking = PaymentMethod(name: "Euros", symbol: "eurosign", currencyCode: "EUR")
        let wallets = account(
            wallets: [dollars, francs, pounds, hiddenPounds, notTracking],
            expenses: [expense("10", "GBP", from: dollars.id)]
        )
        // No table: only the cash, in the display currency, is in it. The
        // dollars and the pounds are left out, a wallet each.
        #expect(total(of: wallets, rates: nil) == (amount: 50_000, unconverted: 2))
        // With the table, the dollars are in, less the GBP expense they
        // could not convert; the pounds stay out.
        #expect(total(of: wallets, rates: table()) == (amount: 190_000, unconverted: 2))
    }

    // MARK: A balance stated in another currency

    @Test func aBalanceStatedInAnotherCurrencyIsConvertedAtTodaysRates() {
        var spent = account(expenses: [expense("20", nil, from: dollars.id)])
        spent.balanceAdjustments = [
            BalanceAdjustment(walletID: dollars.id, balance: 30_000, currencyCode: "JPY", date: Self.at(5), createdAt: Self.at(5)),
        ]
        // 30,000 JPY is 200 USD; 20 spent since leaves 180.
        #expect(balance(of: dollars.id, in: spent, rates: table()) == WalletBalance(amount: 180, unconverted: 0))
        // Without rates it is passed over for the opening 100, and counted.
        #expect(balance(of: dollars.id, in: spent, rates: nil) == WalletBalance(amount: 80, unconverted: 1))
        // Pinned to the wallet's own currency, it is taken as stated.
        spent.balanceAdjustments[0].currencyCode = "usd"
        spent.balanceAdjustments[0].balance = 70
        #expect(balance(of: dollars.id, in: spent, rates: nil) == WalletBalance(amount: 50, unconverted: 0))

        // One the table lacks, later than that, is passed over for it.
        spent.balanceAdjustments.append(
            BalanceAdjustment(walletID: dollars.id, balance: 40, currencyCode: "GBP", date: Self.at(7), createdAt: Self.at(7))
        )
        #expect(balance(of: dollars.id, in: spent, rates: table()) == WalletBalance(amount: 50, unconverted: 1))
        // A later one in the wallet's currency: nothing is passed over.
        spent.balanceAdjustments.append(
            BalanceAdjustment(walletID: dollars.id, balance: 90, date: Self.at(8), createdAt: Self.at(8))
        )
        #expect(balance(of: dollars.id, in: spent, rates: table()) == WalletBalance(amount: 70, unconverted: 0))
        // Rounded to the wallet's places: 1 USD is 0.3 KWD.
        var dinarWallet = account()
        dinarWallet.balanceAdjustments = [
            BalanceAdjustment(walletID: dinars.id, balance: d("10.01"), currencyCode: "USD", date: Self.at(5), createdAt: Self.at(5)),
        ]
        #expect(balance(of: dinars.id, in: dinarWallet, rates: table()) == WalletBalance(amount: d("3.003"), unconverted: 0))
    }
}
