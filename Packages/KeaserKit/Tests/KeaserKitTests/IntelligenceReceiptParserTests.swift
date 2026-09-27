import Foundation
import Testing
@testable import KeaserKit

/// The heuristics behind receipt scanning without Apple Intelligence.
struct IntelligenceReceiptParserTests {
    private let today = ReceiptSamples.today

    private func draft(_ text: String, monthFirst: Bool = true) -> ReceiptDraft {
        ReceiptParser.draft(from: text.split(separator: "\n").map(String.init), today: today, prefersMonthFirst: monthFirst)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> ReceiptDay {
        ReceiptDay(year: year, month: month, day: day)!
    }

    // MARK: Every sample

    @Test(arguments: ReceiptSamples.all.map(\.name))
    func readsTheSampleReceipt(_ name: String) throws {
        let sample = try #require(ReceiptSamples.named(name))
        // An American iPhone: "03/08/2026" is March 8 unless the receipt says otherwise.
        let draft = ReceiptParser.draft(from: sample.lines, today: today, prefersMonthFirst: true)
        #expect(draft == sample.expected)
    }

    @Test func onlyATotalOrADateMakesAReceipt() throws {
        #expect(try #require(ReceiptSamples.named("not-a-receipt")).expected.isReceipt == false)
        #expect(ReceiptDraft(total: 4).isReceipt)
        #expect(ReceiptDraft(day: today).isReceipt)
        #expect(!ReceiptDraft(merchant: "Meeting notes").isReceipt)
    }

    // MARK: Amounts

    @Test(arguments: [
        ("12.50", Decimal(string: "12.50")!, 2), ("12,50", Decimal(string: "12.5")!, 2),
        ("1,234.56", Decimal(string: "1234.56")!, 2), ("1.234,56", Decimal(string: "1234.56")!, 2),
        ("1'234.50", Decimal(string: "1234.5")!, 2), ("6,300", 6300, 0), ("10.000", 10000, 0),
        ("1,234,567", 1_234_567, 0), ("12.5", Decimal(string: "12.5")!, 1), ("0.500", Decimal(string: "0.5")!, 3), ("753", 753, 0),
    ] as [(String, Decimal, Int)])
    func readsNumbers(_ text: String, _ value: Decimal, _ fractionDigits: Int) throws {
        let number = try #require(ReceiptParser.number(text))
        #expect(number.0 == value)
        #expect(number.1 == fractionDigits)
    }

    @Test(arguments: ["12.345.67", "1,23,456", "12.3456", "1.23.4"])
    func rejectsWhatIsNotANumber(_ text: String) {
        #expect(ReceiptParser.number(text) == nil)
    }

    @Test func aDecimalPointReceiptKeepsThreeDecimals() {
        #expect(ReceiptParser.amounts(in: "PRICE/GAL $4.599", decimalSeparator: ".").map(\.value) == [Decimal(string: "4.599")!])
        #expect(ReceiptParser.amounts(in: "PRICE/GAL $4.599").map(\.value) == [4599])
        #expect(ReceiptParser.decimalSeparator(in: ["Total 12,50", "Card 12,50", "Tel 1.234"]) == ",")
        #expect(ReceiptParser.decimalSeparator(in: ["TOTAL RWF 6,300"]) == nil)
    }

    @Test func leavesOutTimesDatesPhoneNumbersAndPercentages() {
        #expect(ReceiptParser.amounts(in: "09/21/2026 14:32").isEmpty)
        #expect(ReceiptParser.amounts(in: "Datum: 21.09.2026").isEmpty)
        #expect(ReceiptParser.amounts(in: "Tel 020-1234567").isEmpty)
        #expect(ReceiptParser.amounts(in: "(415) 555-0123").map(\.value) == [415])
        #expect(ReceiptParser.amounts(in: "TVA 10% 1,32").map(\.value) == [Decimal(string: "1.32")!])
        #expect(ReceiptParser.amounts(in: "Service 12.5 % 4.44").map(\.value) == [Decimal(string: "4.44")!])
    }

    @Test func notesCurrenciesSignsAndUnits() throws {
        let euros = try #require(ReceiptParser.amounts(in: "Total TTC 14,50 €").first)
        #expect(euros.currencyCode == "EUR" && euros.hasCurrencyMark && euros.looksLikeMoney)

        let francs = try #require(ReceiptParser.amounts(in: "TOTAL RWF 6,300").first)
        #expect(francs.currencyCode == "RWF" && francs.value == 6300 && francs.looksLikeMoney)
        #expect(ReceiptParser.amounts(in: "3,000 Frw").first?.currencyCode == "RWF")
        #expect(ReceiptParser.amounts(in: "Total US$23.47").first?.currencyCode == "USD")

        let dollars = try #require(ReceiptParser.amounts(in: "Total $12.50").first)
        #expect(dollars.currencyCode == nil && dollars.hasCurrencyMark)

        #expect(ReceiptParser.amounts(in: "SAVINGS -2.00").first?.isNegative == true)
        #expect(ReceiptParser.amounts(in: "COUPON 2.00-").first?.isNegative == true)
        #expect(ReceiptParser.amounts(in: "Tomatoes 2kg").first?.hasUnit == true)
        #expect(ReceiptParser.amounts(in: "Eggs x12").first?.hasUnit == true)
        // A tax flag after a price is not a unit.
        #expect(ReceiptParser.amounts(in: "BANANAS 0.99F").first?.looksLikeMoney == true)
        // "TOP" is clothing, not the Tongan paʻanga.
        #expect(ReceiptParser.amounts(in: "TOP 19.99").first?.currencyCode == nil)
    }

    // MARK: Total

    @Test func takesTheTotalNotTheSubtotalTaxOrCash() {
        #expect(ReceiptParser.total(in: ["SUBTOTAL 23.45", "TAX 2.08", "TOTAL 25.53", "CASH 50.00", "CHANGE 24.47"]) == Decimal(string: "25.53"))
        #expect(ReceiptParser.total(in: ["Sub-Total 10.00", "Total Tax 0.80", "Total 10.80"]) == Decimal(string: "10.80"))
        #expect(ReceiptParser.total(in: ["Sous-total 12,00", "Total HT 10,00", "Net à payer 12,00"]) == 12)
        #expect(ReceiptParser.total(in: ["Zwischensumme 5,00", "Summe 5,95", "Gegeben 10,00", "Rückgeld 4,05"]) == Decimal(string: "5.95"))
    }

    @Test func aTotalWithTheTipIncludedWins() {
        #expect(ReceiptParser.total(in: ["Total 43.50", "Tip 8.00", "Total 51.50"]) == Decimal(string: "51.50"))
        #expect(ReceiptParser.total(in: ["Total 51.50", "Amount due 43.50"]) == Decimal(string: "43.50"))
        #expect(ReceiptParser.total(in: ["Total incl. VAT 24.00", "VAT 4.00"]) == 24)
    }

    @Test func findsAnAmountPrintedUnderItsLabel() {
        #expect(ReceiptParser.total(in: ["TOTAL", "$12.50", "VISA 12.50"]) == Decimal(string: "12.50"))
    }

    @Test func withoutATotalLineTakesTheLargestPrice() {
        #expect(ReceiptParser.total(in: ["Burrito 11.00", "Soda 2.50", "Card 13.50", "Cash 20.00"]) == Decimal(string: "13.50"))
        #expect(ReceiptParser.total(in: ["Onions 800", "3,000 Frw"]) == 3000)
        #expect(ReceiptParser.total(in: ["Hello", "Tel 0788 300 400"]) == nil)
    }

    // MARK: Day

    @Test func readsDatesInEveryCommonFormat() {
        let expected = day(2026, 9, 21)
        for text in [
            "2026-09-21", "2026/09/21", "09/21/2026", "9/21/26", "21.09.2026", "21-09-2026", "21 Sep 2026",
            "Sep 21, 2026", "September 21st, 2026", "21-SEP-2026", "21 septembre 2026", "21. September 2026",
            "Mon 21 Sep '26",
        ] {
            #expect(ReceiptParser.day(in: [text], today: today, monthFirst: true) == expected, "\(text)")
        }
    }

    @Test func anAmbiguousDateFollowsTheReceiptThenTheRegion() {
        #expect(ReceiptParser.day(in: ["03/04/2026"], today: today, monthFirst: true) == day(2026, 3, 4))
        #expect(ReceiptParser.day(in: ["03/04/2026"], today: today, monthFirst: false) == day(2026, 4, 3))
        // Euros and decimal commas mean day first, whatever the region.
        #expect(draft("Total 12,50 €\n03/04/2026").day == day(2026, 4, 3))
        #expect(draft("Totaal 8,43\n05-09-26").day == day(2026, 9, 5))
        // Dollars written "USD" mean month first, even on a British iPhone.
        #expect(draft("Total USD 12.50\n03/04/2026", monthFirst: false).day == day(2026, 3, 4))
    }

    @Test func skipsFutureReturnAndImpossibleDates() {
        #expect(ReceiptParser.day(in: ["Return by 10/27/2026", "09/21/2026"], today: today, monthFirst: true) == day(2026, 9, 21))
        #expect(ReceiptParser.day(in: ["12/25/2026"], today: today, monthFirst: true) == nil)
        #expect(ReceiptParser.day(in: ["02/30/2026"], today: today, monthFirst: true) == nil)
        #expect(ReceiptParser.day(in: ["Est. 01/01/1980"], today: today, monthFirst: true) == nil)
        // "MAYO 2.99" is mayonnaise.
        #expect(ReceiptParser.day(in: ["MAYO 2.99"], today: today, monthFirst: true) == nil)
        // Tomorrow is allowed: the shop may be a time zone ahead.
        #expect(ReceiptParser.day(in: ["09/28/2026"], today: today, monthFirst: true) == day(2026, 9, 28))
    }

    @Test func aDayKeepsTheTimeOfDayItIsPutOn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Kigali")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 14, minute: 5)))
        let date = try #require(day(2026, 9, 21).date(keepingTimeOf: now, calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            == DateComponents(year: 2026, month: 9, day: 21, hour: 14, minute: 5))
        #expect(ReceiptDay(date, calendar: calendar) == day(2026, 9, 21))
        #expect(day(2026, 12, 31).next == day(2027, 1, 1))
    }

