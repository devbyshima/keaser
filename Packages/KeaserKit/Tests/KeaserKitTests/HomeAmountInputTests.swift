import Foundation
import Testing
@testable import KeaserKit

struct HomeAmountInputTests {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    @Test func prefixesTheSymbolWhileTyping() {
        #expect(AmountInput.display("2", currencyCode: "USD", locale: us) == "$2")
        #expect(AmountInput.display("$20", currencyCode: "USD", locale: us) == "$20")
        #expect(AmountInput.display("$", currencyCode: "USD", locale: us) == "")
        #expect(AmountInput.display("", currencyCode: "USD", locale: us) == "")
    }

    @Test func keepsOneSeparatorAndTheCurrencysFractionDigits() {
        #expect(AmountInput.digits("$20.555", currencyCode: "USD", locale: us) == "20.55")
        #expect(AmountInput.digits("$1.2.3", currencyCode: "USD", locale: us) == "1.23")
        #expect(AmountInput.digits(".5", currencyCode: "USD", locale: us) == "0.5")
        #expect(AmountInput.digits("$1,234.5", currencyCode: "USD", locale: us) == "1234.5")
        #expect(AmountInput.digits("1500.5", currencyCode: "JPY", locale: us) == "15005")
        #expect(AmountInput.digits("12345678901234", currencyCode: "USD", locale: us) == "1234567890")
    }

    @Test func usesTheLocalesDecimalSeparator() {
        #expect(AmountInput.digits("16,99", currencyCode: "EUR", locale: de) == "16,99")
        #expect(AmountInput.digits("16.99", currencyCode: "EUR", locale: us) == "16.99")
        let typed = AmountInput.digits("16,9", currencyCode: "EUR", locale: de)
        #expect(MoneyFormat.parse(typed, locale: de) == Decimal(string: "16.9"))
    }

    @Test func editingTextRoundTripsThroughParse() {
        let text = AmountInput.editingText(for: 20, currencyCode: "USD", locale: us)
        #expect(text == "20.00")
        #expect(AmountInput.display(text, currencyCode: "USD", locale: us) == "$20.00")
        #expect(MoneyFormat.parse(text, locale: us) == 20)
        #expect(AmountInput.editingText(for: Decimal(string: "1234.5")!, currencyCode: "USD", locale: us) == "1234.50")
        #expect(AmountInput.editingText(for: 1500, currencyCode: "JPY", locale: us) == "1500")
        #expect(AmountInput.editingText(for: Decimal(string: "16.99")!, currencyCode: "EUR", locale: de) == "16,99")
    }

    /// Edit Expense fills its field from the stored amount, which can have
    /// more fraction digits than the currency (logged before a currency
    /// change, or from a Shortcut). Saving without touching the field keeps
    /// it.
    @Test(arguments: [("4.555", "USD"), ("20.5", "JPY"), ("1.2345", "KWD"), ("20", "USD")])
    func anUntouchedFieldSavesTheStoredAmount(_ raw: String, _ code: String) {
        let stored = Decimal(string: raw)!
        let field = AmountInput.field(for: stored, currencyCode: code, locale: us)
        #expect(AmountInput.amount(from: field, seed: stored, currencyCode: code, locale: us) == stored)
    }

    @Test func anEditedFieldSavesWhatItShows() {
        let stored = Decimal(string: "4.555")!
        #expect(AmountInput.field(for: stored, currencyCode: "USD", locale: us) == "$4.56")
        #expect(AmountInput.amount(from: "$4.5", seed: stored, currencyCode: "USD", locale: us) == Decimal(string: "4.5"))
        #expect(AmountInput.amount(from: "$12", seed: nil, currencyCode: "USD", locale: us) == 12)
        #expect(AmountInput.amount(from: "", seed: stored, currencyCode: "USD", locale: us) == nil)
    }
}
