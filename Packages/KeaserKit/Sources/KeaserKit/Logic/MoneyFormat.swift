import Foundation

public enum MoneyFormat {
    /// "$20.00" for USD in an English locale. Uses the currency's own number of
    /// fraction digits (JPY shows none).
    public static func string(_ amount: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// The currency symbol alone ("$", "€", "KSh"), for prefixing an amount
    /// field while the user types.
    public static func symbol(for currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.currencySymbol ?? currencyCode
    }

    /// Parses user input such as "20", "20.5", "1,234.56" or "$20" in the given
    /// locale. Returns nil for anything that is not a non-negative number.
    public static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        var cleaned = ""
        for character in text {
            let s = String(character)
            if character.isASCII && character.isNumber {
                cleaned.append(character)
            } else if s == "-" || s == "\u{2212}" {
                return nil
            } else if s == separator {
                if cleaned.contains(".") { return nil }
                cleaned.append(".")
            } else if s == grouping || character.isWhitespace {
                continue
            } else if s == "." {
                // Pasted text may use "." even where the locale does not.
                if cleaned.contains(".") { return nil }
                cleaned.append(".")
            } else if !character.isLetter && !character.isPunctuation && !character.isSymbol {
                return nil
            }
        }
        guard !cleaned.isEmpty, cleaned != "." else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Decimal {
    /// For chart geometry only. Never do money arithmetic in `Double`.
    public var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