    // MARK: Merchant

    @Test func tidiesANameIntoATitle() {
        #expect(ReceiptParser.cleanMerchant("TRADER JOE'S #552") == "Trader Joe's")
        #expect(ReceiptParser.cleanMerchant("STARBUCKS STORE 05123") == "Starbucks")
        #expect(ReceiptParser.cleanMerchant("*** 7-ELEVEN ***") == "7-Eleven")
        #expect(ReceiptParser.cleanMerchant("CVS PHARMACY") == "CVS Pharmacy")
        #expect(ReceiptParser.cleanMerchant("H&M") == "H&M")
        #expect(ReceiptParser.cleanMerchant("BANK OF AMERICA") == "Bank of America")
        #expect(ReceiptParser.cleanMerchant("Simba Supermarket Ltd.") == "Simba Supermarket")
        #expect(ReceiptParser.cleanMerchant("Acme S.A.") == "Acme")
        #expect(ReceiptParser.cleanMerchant("McDonald's") == "McDonald's")
        #expect(ReceiptParser.cleanMerchant("CAFÉ DE FLORE") == "Café de Flore")
        #expect(ReceiptParser.cleanMerchant("Store #12") == nil)
        #expect(ReceiptParser.cleanMerchant("RECEIPT") == nil)
        #expect(ReceiptParser.cleanMerchant("---") == nil)
    }

