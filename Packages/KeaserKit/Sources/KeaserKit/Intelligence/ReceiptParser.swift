import Foundation

/// An amount of money printed on a receipt line.
public struct ReceiptAmount: Equatable, Sendable {
    public let value: Decimal
    /// Digits after the decimal separator: 2 in "12.50", 0 in "6,300".
    public let fractionDigits: Int
    /// The currency printed next to it, when it names one ("EUR", "€").
    public let currencyCode: String?
    /// A currency symbol or code next to it, even an ambiguous one ("$").
    public let hasCurrencyMark: Bool
    /// "-2.00" or "2.00-": a discount or a refund.
    public let isNegative: Bool
    /// Letters stuck to the number that are not a currency ("500g", "x2").
    public let hasUnit: Bool

    /// Reads as a price: two decimals, or a currency next to it.
    public var looksLikeMoney: Bool {
        !isNegative && !hasUnit && value > 0 && (fractionDigits == 2 || hasCurrencyMark)
    }
}

/// Reads a receipt's text without a language model: the heuristics behind
/// receipt scanning on iOS 18 to 25 and on iPhones without Apple
/// Intelligence, and the fallback for any detail the model gets wrong.
///
/// - Total: the amount on the line saying "Total" (or "Amount due",
///   "Summe", "Total TTC"...), never a subtotal, tax, cash, change, amount
///   paid, gross amount or suggested-tip line; the largest price on the
///   receipt when no line says so.
/// - Day: the first date printed that is not in the future, in any common
///   format; "03/04/2026" is read the way the receipt's currency or else
///   the person's region writes dates, unless that reading is tomorrow and
///   the other one is not.
/// - Merchant: the first line near the top that is not an address, phone
///   number, date, greeting or price, tidied up to be a title.
/// - Currency: a code or a symbol only one currency uses, next to an amount
///   (never letters after a count, such as "6 FT" or "5 KGS"); otherwise a
///   symbol several currencies share ("$", "¥"), kept on the draft.
public enum ReceiptParser {
    /// What the heuristics read, and whether the receipt itself settled the
    /// details a language model might read better.
    public struct Reading: Equatable, Sendable {
        public var draft: ReceiptDraft
        /// The total is on a line saying so ("Total", "Amount due"), rather
        /// than the largest price.
        public var totalIsLabelled: Bool
        /// The day can only be read one way, or the receipt's currency or
        /// decimal commas settled "03/04", rather than the person's region.
        public var dayIsSettled: Bool

        public init(draft: ReceiptDraft, totalIsLabelled: Bool = false, dayIsSettled: Bool = false) {
            self.draft = draft
            self.totalIsLabelled = totalIsLabelled && draft.total != nil
            self.dayIsSettled = dayIsSettled && draft.day != nil
        }
    }

    /// Everything the text shows. `today` rules out future dates;
    /// `prefersMonthFirst` settles "03/04" when the receipt does not.
    public static func draft(from lines: [String], today: ReceiptDay, prefersMonthFirst: Bool) -> ReceiptDraft {
        reading(from: lines, today: today, prefersMonthFirst: prefersMonthFirst).draft
    }

    /// `draft(from:today:prefersMonthFirst:)`, with how sure it is.
    public static func reading(from lines: [String], today: ReceiptDay, prefersMonthFirst: Bool) -> Reading {
        let lines = lines.map(oneLine).filter { !$0.isEmpty }
        let currency = currencyCode(in: lines)
        let symbol = currency == nil ? sharedSymbol(in: lines) : nil
        // Receipts with decimal commas come from places that write the day
        // first.
        let receiptOrder = currency.map { monthFirstCurrencies.contains($0) }
            ?? (decimalSeparator(in: lines) == "," ? false : nil)
        let labelled = labelledTotal(in: lines)
        let found = dayChoice(in: lines, today: today, monthFirst: receiptOrder ?? prefersMonthFirst)
        return Reading(
            draft: ReceiptDraft(
                merchant: merchant(in: lines),
                total: labelled ?? largestPrice(in: lines),
                day: found?.day,
                currencyCode: currency,
                currencySymbol: symbol
            ),
            totalIsLabelled: labelled != nil,
            dayIsSettled: found.map { !$0.isAmbiguous || receiptOrder != nil } ?? false
        )
    }

