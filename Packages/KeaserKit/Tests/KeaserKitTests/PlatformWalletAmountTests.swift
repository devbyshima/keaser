import Foundation
import Testing
@testable import KeaserKit

/// Log Wallet Transaction's amount text, read the same whatever number
/// style the phone uses.
struct PlatformWalletAmountTests {
    /// English (US) and (UK) write "1,234.56"; German and Kinyarwanda
    /// "1.234,56"; French "1 234,56" with a narrow no-break space.
    static let locales = ["en_US", "en_GB", "de_DE", "fr_FR", "rw_RW"]

    /// Text, the number it stands for and the marks around it, on every
    /// phone.
    static let readings: [(String, String, [String])] = [
        ("$4.50", "4.5", ["$"]),
        ("US$4.50", "4.5", ["US$"]),
        ("USD 4.50", "4.5", ["USD"]),
        ("4.50 USD", "4.5", ["USD"]),
        ("4.50", "4.5", []),
        ("  4.50\n", "4.5", []),
        ("$.50", "0.5", ["$"]),
        ("€12.40", "12.4", ["€"]),
        ("CA$4.50", "4.5", ["CA$"]),
        ("$1,299.00", "1299", ["$"]),
        ("€1,234.56", "1234.56", ["€"]),
        // Decimal commas.
        ("4,50 €", "4.5", ["€"]),
        ("12,40 $", "12.4", ["$"]),
        ("4,50 $US", "4.5", ["$US"]),
        ("1.234,56 €", "1234.56", ["€"]),
        ("1.299,00 $", "1299", ["$"]),
        ("EUR 1.234.567,89", "1234567.89", ["EUR"]),
        ("0,500 €", "0.5", ["€"]),
        // Spaces group thousands, before three digits only.
        ("1 234,56 €", "1234.56", ["€"]),
        ("1\u{202F}234,56 €", "1234.56", ["€"]),
        ("5 000 RWF", "5000", ["RWF"]),
        ("5\u{00A0}000 RWF", "5000", ["RWF"]),
        ("1 000 000 ₫", "1000000", ["₫"]),
        // Currencies with no minor unit group thousands whatever the phone.
        ("RWF 5,000", "5000", ["RWF"]),
        ("5.000 Frw", "5000", ["Frw"]),
        ("¥1,500", "1500", ["¥"]),
        ("¥1.500", "1500", ["¥"]),
        ("JPY 1.500", "1500", ["JPY"]),
        ("₩12,000", "12000", ["₩"]),
        // As do those with two.
        ("€1.234", "1234", ["€"]),
        ("$1,500", "1500", ["$"]),
        // Swiss and Indian grouping.
        ("CHF 1'234.50", "1234.5", ["CHF"]),
        ("CHF 1’234.50", "1234.5", ["CHF"]),
        ("Fr. 12.50", "12.5", ["Fr"]),
        ("CHF 12.–", "12", ["CHF"]),
        ("₹1,23,456.00", "123456", ["₹"]),
        ("Rs.50", "50", ["Rs"]),
    ]

    @Test(arguments: locales, readings)
    func readsTheSameOnEveryPhone(_ identifier: String, _ reading: (String, String, [String])) throws {
        let (text, value, marks) = reading
        let amount = try #require(WalletAmount.read(text, locale: Locale(identifier: identifier)))
        #expect(amount.value == Decimal(string: value))
        #expect(amount.marks == marks)
        #expect(amount.text == text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Negative, zero, and anything that is not exactly one number.
    static let refusals = [
        "", "   ", "free", "$", "$0.00", "0", "0,00 €", "-$4.50", "$-4.50", "4.50-", "−4,50 €", "–4,50 €",
        "1 2", "4 50", "1.2.3", "12 34 56", "1234 5678", "$4.50 or $5.00", "4.5000", "12,345,67",
        "٤٫٥٠",
        // More than nine digits before the point, the receipt reader's limit.
        "1,234,567,890.00",
    ]

    @Test(arguments: locales, refusals)
    func refusesWhatIsNotAPayment(_ identifier: String, _ text: String) {
        #expect(WalletAmount.read(text, locale: Locale(identifier: identifier)) == nil)
    }

    /// Only a currency that can have three decimals (KWD) leaves "1.500" to
    /// the phone: 1.5 where "." is the decimal point, 1,500 where it
    /// groups thousands.
    @Test func theLocaleSettlesThreeDecimalsOnlyWhereTheCurrencyHasThem() {
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        let fr = Locale(identifier: "fr_FR")
        #expect(WalletAmount.read("KWD 1.500", locale: us)?.value == Decimal(string: "1.5"))
        #expect(WalletAmount.read("KWD 1.500", locale: de)?.value == 1500)
        #expect(WalletAmount.read("1,500 KWD", locale: de)?.value == Decimal(string: "1.5"))
        #expect(WalletAmount.read("1,500 KWD", locale: fr)?.value == Decimal(string: "1.5"))
        #expect(WalletAmount.read("1,500 KWD", locale: us)?.value == 1500)
        // A number with no currency named is in `currencyCode`.
        #expect(WalletAmount.read("1,500", currencyCode: "KWD", locale: de)?.value == Decimal(string: "1.5"))
        #expect(WalletAmount.read("1,500", currencyCode: "USD", locale: de)?.value == 1500)
        #expect(WalletAmount.read("1.500", currencyCode: "JPY", locale: us)?.value == 1500)
        #expect(WalletAmount.read("1.500", currencyCode: "EUR", locale: us)?.value == 1500)
        // Marks that name no currency leave it to `currencyCode` too.
        #expect(WalletAmount.read("RF 5.000", currencyCode: "RWF", locale: us)?.value == 5000)
        // With neither, the phone decides.
        #expect(WalletAmount.read("1,500", locale: us)?.value == 1500)
        #expect(WalletAmount.read("1,500", locale: de)?.value == Decimal(string: "1.5"))
        #expect(WalletAmount.read("RF 5.000", locale: Locale(identifier: "rw_RW"))?.value == 5000)
        // A named currency wins over `currencyCode`.
        #expect(WalletAmount.read("€1.500", currencyCode: "KWD", locale: us)?.value == 1500)
    }

    /// One or two digits after a lone separator are decimals in every
    /// currency, even one with none.
    @Test func twoDigitsAfterASeparatorAreDecimals() {
        let de = Locale(identifier: "de_DE")
        #expect(WalletAmount.read("RWF 5,50", locale: de)?.value == Decimal(string: "5.5"))
        #expect(WalletAmount.read("¥12.5", locale: de)?.value == Decimal(string: "12.5"))
        #expect(WalletAmount.read("1,5", currencyCode: "USD", locale: Locale(identifier: "en_US"))?.value == Decimal(string: "1.5"))
    }

    /// Keaser records the number in its own currency, rounded to it.
    @Test func quickLogRoundsTheReadingToKeasersCurrency() {
        let de = Locale(identifier: "de_DE")
        #expect(QuickLog.amount(from: "$4.99", currencyCode: "JPY", locale: de) == 5)
        #expect(QuickLog.amount(from: "4,999 KWD", currencyCode: "KWD", locale: de) == Decimal(string: "4.999"))
        #expect(QuickLog.amount(from: "$0.001", currencyCode: "USD", locale: de) == nil)
        #expect(QuickLog.amount(from: "5,000", currencyCode: "RWF", locale: de) == 5000)
    }
}