    @Test func skipsAddressesPhonesAndGreetingsForTheName() {
        #expect(ReceiptParser.merchant(in: ["1234 Market St", "Blue Bottle Coffee"]) == "Blue Bottle Coffee")
        #expect(ReceiptParser.merchant(in: ["Tel: 0788 300 400", "www.simba.rw", "Simba"]) == "Simba")
        #expect(ReceiptParser.merchant(in: ["CUSTOMER COPY", "Welcome to Whole Foods Market"]) == "Whole Foods Market")
        #expect(ReceiptParser.merchant(in: ["SALES RECEIPT", "KN 4 Ave", "Kigali Heights Cafe"]) == "Kigali Heights Cafe")
        #expect(ReceiptParser.merchant(in: ["Coffee 3.50", "Total 3.50", "Thank you for dining with Nando's!"]) == "Nando's")
        #expect(ReceiptParser.merchant(in: ["12.50", "09/21/2026"]) == nil)
    }

    // MARK: Currency

    @Test func namesACurrencyOnlyWhenTheReceiptDoes() {
        #expect(ReceiptParser.currencyCode(in: ["Total 12,50 €"]) == "EUR")
        #expect(ReceiptParser.currencyCode(in: ["SUMME EUR 6,02"]) == "EUR")
        #expect(ReceiptParser.currencyCode(in: ["Total £39.99"]) == "GBP")
        #expect(ReceiptParser.currencyCode(in: ["TOTAL KSh 1,250"]) == "KES")
        #expect(ReceiptParser.currencyCode(in: ["Total $12.50"]) == nil)
        #expect(ReceiptParser.currencyCode(in: ["Total ¥753"]) == nil)
        #expect(ReceiptParser.receiptShows(currency: "RWF", in: ["3,000 Frw"]))
        #expect(ReceiptParser.receiptShows(currency: "USD", in: ["Total US$ 4.00"]))
        #expect(!ReceiptParser.receiptShows(currency: "USD", in: ["Total $4.00"]))
    }

