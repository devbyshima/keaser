import Foundation
import Synchronization

/// Each currency's decimal places, and rounding to them.
public enum CurrencyMath {
    /// How many decimal places `code` is written with (USD 2, JPY and RWF
    /// 0, KWD 3), from Foundation's own currency data, the source
    /// `MoneyFormat` prints from, so a rounded amount prints exactly.
    public static func fractionDigits(for code: String) -> Int {
        let code = code.uppercased()
        if let known = digits.withLock({ $0[code] }) { return known }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = code
        let found = formatter.maximumFractionDigits
        digits.withLock { $0[code] = found }
        return found
    }

    /// `amount` to `currencyCode`'s places, halves away from zero
    /// (RWF 2.5 is 3, -2.5 is -3).
    public static func rounded(_ amount: Decimal, currencyCode: String) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, fractionDigits(for: currencyCode), .plain)
        return result
    }

    /// Looked up once per currency: making a formatter is slow next to the
    /// sums it serves.
    private static let digits = Mutex<[String: Int]>([:])
}
