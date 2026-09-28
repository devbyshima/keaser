import Foundation

/// An amount as Apple Wallet passes it to "Log Wallet Transaction": text in
/// whatever number style the card issuer or the phone writes, such as
/// "$4.50", "4,50 €", "1.234,56 €", "RWF 5,000", "5 000 RWF" or
/// "CHF 1'234.50".
///
/// The number is read with the receipt reader's rules
/// (`ReceiptParser.number`), not with the phone's number style alone, so
/// "4,50 €" is 4.50 on an English (US) phone and "$4.50" is 4.50 on a German
/// one:
/// - With two kinds of separator, the last one is the decimal point
///   ("1.234,56", "1,234.56").
/// - A lone separator before one or two digits is the decimal point
///   ("4,50").
/// - A lone separator before three digits groups thousands when the
///   currency has at most two decimals ("RWF 5,000", "¥1,500", "€1.234").
///   Only for a currency with three (KWD) does the phone's decimal
///   separator settle it.
/// - A space (also U+00A0 or U+202F) groups thousands only before three
///   digits ("5 000"), and "’" is read as "'" ("1’234.50").
/// - Indian grouping reads too ("₹1,23,456.00").
///
/// Anything negative, zero, or not exactly one number is refused, as is a
/// number with more than nine digits before the point (the receipt
/// reader's limit).
public struct WalletAmount: Equatable, Sendable {
    /// The text as passed, trimmed.
    public let text: String
    /// The number written, not rounded to any currency.
    public let value: Decimal
    /// What is written around the number ("€", "RWF", "CA$", "Fr" for
    /// "Fr."), in order; empty for a bare number.
    public let marks: [String]

    /// Reads `text`. `currencyCode` is the currency of a number whose marks
    /// name none (Keaser's own, which it is recorded in). `locale` decides
    /// "1.500" only when that currency can have three decimals, or is not
    /// known.
    public static func read(_ text: String, currencyCode: String? = nil, locale: Locale = .current) -> WalletAmount? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A minus anywhere, and digits Keaser does not read ("٤٫٥٠").
        guard !text.contains(where: { $0 == "-" || $0 == "\u{2212}" || ($0.isNumber && !$0.isASCIIDigit) }) else { return nil }
        let characters = Array(text)
        let runs = numberRuns(in: characters)
        guard runs.count == 1, var run = runs.first else { return nil }
        // An en dash before the number is a minus too ("–4,50 €"); after it,
        // it stands for no cents ("CHF 12.–").
        guard !characters[..<run.lowerBound].contains("\u{2013}") else { return nil }

        var number = String(characters[run].map { isSpace($0) || $0 == "\u{2019}" ? "'" : $0 })
        // "$.50" and ".50": a decimal point with no digit before it. Not
        // "Rs.50", which is 50 rupees.
        if run.lowerBound > 0, characters[run.lowerBound - 1] == "." || characters[run.lowerBound - 1] == "," {
            let before = run.lowerBound > 1 ? characters[run.lowerBound - 2] : nil
            if before.map({ $0.isWhitespace || $0.isCurrencySymbol }) ?? true {
                number = "0" + String(characters[run.lowerBound - 1]) + number
                run = (run.lowerBound - 1)..<run.upperBound
            }
        }
        // Indian grouping: thousands, then pairs ("1,23,456.00").
        if number.range(of: #"^\d{1,2}(,\d{2})+,\d{3}(\.\d+)?$"#, options: .regularExpression) != nil {
            number.removeAll { $0 == "," }
        }

        let marks = words(in: characters[..<run.lowerBound]) + words(in: characters[run.upperBound...])
        // A lone separator before three digits is a decimal point only in a
        // currency that can have three decimals, and there only where the
        // phone writes decimals that way.
        let canHaveThreeDecimals = maximumDecimals(of: marks, currencyCode: currencyCode).map { $0 >= 3 } ?? true
        let decimalSeparator = canHaveThreeDecimals ? locale.decimalSeparator?.first : nil
        guard let (value, _) = ReceiptParser.number(number, decimalSeparator: decimalSeparator), value > 0 else { return nil }
        return WalletAmount(text: text, value: value, marks: marks)
    }

    // MARK: Private

    /// Each number written: ASCII digits, with ".", ",", "'" or "’" between
    /// digits, and a space before a group of exactly three digits.
    private static func numberRuns(in characters: [Character]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
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
                } else if separators.contains(characters[end]), end + 1 < characters.count, characters[end + 1].isASCIIDigit {
                    end += 2
                } else if isSpace(characters[end]), isGroupOfThree(characters, at: end + 1) {
                    end += 4
                } else {
                    break
                }
            }
            runs.append(start..<end)
            index = end
        }
        return runs
    }

    private static let separators: Set<Character> = [".", ",", "'", "\u{2019}"]

    /// Three digits at `index`, and no fourth.
    private static func isGroupOfThree(_ characters: [Character], at index: Int) -> Bool {
        guard index + 3 <= characters.count, characters[index..<(index + 3)].allSatisfy(\.isASCIIDigit) else { return false }
        return index + 3 == characters.count || !characters[index + 3].isASCIIDigit
    }

    /// The chunks of text between spaces that have a letter or a currency
    /// symbol in them, with a trailing "." dropped ("Fr." is "Fr"). The
    /// ".–" of "12.–" is not one.
    private static func words(in characters: ArraySlice<Character>) -> [String] {
        characters.split(whereSeparator: \.isWhitespace).compactMap { chunk in
            guard chunk.contains(where: { $0.isLetter || $0.isCurrencySymbol }) else { return nil }
            var word = String(chunk)
            if word.hasSuffix(".") { word.removeLast() }
            return word
        }
    }

    /// The most decimals the currency can have: the one the marks name, else
    /// `currencyCode`. Every currency written with "$" or "¥" has at most
    /// two. Nil when neither says.
    private static func maximumDecimals(of marks: [String], currencyCode: String?) -> Int? {
        var named: [Int] = []
        for mark in marks {
            let currency = ReceiptParser.currency(forMark: mark)
            if let code = currency.code {
                named.append(fractionDigits(of: code))
            } else if currency.isMark || mark.contains(where: { $0 == "$" || $0 == "¥" || $0 == "￥" }) {
                named.append(2)
            }
        }
        return named.max() ?? currencyCode.map { fractionDigits(of: $0) }
    }

    private static func fractionDigits(of currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }

    /// A space that can group thousands: " ", U+00A0, U+202F and the like,
    /// never a line break.
    private static func isSpace(_ character: Character) -> Bool {
        character.isWhitespace && !character.isNewline
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