    @Test func aReceiptInAnotherCurrencyIsFlagged() {
        #expect(ReceiptDraft(total: 14.5, currencyCode: "EUR").isInOtherCurrency(than: "USD"))
        #expect(!ReceiptDraft(total: 14.5, currencyCode: "EUR").isInOtherCurrency(than: "EUR"))
        #expect(!ReceiptDraft(total: 12.5).isInOtherCurrency(than: "RWF"))
    }

    @Test func theRegionsDateOrder() {
        #expect(ReceiptParser.prefersMonthFirst(locale: Locale(identifier: "en_US")))
        #expect(!ReceiptParser.prefersMonthFirst(locale: Locale(identifier: "en_GB")))
        #expect(!ReceiptParser.prefersMonthFirst(locale: Locale(identifier: "fr_RW")))
    }
}

/// Putting text recognition's pieces back into the receipt's lines.
struct IntelligenceReceiptTextTests {
    @Test func joinsALabelAndItsAmountOnOneLine() {
        let fragments = [
            ReceiptText.Fragment("$12.50", x: 330, y: 318, width: 70, height: 22),
            ReceiptText.Fragment("TOTAL", x: 30, y: 324, width: 60, height: 22),
            ReceiptText.Fragment("TRADER JOE'S", x: 30, y: 896, width: 150, height: 24),
            ReceiptText.Fragment("SUBTOTAL", x: 30, y: 420, width: 100, height: 22),
            ReceiptText.Fragment("11.96", x: 330, y: 413, width: 60, height: 22),
        ]
        #expect(ReceiptText.lines(from: fragments) == ["TRADER JOE'S", "SUBTOTAL 11.96", "TOTAL $12.50"])
    }

    @Test func aPhotoTakenAtAnAngleKeepsItsLines() {
        // Every line climbs 0.12 points per point to the right, so the
        // amount at the right of a line sits as high as the next line's label.
        func tilted(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> ReceiptText.Fragment {
            let rise = width * 0.12
            let base = y + x * 0.12
            return ReceiptText.Fragment(
                text: text,
                topLeft: CGPoint(x: x, y: base + 20),
                topRight: CGPoint(x: x + width, y: base + rise + 20),
                bottomRight: CGPoint(x: x + width, y: base + rise),
                bottomLeft: CGPoint(x: x, y: base)
            )
        }
        let fragments = [
            tilted("SUBTOTAL", x: 20, y: 400, width: 120), tilted("11.96", x: 340, y: 400, width: 60),
            tilted("TOTAL", x: 20, y: 360, width: 80), tilted("$12.50", x: 340, y: 360, width: 70),
        ]
        #expect(ReceiptText.lines(from: fragments) == ["SUBTOTAL 11.96", "TOTAL $12.50"])
    }

    @Test func dropsBlankPieces() {
        #expect(ReceiptText.lines(from: [ReceiptText.Fragment("  ", x: 0, y: 0, width: 10, height: 10)]).isEmpty)
        #expect(ReceiptText.lines(from: []).isEmpty)
    }
}
