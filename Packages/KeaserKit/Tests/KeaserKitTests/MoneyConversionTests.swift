import Foundation
import Testing
@testable import KeaserKit

/// Currency places, rounding, the rate table and converting.
struct MoneyConversionTests {
    private let day = Date(timeIntervalSinceReferenceDate: 780_000_000)

    /// 1 USD = 0.9 EUR = 1400 RWF = 150 JPY = 0.3 KWD.
    private var table: ExchangeRates {
        ExchangeRates(base: "USD", rates: ["EUR": Decimal(string: "0.9")!, "RWF": 1400, "JPY": 150, "KWD": Decimal(string: "0.3")!], date: day, fetchedAt: day)
    }

    private func saved(_ rate: String, _ code: String) -> ExchangeRate {
        ExchangeRate(rate: Decimal(string: rate)!, currencyCode: code, date: day)
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    // MARK: Places and rounding

    @Test func eachCurrencyHasItsOwnPlaces() {
        #expect(CurrencyMath.fractionDigits(for: "USD") == 2)
        #expect(CurrencyMath.fractionDigits(for: "EUR") == 2)
        #expect(CurrencyMath.fractionDigits(for: "JPY") == 0)
        #expect(CurrencyMath.fractionDigits(for: "RWF") == 0)
        #expect(CurrencyMath.fractionDigits(for: "KWD") == 3)
        #expect(CurrencyMath.fractionDigits(for: "usd") == 2)
    }

    @Test func roundingGoesToThePlacesHalvesAwayFromZero() {
        #expect(CurrencyMath.rounded(decimal("1234.5"), currencyCode: "JPY") == 1235)
        #expect(CurrencyMath.rounded(decimal("2.5"), currencyCode: "RWF") == 3)
        #expect(CurrencyMath.rounded(decimal("-2.5"), currencyCode: "RWF") == -3)
        #expect(CurrencyMath.rounded(decimal("2.49"), currencyCode: "RWF") == 2)
        #expect(CurrencyMath.rounded(decimal("1.005"), currencyCode: "USD") == decimal("1.01"))
        #expect(CurrencyMath.rounded(decimal("2.004"), currencyCode: "USD") == 2)
        #expect(CurrencyMath.rounded(decimal("1.23456"), currencyCode: "KWD") == decimal("1.235"))
        #expect(CurrencyMath.rounded(decimal("12345678901234567.895"), currencyCode: "USD") == decimal("12345678901234567.9"))
        // What prints is what was rounded.
        let rounded = CurrencyMath.rounded(decimal("17317.125"), currencyCode: "RWF")
        let printed = MoneyFormat.string(rounded, currencyCode: "RWF", locale: Locale(identifier: "en_US"))
        #expect(printed.contains("17,317") && !printed.contains("."))
    }

    // MARK: The table

    @Test func theTableConvertsThroughItsBase() {
        let rates = table
        #expect(rates.rate(from: "USD", to: "RWF") == 1400)
        #expect(rates.rate(from: "RWF", to: "USD") == 1 / Decimal(1400))
        #expect(rates.rate(from: "EUR", to: "JPY") == 150 / decimal("0.9"))
        #expect(rates.rate(from: "eur", to: "usd") == 1 / decimal("0.9"))
        #expect(rates.rate(from: "RWF", to: "RWF") == 1)
        #expect(rates.rate(from: "USD", to: "USD") == 1)
        #expect(rates.rate(from: "GBP", to: "USD") == nil)
        #expect(rates.rate(from: "USD", to: "GBP") == nil)
        #expect(rates.rate(from: "", to: "USD") == nil)
    }

    @Test func aZeroOrLowerCasedEntryIsHandled() {
        let rates = ExchangeRates(base: "usd", rates: ["ugx": 3700, "XAF": 0], date: day, fetchedAt: day)
        #expect(rates.rate(from: "USD", to: "UGX") == 3700)
        #expect(rates.rate(from: "XAF", to: "USD") == nil)
        #expect(rates.rate(from: "USD", to: "XAF") == nil)
    }

    @Test func theTableReadsTolerantlyAndRoundTrips() throws {
        let decoded = try DatabaseFile.makeDecoder().decode(ExchangeRates.self, from: Data("{}".utf8))
        #expect(decoded.base.isEmpty && decoded.rates.isEmpty && decoded.date == .distantPast)
        let data = try DatabaseFile.makeEncoder().encode(table)
        #expect(try DatabaseFile.makeDecoder().decode(ExchangeRates.self, from: data) == table)
    }

    // MARK: Converting

    @Test func rule1TheSameCurrencyIsTheAmountAsItIs() {
        let converter = CurrencyConverter(displayCurrency: "USD", rates: nil)
        #expect(converter.convert(decimal("1.23456"), from: "USD", to: "USD", saved: nil) == decimal("1.23456"))
        #expect(converter.convert(5, from: "rwf", to: "RWF", saved: saved("0.0007", "USD")) == 5)
    }

    @Test func rule2ASavedRateIntoTheTargetWins() {
        let converter = CurrencyConverter(displayCurrency: "RWF", rates: table)
        // Saved when 1 USD was 1385.37 RWF; today's 1400 is ignored.
        #expect(converter.convert(decimal("12.5"), from: "USD", to: "RWF", saved: saved("1385.37", "RWF")) == 17317)
        #expect(converter.convert(1000, from: "JPY", to: "USD", saved: saved("0.0066666", "usd")) == decimal("6.67"))
        // It works without a table too.
        let offline = CurrencyConverter(displayCurrency: "RWF", rates: nil)
        #expect(offline.convert(decimal("12.5"), from: "USD", to: "RWF", saved: saved("1385.37", "RWF")) == 17317)
    }

    @Test func rule3ASavedRateIntoAnotherCurrencyGoesOnThroughTheTable() {
        // Logged in EUR while the display currency was USD (1 EUR = 1.1 USD);
        // the display currency is RWF now.
        let converter = CurrencyConverter(displayCurrency: "RWF", rates: table)
        #expect(converter.convert(10, from: "EUR", to: "RWF", saved: saved("1.1", "USD")) == 15400)
        // The table lacks the saved rate's currency: today's table instead.
        let partial = ExchangeRates(base: "EUR", rates: ["RWF": 1500], date: day, fetchedAt: day)
        let fallback = CurrencyConverter(displayCurrency: "RWF", rates: partial)
        #expect(fallback.convert(10, from: "EUR", to: "RWF", saved: saved("1.1", "USD")) == 15000)
    }

    @Test func rule4WithoutASavedRateTodaysTableIsUsed() {
        let converter = CurrencyConverter(displayCurrency: "KWD", rates: table)
        #expect(converter.convert(100, from: "EUR", to: "KWD", saved: nil) == decimal("33.333"))
        #expect(converter.convert(1000, from: "RWF", to: "JPY", saved: nil) == 107)
        // A saved rate that is 0 or has no currency counts as none.
        #expect(converter.convert(100, from: "EUR", to: "KWD", saved: saved("0", "KWD")) == decimal("33.333"))
        #expect(converter.convert(100, from: "EUR", to: "KWD", saved: saved("2", "")) == decimal("33.333"))
    }

    @Test func anExactHalfThroughTheTableRoundsAwayFromZero() {
        // 1/1400 is a cut-short quotient; 7 RWF is exactly 0.005 USD.
        let converter = CurrencyConverter(displayCurrency: "USD", rates: table)
        #expect(converter.convert(7, from: "RWF", to: "USD", saved: nil) == decimal("0.01"))
        #expect(converter.convert(21, from: "RWF", to: "USD", saved: nil) == decimal("0.02"))
        #expect(converter.convert(175, from: "RWF", to: "USD", saved: nil) == decimal("0.13"))
        #expect(converter.convert(-7, from: "RWF", to: "USD", saved: nil) == decimal("-0.01"))
        #expect(converter.convert(7007, from: "RWF", to: "USD", saved: nil) == decimal("5.01"))
        // The same through a saved rate into another currency (rule 3).
        #expect(converter.convert(7, from: "BIF", to: "USD", saved: saved("1", "RWF")) == decimal("0.01"))
        #expect(table.convert(7, from: "RWF", to: "USD") == decimal("0.005"))
        #expect(table.convert(7, from: "GBP", to: "USD") == nil)
    }

    @Test func rule5WhatCannotBeConvertedIsNil() {
        let offline = CurrencyConverter(displayCurrency: "RWF", rates: nil)
        #expect(offline.convert(10, from: "USD", to: "RWF", saved: nil) == nil)
        #expect(offline.convert(10, from: "USD", to: "RWF", saved: saved("0", "RWF")) == nil)
        #expect(offline.convert(10, from: "EUR", to: "RWF", saved: saved("1.1", "USD")) == nil)
        let converter = CurrencyConverter(displayCurrency: "RWF", rates: table)
        #expect(converter.convert(10, from: "GBP", to: "RWF", saved: nil) == nil)
        #expect(converter.convert(10, from: "GBP", to: "RWF", saved: saved("2", "CHF")) == nil)
    }

    // MARK: Effective currencies

    @Test func nilCurrenciesFollowTheirWalletThenTheDisplayCurrency() {
        let dollars = PaymentMethod(name: "Dollars", symbol: "dollarsign", currencyCode: "USD")
        let cash = PaymentMethod(name: "Cash", symbol: "banknote.fill")
        let gone = UUID()
        let account = Account(name: "Personal", paymentMethods: [dollars, cash])
        let display = "RWF"

        #expect(account.effectiveCurrency(ofWallet: dollars.id, display: display) == "USD")
        #expect(account.effectiveCurrency(ofWallet: cash.id, display: display) == "RWF")
        #expect(account.effectiveCurrency(ofWallet: gone, display: display) == nil)
        #expect(account.effectiveCurrency(ofWallet: nil, display: display) == nil)

        #expect(account.effectiveCurrency(of: Expense(title: "a", amount: 1, paymentMethodID: dollars.id), display: display) == "USD")
        #expect(account.effectiveCurrency(of: Expense(title: "a", amount: 1, paymentMethodID: dollars.id, currencyCode: "EUR"), display: display) == "EUR")
        #expect(account.effectiveCurrency(of: Expense(title: "a", amount: 1, paymentMethodID: cash.id), display: display) == "RWF")
        #expect(account.effectiveCurrency(of: Expense(title: "a", amount: 1, paymentMethodID: gone), display: display) == "RWF")
        #expect(account.effectiveCurrency(of: Expense(title: "a", amount: 1), display: display) == "RWF")

        #expect(account.effectiveCurrency(of: Income(title: "a", amount: 1, walletID: dollars.id), display: display) == "USD")
        #expect(account.effectiveCurrency(of: Income(title: "a", amount: 1, currencyCode: "JPY", walletID: dollars.id), display: display) == "JPY")
        #expect(account.effectiveCurrency(of: Income(title: "a", amount: 1), display: display) == "RWF")

        let transfer = Transfer(fromWalletID: dollars.id, toWalletID: cash.id, amountOut: 10, amountIn: 14_000)
        #expect(account.effectiveCurrencyOut(of: transfer, display: display) == "USD")
        #expect(account.effectiveCurrencyIn(of: transfer, display: display) == "RWF")
        let pinned = Transfer(fromWalletID: nil, toWalletID: gone, amountOut: 10, currencyOut: "EUR", amountIn: 10)
        #expect(account.effectiveCurrencyOut(of: pinned, display: display) == "EUR")
        #expect(account.effectiveCurrencyIn(of: pinned, display: display) == "RWF")
    }
}
