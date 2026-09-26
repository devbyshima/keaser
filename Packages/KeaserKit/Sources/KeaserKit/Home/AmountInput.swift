import Foundation

/// The expense editor's amount field. It shows the currency symbol in front
/// of whatever the user types ("$20"), keeps only digits and one decimal
/// separator, and never allows more fraction digits than the currency has.
public enum AmountInput {
    /// Long enough for any real expense, short enough that a pasted phone
    /// number does not turn into one.
    public static let maximumIntegerDigits = 10

    /// What the field shows for `input`: the symbol plus the cleaned number,
    /// or an empty string (so the placeholder appears) when nothing is left.
    public static func display(
        _ input: String,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let number = digits(input, currencyCode: currencyCode, locale: locale)
        return number.isEmpty ? "" : MoneyFormat.symbol(for: currencyCode, locale: locale) + number
    }

    /// The typed number alone: digits and at most one decimal separator (the
    /// locale's), trimmed to the currency's fraction digits. The currency
    /// symbol and anything else are dropped.
    public static func digits(
        _ input: String,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let symbol = MoneyFormat.symbol(for: currencyCode, locale: locale)
        var text = Substring(input)
        if !symbol.isEmpty, text.hasPrefix(symbol) { text = text.dropFirst(symbol.count) }

        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let fractionLimit = fractionDigits(for: currencyCode, locale: locale)
        var integer = ""
        var fraction = ""
        var sawSeparator = false
        for character in text {
            let s = String(character)
            if character.isASCII && character.isNumber {
                if sawSeparator {
                    if fraction.count < fractionLimit { fraction.append(character) }
                } else if integer.count < maximumIntegerDigits {
                    integer.append(character)
                }
            } else if s == separator || (s == "." && grouping != ".") {
                // A pasted "20.5" still works where the separator is ",".
                if fractionLimit > 0 { sawSeparator = true }
            }
        }
        if sawSeparator {
            return (integer.isEmpty ? "0" : integer) + separator + fraction
        }
        return integer
    }

    /// The field's starting text when editing an existing amount: "20.00",
    /// with the currency's usual fraction digits and no grouping.
    public static func editingText(
        for amount: Decimal,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let digits = fractionDigits(for: currencyCode, locale: locale)
        return amount.formatted(
            .number
                .precision(.fractionLength(digits))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// What the field shows when it is filled in from a stored amount (an
    /// expense being edited, or a Smart Suggestion): "$20.00".
    public static func field(
        for amount: Decimal,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        display(editingText(for: amount, currencyCode: currencyCode, locale: locale), currencyCode: currencyCode, locale: locale)
    }

    /// The amount to save for what the field shows. While the field still
    /// shows exactly what `seed` was filled in as, `seed` itself comes back:
    /// an amount with more fraction digits than the currency (from Notion,
    /// or logged before a currency change) must survive an edit that never
    /// touched it, even though the field can only show it rounded.
    public static func amount(
        from field: String,
        seed: Decimal?,
        currencyCode: String,
        locale: Locale = .current
    ) -> Decimal? {
        if let seed, field == self.field(for: seed, currencyCode: currencyCode, locale: locale) {
            return seed
        }
        return MoneyFormat.parse(digits(field, currencyCode: currencyCode, locale: locale), locale: locale)
    }

    /// 2 for USD and EUR, 0 for JPY, 3 for KWD.
    public static func fractionDigits(for currencyCode: String, locale: Locale = .current) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.maximumFractionDigits
    }
}