    /// Whether `locale` writes the month before the day ("9/21/2026").
    public static func prefersMonthFirst(locale: Locale = .current) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        guard let month = format.firstIndex(of: "M"), let day = format.firstIndex(of: "d") else { return true }
        return month < day
    }

    // MARK: Total

    /// The amount paid in the end: the one labelled as the total, else the
    /// largest price.
    public static func total(in lines: [String]) -> Decimal? {
        labelledTotal(in: lines) ?? largestPrice(in: lines)
    }

    /// The amount on the line naming the final total, if any does. Between
    /// lines of the same rank the larger amount wins: the total with the tip
    /// after the one without. A plain "Total" line with a percentage on it
    /// is a suggested tip ("18%: $7.78 (Total: $51.02)"), not the total.
    static func labelledTotal(in lines: [String]) -> Decimal? {
        let separator = decimalSeparator(in: lines)
        var best: (rank: Int, value: Decimal)?
        for (index, line) in lines.enumerated() {
            guard let rank = totalRank(words(line)), rank == 2 || !line.contains("%") else { continue }
            var found = amounts(in: line, decimalSeparator: separator).filter { !$0.isNegative && !$0.hasUnit && $0.value > 0 }
            // The label and the amount can come out on separate lines.
            if found.isEmpty, index + 1 < lines.count, isBareAmount(lines[index + 1]) {
                found = amounts(in: lines[index + 1], decimalSeparator: separator).filter { !$0.isNegative && !$0.hasUnit && $0.value > 0 }
            }
            guard let amount = found.last(where: { $0.fractionDigits > 0 || $0.hasCurrencyMark }) ?? found.last else { continue }
            if let current = best, current.rank > rank || (current.rank == rank && current.value >= amount.value) { continue }
            best = (rank, amount.value)
        }
        return best?.value
    }

    /// For a receipt no line of which says "total": the largest price,
    /// leaving out cash handed over, change and the like.
    static func largestPrice(in lines: [String]) -> Decimal? {
        let separator = decimalSeparator(in: lines)
        return lines
            .filter { Set(words($0)).isDisjoint(with: notPaidWords) }
            .flatMap { amounts(in: $0, decimalSeparator: separator) }
            .filter(\.looksLikeMoney)
            .map(\.value)
            .max()
    }

    /// 2 for a line naming the final amount ("Amount due", "Total TTC"), 1
    /// for a plain "Total", nil for anything else (including "Subtotal",
    /// "Total tax", "Total savings").
    static func totalRank(_ words: [String]) -> Int? {
        let joined = " " + words.joined(separator: " ") + " "
        if finalTotalPhrases.contains(where: { joined.contains(" \($0) ") }) { return 2 }
        let set = Set(words)
        guard !set.isDisjoint(with: totalWords), set.isDisjoint(with: notTotalWords) else { return nil }
        return 1
    }

    /// A line that is only an amount, give or take a currency.
    private static func isBareAmount(_ line: String) -> Bool {
        line.filter(\.isLetter).count <= 3 && !amounts(in: line).isEmpty
    }

    static let finalTotalPhrases = [
        "grand total", "total due", "amount due", "balance due", "total to pay", "total payable",
        "amount payable", "total paid", "total amount", "total ttc", "montant ttc", "net a payer",
        "a payer", "zu zahlen", "gesamtbetrag", "endbetrag", "total a pagar", "importe total",
        "total general", "te betalen", "totale complessivo", "totale da pagare", "total incl",
        "total inkl", "total including", "total inc",
    ]

    static let totalWords: Set<String> = [
        "total", "totaal", "totale", "summe", "gesamt", "montant", "importe", "sum", "amount", "betrag",
        "jumla", "igiteranyo", "合計", "合计", "總計", "总计", "합계",
    ]

    /// Words on a line that make its amount something other than the total.
    static let notTotalWords: Set<String> = Set([
        "sub", "subtotal", "subtot", "sous", "zwischensumme", "subtotale", "tax", "taxes", "vat", "tva",
        "mwst", "ust", "iva", "gst", "hst", "pst", "btw", "ht", "net", "netto", "excl", "exkl", "hors",
        "saving", "savings", "saved", "save", "discount", "discounts", "rabatt", "remise", "descuento",
        "sconto", "coupon", "coupons", "items", "item", "articles", "article", "artikel", "qty",
        "quantity", "count", "points", "point", "tip", "tips", "gratuity", "pourboire", "trinkgeld",
        "propina", "mancia", "小計", "小计", "소계",
        // "Amount paid" is often the cash handed over; "Total paid" still
        // names the total (a final phrase, matched first).
        "paid",
    ]).union(notPaidWords)

    /// Words on a line whose amount is not what was paid.
    static let notPaidWords: Set<String> = [
        "cash", "bar", "especes", "espece", "efectivo", "contanti", "tendered", "tender", "received",
        "given", "gegeben", "change", "rendu", "monnaie", "ruckgeld", "wechselgeld", "cambio", "resto",
        "deposit", "pfand", "saving", "savings", "saved", "discount", "points", "balance", "お預り",
        "お預かり", "預り", "お釣り", "釣銭",
        // Before a discount.
        "gross", "brutto",
    ]

    // MARK: Amounts

    /// The receipt's decimal separator: whichever of "." and "," more of its
    /// prices end with two digits after. Nil when none do.
    public static func decimalSeparator(in lines: [String]) -> Character? {
        var points = 0
        var commas = 0
        for line in lines {
            let characters = Array(line)
            for index in characters.indices where index >= 1 && index + 2 < characters.count {
                guard characters[index - 1].isASCIIDigit, characters[index + 1].isASCIIDigit, characters[index + 2].isASCIIDigit,
                      index + 3 == characters.count || !characters[index + 3].isASCIIDigit
                else { continue }
                if characters[index] == "." { points += 1 }
                if characters[index] == "," { commas += 1 }
            }
        }
        if points == 0, commas == 0 { return nil }
        return commas > points ? "," : "."
    }

    /// Every amount on `line`, left to right. Times, dates, percentages,
    /// phone numbers and numbers glued to other text are left out. With the
    /// receipt's `decimalSeparator`, "4.599" on a receipt that writes
    /// "12.50" is 4.599, not 4,599.
    public static func amounts(in line: String, decimalSeparator: Character? = nil) -> [ReceiptAmount] {
        let characters = Array(line)
        var found: [ReceiptAmount] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isASCIIDigit else {
                index += 1
                continue
            }
            let start = index
            var end = index + 1
            while end < characters.count {
                if characters[end].isASCIIDigit {
                    end += 1
                } else if numberSeparators.contains(characters[end]), end + 1 < characters.count, characters[end + 1].isASCIIDigit {
                    end += 2
                } else if let digits = spacedGroup(in: characters, at: end) {
                    // Text recognition sometimes reads "6,300" as "6, 300".
                    end += 2 + digits
                } else {
                    break
                }
            }
            index = end
            if let amount = amount(in: characters, from: start, to: end, decimalSeparator: decimalSeparator) { found.append(amount) }
        }
        return found
    }

    private static func amount(in characters: [Character], from start: Int, to end: Int, decimalSeparator: Character?) -> ReceiptAmount? {
        let before = start > 0 ? characters[start - 1] : nil
        let after = end < characters.count ? characters[end] : nil
        // Times ("14:32") and dates ("09/21").
        if let before, before == ":" || before == "/" { return nil }
        if let after, after == ":" || after == "/" { return nil }
        // Hyphenated numbers: dates ("21-09-2026") and phone numbers.
        if let before, isHyphen(before), start >= 2, characters[start - 2].isASCIIDigit { return nil }
        if let after, isHyphen(after), end + 1 < characters.count, characters[end + 1].isASCIIDigit { return nil }
        // Percentages ("10%", "10 %").
        if let next = nextNonSpace(characters, from: end), next == "%" { return nil }
        let text = String(characters[start..<end].filter { $0 != " " })
        guard let (value, fractionDigits) = number(text, decimalSeparator: decimalSeparator) else { return nil }

        let leading = mark(in: characters, before: start)
        let trailing = mark(in: characters, after: end)
        var leadingCurrency = currency(forMark: leading.text)
        var trailingCurrency = currency(forMark: trailing.text)
        // Letters after a count are its unit, even where they spell a
        // currency: "6 FT HDMI CABLE 12.99" (feet, not forints) and
        // "RICE 5 KGS 250.00" (kilograms, not Kyrgyz som, for either
        // number). A currency after a whole number ends the line: "3,000 Frw".
        let isCount = text.allSatisfy(\.isASCIIDigit)
        if isCount, trailingCurrency.isMark, hasText(in: characters, from: trailing.start + trailing.text.count) {
            trailingCurrency = (nil, false)
        }
        if leadingCurrency.isMark, followsCount(characters, before: leading.start) {
            leadingCurrency = (nil, false)
        }

        var hasUnit = false
        if leading.isAttached, !leading.text.isEmpty, !leadingCurrency.isMark { hasUnit = true }
        if trailing.isAttached, !trailing.text.isEmpty, !trailingCurrency.isMark {
            // A tax flag after a price ("4.49F") is not a unit.
            if !(trailing.text.count == 1 && fractionDigits == 2) { hasUnit = true }
        }

        var negative = false
        let signIndex = leading.text.isEmpty ? start - 1 : leading.start - 1
        if let sign = character(in: characters, at: signIndex, skippingOneSpace: true), isHyphen(sign) { negative = true }
        if let after, isHyphen(after) { negative = true }

        return ReceiptAmount(
            value: value,
            fractionDigits: fractionDigits,
            currencyCode: leadingCurrency.code ?? trailingCurrency.code,
            hasCurrencyMark: leadingCurrency.isMark || trailingCurrency.isMark,
            isNegative: negative,
            hasUnit: hasUnit
        )
    }

    /// "1,234.56", "1.234,56", "12,50", "6,300", "1'234.50": the value and
    /// its number of decimals. A single separator followed by three digits
    /// groups thousands ("6,300") unless it is the receipt's
    /// `decimalSeparator`; followed by one or two, it is the decimal point.
    static func number(_ text: String, decimalSeparator: Character? = nil) -> (Decimal, Int)? {
        let characters = Array(text)
        let separators = characters.indices.filter { !characters[$0].isASCIIDigit }
        var decimal: Int?
        let kinds = Set(separators.map { characters[$0] })
        if kinds.count > 1 {
            guard let last = separators.last, characters[last] == "." || characters[last] == ",",
                  separators.filter({ characters[$0] == characters[last] }).count == 1
            else { return nil }
            decimal = last
        } else if let only = separators.first, kinds.first != "'", separators.count == 1 {
            let digitsAfter = characters.count - only - 1
            let integer = String(characters[..<only])
            if digitsAfter == 3, integer != "0", characters[only] != decimalSeparator {
                decimal = nil
            } else if digitsAfter <= 3 {
                decimal = only
            } else {
                return nil
            }
        }

        // Thousands groups: one to three digits, then groups of three.
        let grouping = separators.filter { $0 != decimal }
        let integerEnd = decimal ?? characters.count
        if let first = grouping.first {
            guard (1...3).contains(first) else { return nil }
            for (index, position) in grouping.enumerated() {
                let next = index + 1 < grouping.count ? grouping[index + 1] : integerEnd
                guard next - position - 1 == 3 else { return nil }
            }
        }
        let integerDigits = String(characters[..<integerEnd].filter(\.isASCIIDigit))
        let fraction = decimal.map { String(characters[($0 + 1)...]) } ?? ""
        guard !integerDigits.isEmpty, integerDigits.count <= 9, fraction.count <= 3 else { return nil }
        let literal = fraction.isEmpty ? integerDigits : integerDigits + "." + fraction
        guard let value = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return (value, fraction.count)
    }

    private static let numberSeparators: Set<Character> = [".", ",", "'"]

    /// The length of a group of three digits after a separator and a space,
    /// where text recognition split "6,300"; nil when there is none at
    /// `index`. Two digits ("4, 12") are more likely a list than a price.
    private static func spacedGroup(in characters: [Character], at index: Int) -> Int? {
        guard index + 3 < characters.count, characters[index] == "," || characters[index] == ".", characters[index + 1] == " " else { return nil }
        var digits = 0
        while index + 2 + digits < characters.count, characters[index + 2 + digits].isASCIIDigit { digits += 1 }
        return digits == 3 ? digits : nil
    }

    /// Whether a letter or a digit comes at or after `index`.
    private static func hasText(in characters: [Character], from index: Int) -> Bool {
        characters[min(index, characters.count)...].contains { $0.isLetter || $0.isNumber }
    }

    /// Whether a whole number ends just before `index`, give or take a
    /// space: "5 " in "RICE 5 KGS 250.00".
    private static func followsCount(_ characters: [Character], before index: Int) -> Bool {
        var end = index
        if end > 0, characters[end - 1] == " " { end -= 1 }
        var start = end
        while start > 0, characters[start - 1].isASCIIDigit { start -= 1 }
        return start < end && (start == 0 || characters[start - 1] == " ")
    }

    private static func isHyphen(_ character: Character) -> Bool {
        character == "-" || character == "\u{2212}" || character == "\u{2013}"
    }

    private static func nextNonSpace(_ characters: [Character], from index: Int) -> Character? {
        var index = index
        while index < characters.count, characters[index] == " " { index += 1 }
        return index < characters.count ? characters[index] : nil
    }

    private static func character(in characters: [Character], at index: Int, skippingOneSpace: Bool) -> Character? {
        guard index >= 0, index < characters.count else { return nil }
        if skippingOneSpace, characters[index] == " " {
            return index > 0 ? characters[index - 1] : nil
        }
        return characters[index]
    }

    /// The letters or currency symbols right before or after a number (one
    /// space allowed): "EUR", "US$", "€", "g".
    private struct Mark {
        var text = ""
        var start = 0
        var isAttached = false
    }

    private static func mark(in characters: [Character], before index: Int) -> Mark {
        var end = index
        var attached = true
        if end > 0, characters[end - 1] == " " {
            end -= 1
            attached = false
        }
        var start = end
        while start > 0, isMarkCharacter(characters[start - 1]), end - start < 5 { start -= 1 }
        return Mark(text: String(characters[start..<end]), start: start, isAttached: attached)
    }

    private static func mark(in characters: [Character], after index: Int) -> Mark {
        var start = index
        var attached = true
        if start < characters.count, characters[start] == " " {
            start += 1
            attached = false
        }
        var end = start
        while end < characters.count, isMarkCharacter(characters[end]), end - start < 5 { end += 1 }
        return Mark(text: String(characters[start..<end]), start: start, isAttached: attached)
    }

    private static func isMarkCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isCurrencySymbol
    }

    // MARK: Currency

    /// The currency the receipt names most often next to its amounts.
    public static func currencyCode(in lines: [String]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        func count(_ code: String) {
            if counts[code] == nil { order.append(code) }
            counts[code, default: 0] += 1
        }
        for line in lines {
            for amount in amounts(in: line) {
                if let code = amount.currencyCode { count(code) }
            }
            // A symbol only one currency uses counts anywhere ("€" heading
            // a column).
            for character in line {
                if let code = symbolCodes[String(character)] { count(code) }
            }
        }
        return order.max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// The symbol several currencies share ("$", "¥") printed next to the
    /// receipt's amounts, for a receipt that names no currency. "￥" is
    /// read as "¥".
    public static func sharedSymbol(in lines: [String]) -> String? {
        var counts: [String: Int] = [:]
        for line in lines where amounts(in: line).contains(where: { $0.hasCurrencyMark && $0.currencyCode == nil }) {
            for character in line {
                let text = String(character) == "￥" ? "¥" : String(character)
                if ambiguousSymbols.contains(text) { counts[text, default: 0] += 1 }
            }
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// The currency a mark names, and whether it is a currency mark at all
    /// ("$" is one, but names no single currency).
    static func currency(forMark mark: String) -> (code: String?, isMark: Bool) {
        guard !mark.isEmpty else { return (nil, false) }
        if let code = symbolCodes[mark] { return (code, true) }
        if ambiguousSymbols.contains(mark) { return (nil, true) }
        let upper = mark.uppercased()
        if let code = prefixedSymbols[upper] ?? currencyAliases[upper] { return (code, true) }
        if upper.count == 3, upper.allSatisfy(\.isLetter), isoCurrencyCodes.contains(upper), !codesThatAreWords.contains(upper) {
            return (upper, true)
        }
        return (nil, false)
    }

    /// Whether `code` is printed on the receipt, as a code or as a symbol
    /// only that currency uses.
    public static func receiptShows(currency code: String, in lines: [String]) -> Bool {
        let code = code.uppercased()
        for line in lines {
            for character in line where symbolCodes[String(character)] == code { return true }
            let tokens = line.uppercased().split { !$0.isLetter && $0 != "$" }
            for token in tokens {
                let text = String(token)
                if text == code || prefixedSymbols[text] == code || currencyAliases[text] == code { return true }
            }
        }
        return false
    }

    /// Currencies whose receipts write "03/04/2026" month first.
    static let monthFirstCurrencies: Set<String> = ["USD", "PHP"]

    static let symbolCodes: [String: String] = [
        "€": "EUR", "£": "GBP", "₹": "INR", "₩": "KRW", "₱": "PHP", "₦": "NGN", "₺": "TRY", "₫": "VND",
        "₪": "ILS", "฿": "THB", "₴": "UAH", "₽": "RUB", "₵": "GHS", "₸": "KZT", "₼": "AZN", "₾": "GEL",
        "₡": "CRC", "₲": "PYG",
    ]

    /// Symbols several currencies share.
    static let ambiguousSymbols: Set<String> = ["$", "¥", "￥"]

    static let prefixedSymbols: [String: String] = [
        "US$": "USD", "CA$": "CAD", "C$": "CAD", "A$": "AUD", "AU$": "AUD", "NZ$": "NZD", "HK$": "HKD",
        "S$": "SGD", "R$": "BRL", "MX$": "MXN", "NT$": "TWD",
    ]

    /// How receipts write some currencies besides their ISO code.
    static let currencyAliases: [String: String] = [
        "FRW": "RWF", "RWF": "RWF", "KSH": "KES", "USH": "UGX", "TSH": "TZS", "ZŁ": "PLN", "KČ": "CZK",
        "FT": "HUF", "LEI": "RON", "RM": "MYR",
    ]

    /// Currency codes that are also words on receipts ("TOP 19.99").
    static let codesThatAreWords: Set<String> = [
        "ALL", "AMD", "BAM", "BOB", "CUP", "GEL", "MAD", "MOP", "PEN", "SOS", "TOP", "TRY", "WST",
    ]

    static let isoCurrencyCodes = Set(Locale.commonISOCurrencyCodes.map { $0.uppercased() })

    // MARK: Day

    /// The first day printed that is a real date, not in the future and
    /// not decades old. Return-by and expiry dates are skipped.
    public static func day(in lines: [String], today: ReceiptDay, monthFirst: Bool) -> ReceiptDay? {
        dayChoice(in: lines, today: today, monthFirst: monthFirst)?.day
    }

    /// `day(in:today:monthFirst:)`, and whether the date it came from could
    /// be read another way. Tomorrow is only taken when it is the one
    /// reading: "03/04" read on April 2 is March 4, even where the day
    /// comes first.
    static func dayChoice(in lines: [String], today: ReceiptDay, monthFirst: Bool) -> (day: ReceiptDay, isAmbiguous: Bool)? {
        for line in lines {
            guard Set(words(line)).isDisjoint(with: notPurchaseDayWords) else { continue }
            for candidates in days(in: line, monthFirst: monthFirst) {
                let plausible = candidates.filter { isPlausible($0, today: today) }
                if let day = plausible.first(where: { $0 <= today }) ?? plausible.first {
                    return (day, plausible.count > 1)
                }
            }
        }
        return nil
    }

    /// Whether `day` could be when a receipt was printed: not after
    /// tomorrow (the shop may be a time zone ahead) and not decades ago.
    public static func isPlausible(_ day: ReceiptDay, today: ReceiptDay) -> Bool {
        day <= today.next && day.year >= today.year - 20
    }

    /// Each date written on `line`, as the days it could mean, the more
    /// likely first: "03/04/2026" is March 4 or April 3.
    public static func days(in line: String, monthFirst: Bool) -> [[ReceiptDay]] {
        let text = folded(line)
        let range = NSRange(text.startIndex..., in: text)
        var found: [(location: Int, days: [ReceiptDay])] = []
        var taken: [NSRange] = []

        func add(_ match: NSTextCheckingResult, _ days: [ReceiptDay]) {
            guard !days.isEmpty, !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            taken.append(match.range)
            found.append((match.range.location, days))
        }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }

        for match in isoDate.matches(in: text, range: range) + yearMonthDayDate.matches(in: text, range: range) {
            let day = ReceiptDay(year: Int(group(match, 1)) ?? 0, month: Int(group(match, 2)) ?? 0, day: Int(group(match, 3)) ?? 0)
            add(match, day.map { [$0] } ?? [])
        }
        for match in numericDate.matches(in: text, range: range) {
            let first = Int(group(match, 1)) ?? 0
            let second = Int(group(match, 3)) ?? 0
            let year = fullYear(group(match, 4))
            let monthDay = ReceiptDay(year: year, month: first, day: second)
            let dayMonth = ReceiptDay(year: year, month: second, day: first)
            let ordered = monthFirst ? [monthDay, dayMonth] : [dayMonth, monthDay]
            var days: [ReceiptDay] = []
            for day in ordered.compactMap({ $0 }) where !days.contains(day) { days.append(day) }
            add(match, days)
        }
        for match in dayNameDate.matches(in: text, range: range) {
            guard let month = month(named: group(match, 2)) else { continue }
            let day = ReceiptDay(year: fullYear(group(match, 3)), month: month, day: Int(group(match, 1)) ?? 0)
            add(match, day.map { [$0] } ?? [])
        }
        for match in nameDayDate.matches(in: text, range: range) {
            guard let month = month(named: group(match, 1)) else { continue }
            let day = ReceiptDay(year: fullYear(group(match, 3)), month: month, day: Int(group(match, 2)) ?? 0)
            add(match, day.map { [$0] } ?? [])
        }
        return found.sorted { $0.location < $1.location }.map(\.days)
    }

    private static func fullYear(_ text: String) -> Int {
        let digits = text.filter(\.isASCIIDigit)
        let year = Int(digits) ?? 0
        return digits.count == 2 ? 2000 + year : year
    }

    static func month(named word: String) -> Int? {
        monthNames[word.trimmingCharacters(in: CharacterSet(charactersIn: "."))]
    }

    private static let isoDate = try! NSRegularExpression(pattern: #"(?<!\d)((?:19|20)\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?![\d])"#)
    /// "2026年9月20日".
    private static let yearMonthDayDate = try! NSRegularExpression(pattern: #"((?:19|20)\d{2})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#)
    private static let numericDate = try! NSRegularExpression(pattern: #"(?<![\d.,/-])(\d{1,2})([/.\-])(\d{1,2})\2((?:19|20)\d{2}|\d{2})(?![\d:])"#)
    private static let dayNameDate = try! NSRegularExpression(pattern: #"(?<![\d])(\d{1,2})(?:st|nd|rd|th|er)?[\s.\-/]*([a-z]{3,9}\.?)[\s.\-/,]*((?:19|20)\d{2}|'?\d{2})(?![\d:])"#)
    private static let nameDayDate = try! NSRegularExpression(pattern: #"(?<![a-z])([a-z]{3,9}\.?)[\s.\-]*(\d{1,2})(?:st|nd|rd|th)?[\s.,\-]*((?:19|20)\d{2}|'\d{2})(?![\d:])"#)

    /// Month names and abbreviations in English, French, German, Spanish
    /// and Italian, without accents.
    static let monthNames: [String: Int] = {
        let names: [[String]] = [
            ["jan", "january", "janv", "janvier", "januar", "ene", "enero", "gen", "gennaio"],
            ["feb", "february", "fev", "fevr", "fevrier", "februar", "febrero", "febbraio"],
            ["mar", "march", "mars", "marz", "maerz", "marzo"],
            ["apr", "april", "avr", "avril", "abr", "abril", "aprile"],
            ["may", "mai", "mayo", "mag", "maggio"],
            ["jun", "june", "juin", "juni", "junio", "giu", "giugno"],
            ["jul", "july", "juil", "juillet", "juli", "julio", "lug", "luglio"],
            ["aug", "august", "aout", "ago", "agosto"],
            ["sep", "sept", "september", "septembre", "septiembre", "setiembre", "set", "settembre"],
            ["oct", "october", "octobre", "okt", "oktober", "octubre", "ott", "ottobre"],
            ["nov", "november", "novembre", "noviembre"],
            ["dec", "december", "decembre", "dez", "dezember", "dic", "diciembre", "dicembre"],
        ]
        var table: [String: Int] = [:]
        for (index, forms) in names.enumerated() {
            for form in forms { table[form] = index + 1 }
        }
        return table
    }()

    /// Words on a line whose date is not the day of the purchase.
    static let notPurchaseDayWords: Set<String> = [
        "return", "returns", "exp", "expires", "expiry", "expiration", "valid", "until", "thru",
        "before", "since", "retour", "echange", "umtausch", "bis",
    ]

    // MARK: Merchant

    /// The shop's name: the first line near the top that could be one, or
    /// "Welcome to X" / "Thank you for shopping at X".
    public static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(8) {
            if let name = captured(welcome, in: line).flatMap(cleanMerchant) { return name }
            let line = withoutStoreNumber(line, keepingTrailingNumber: true)
            guard isMerchantCandidate(line), let name = cleanMerchant(line) else { continue }
            return name
        }
        for line in lines {
            if let name = captured(thanks, in: line).flatMap(cleanMerchant) { return name }
        }
        return nil
    }

    /// Tidies a printed name into a title: store numbers, legal suffixes
    /// and decoration go, and an all-capitals name is set in title case
    /// ("TRADER JOE'S #552" is "Trader Joe's"). Nil when nothing name-like
    /// is left.
    public static func cleanMerchant(_ text: String) -> String? {
        var name = withoutStoreNumber(text).trimmingCharacters(in: decoration)
        var words = name.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, legalSuffixes.contains(folded(last).filter { $0.isLetter }) {
            words.removeLast()
            while let trailing = words.last, trailing == "&" || trailing == "," || trailing == "-" { words.removeLast() }
        }
        name = words.joined(separator: " ").trimmingCharacters(in: decoration)
        if name.count > maximumMerchantLength {
            name = String(name.prefix(maximumMerchantLength))
            if let space = name.lastIndex(of: " ") { name = String(name[..<space]) }
        }
        name = titleCased(name)
        let letters = name.filter(\.isLetter).count
        guard letters >= 2, letters * 2 >= name.filter({ !$0.isWhitespace }).count else { return nil }
        guard !genericNames.contains(folded(name)) else { return nil }
        return name
    }

    /// "Walgreens #1234" and "Starbucks Store 05123" without the number.
    /// A bare number at the end ("Starbucks 05123") goes too, unless
    /// `keepingTrailingNumber`: before a line is known to be a name, such a
    /// number is more likely a postal code.
    static func withoutStoreNumber(_ text: String, keepingTrailingNumber: Bool = false) -> String {
        var name = oneLine(text)
        for pattern in keepingTrailingNumber ? Array(storeNumberPatterns.dropLast()) : storeNumberPatterns {
            name = pattern.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: " ")
        }
        return oneLine(name)
    }

    /// Stars, rules and punctuation printed around a name.
    private static let decoration = CharacterSet(charactersIn: "*#=-_~.:,;|!<>+/\\\"`").union(.whitespaces)

    /// Longer than this, a "name" is a sentence.
    static let maximumMerchantLength = 40

    static func isMerchantCandidate(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        let digits = line.filter(\.isASCIIDigit).count
        guard letters >= 2, digits < letters, digits < 7 else { return false }
        let lower = folded(line)
        if webMarks.contains(where: lower.contains) { return false }
        if amounts(in: line).contains(where: \.looksLikeMoney) { return false }
        if !days(in: line, monthFirst: true).isEmpty { return false }
        if lower.range(of: #"\d:\d"#, options: .regularExpression) != nil { return false }
        // Postal codes and store numbers.
        if lower.range(of: #"(?<![\d])\d{4,6}(?![\d])"#, options: .regularExpression) != nil { return false }
        // "Mountain View, CA".
        if line.range(of: #",\s*[A-Z]{2}(\s|$)"#, options: .regularExpression) != nil { return false }
        let set = Set(words(line))
        if !set.isDisjoint(with: notMerchantWords) { return false }
        if digits > 0, !set.isDisjoint(with: streetWords) { return false }
        return true
    }

    private static func captured(_ expression: NSRegularExpression, in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let captured = Range(match.range(at: 1), in: line)
        else { return nil }
        let name = String(line[captured]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static let welcome = try! NSRegularExpression(pattern: #"(?i)\b(?:welcome to|bienvenue (?:chez|a|à)|willkommen (?:bei|im)|bienvenido a)\s+(.+)$"#)
    private static let thanks = try! NSRegularExpression(pattern: #"(?i)\b(?:shopping|dining|visiting|eating|choosing|staying)\s+(?:at|with)\s+([^.!]+)"#)
    private static let storeNumberPatterns = [
        try! NSRegularExpression(pattern: #"(?i)\b(?:store|shop|branch|filiale|magasin|unit|no\.?|nr\.?)\s*#?\s*\d+\b"#),
        try! NSRegularExpression(pattern: #"#\s*\d+"#),
        try! NSRegularExpression(pattern: #"\s\d{3,}\s*$"#),
    ]

    static let legalSuffixes: Set<String> = [
        "ltd", "limited", "llc", "inc", "incorporated", "corp", "corporation", "gmbh", "ag", "kg", "sarl",
        "sas", "sa", "srl", "bv", "nv", "plc", "pty", "pvt", "oy", "ab", "llp", "lp",
    ]

    static let genericNames: Set<String> = [
        "store", "shop", "receipt", "invoice", "total", "customer", "cashier", "merchant", "copy", "sale",
        "sales", "welcome", "thank you", "thanks", "none", "unknown", "n/a", "null", "cash", "card", "visa",
        "mastercard", "customer copy", "merchant copy", "tax invoice", "sales receipt",
    ]

    static let webMarks = ["www.", "http", "@", ".com", ".net", ".org", ".co.", ".fr", ".de", ".rw", ".uk"]

    static let notMerchantWords: Set<String> = [
        "receipt", "receipts", "invoice", "facture", "rechnung", "recu", "ticket", "kassenbon", "quittung",
        "factura", "ricevuta", "scontrino", "bienvenue", "willkommen", "bienvenido", "benvenuti", "thank",
        "thanks", "merci", "danke", "gracias", "grazie", "murakoze", "tel", "tél", "telephone", "phone",
        "fax", "tin", "vat", "tva", "siret", "siren", "nif", "cif", "ust", "steuernr", "cashier", "server",
        "table", "order", "date", "time", "customer", "copy", "duplicate", "terminal", "register", "trans",
        "transaction", "operator", "clerk", "guest", "guests", "chk", "sale", "hours", "open", "opening",
        "welcome",
    ]

    static let streetWords: Set<String> = [
        "st", "street", "str", "strasse", "ave", "avenue", "av", "rd", "road", "blvd", "boulevard", "bd",
        "ln", "lane", "dr", "drive", "way", "hwy", "highway", "pkwy", "parkway", "ct", "court", "pl",
        "place", "sq", "square", "suite", "ste", "floor", "fl", "unit", "rue", "allee", "chemin", "platz",
        "weg", "gasse", "calle", "avenida", "plaza", "via", "viale", "corso", "piazza", "straat", "laan",
        "plein", "kg", "kn", "kk", "box",
    ]

    // MARK: Text

    /// One line of single spaces, trimmed.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Lower case without accents: "Café Crème" is "cafe creme".
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
    }

    /// The line's words without accents or punctuation: "Total TTC:" is
    /// ["total", "ttc"].
    static func words(_ line: String) -> [String] {
        folded(line).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// "TRADER JOE'S" is "Trader Joe's"; short words without vowels stay
    /// in capitals ("CVS", "H&M"). Anything already in mixed case is kept.
    static func titleCased(_ text: String) -> String {
        guard text.contains(where: \.isLetter), !text.contains(where: \.isLowercase) else { return text }
        let words = text.split(separator: " ").map(String.init)
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, lowercaseTitleWords.contains(lower) { return lower }
            let letters = word.filter(\.isLetter)
            if letters.count <= 3, !letters.lowercased().contains(where: { "aeiouy".contains($0) }) { return word }
            var result = ""
            var startsWord = true
            for character in lower {
                result.append(startsWord ? Character(character.uppercased()) : character)
                startsWord = !(character.isLetter || character == "'" || character == "\u{2019}")
            }
            return result
        }
        .joined(separator: " ")
    }

    static let lowercaseTitleWords: Set<String> = [
        "of", "and", "the", "de", "du", "des", "la", "le", "les", "et", "y", "del", "da", "di", "van", "von",
        "der", "at", "on", "in", "for", "a", "an", "to",
    ]
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
