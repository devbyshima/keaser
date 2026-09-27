import Foundation

/// What a receipt says, as far as New Expense cares: who was paid, how
/// much, on which day, and in which currency if it says. Every field is
/// optional; the person reviews whatever was found before saving.
public struct ReceiptDraft: Equatable, Sendable {
    /// The shop, restaurant or business, tidied up to be an expense title.
    public var merchant: String?
    /// The amount paid in the end, tax included.
    public var total: Decimal?
    /// The day of the purchase.
    public var day: ReceiptDay?
    /// The ISO 4217 code of the currency printed on the receipt, only when
    /// the receipt names it (a code, or a symbol only one currency uses).
    public var currencyCode: String?

    public init(merchant: String? = nil, total: Decimal? = nil, day: ReceiptDay? = nil, currencyCode: String? = nil) {
        self.merchant = merchant
        self.total = total
        self.day = day
        self.currencyCode = currencyCode
    }

    /// True when it reads as a receipt: a total or a date was found. A name
    /// alone is not enough, since any photo with a line of text has one.
    public var isReceipt: Bool { total != nil || day != nil }

    /// True when the receipt names a currency other than `currencyCode`, the
    /// one Keaser records amounts in: the person should check the amount.
    public func isInOtherCurrency(than currencyCode: String) -> Bool {
        guard let printed = self.currencyCode else { return false }
        return printed.caseInsensitiveCompare(currencyCode) != .orderedSame
    }
}

/// A calendar day printed on a receipt, without a time or a time zone.
public struct ReceiptDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil unless it is a real day in the Gregorian calendar ("2026-02-30"
    /// is not).
    public init?(year: Int, month: Int, day: Int) {
        guard (1900...2999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.gregorian) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        var gregorian = Self.gregorian
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 2000
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// This day at the time of day `time` shows, so it reads in New
    /// Expense's date picker as if the person had picked the day there.
    public func date(keepingTimeOf time: Date, calendar: Calendar = .current) -> Date? {
        var gregorian = Self.gregorian
        gregorian.timeZone = calendar.timeZone
        var parts = gregorian.dateComponents([.hour, .minute, .second], from: time)
        parts.year = year
        parts.month = month
        parts.day = day
        return gregorian.date(from: parts)
    }

    /// The day after this one.
    public var next: ReceiptDay {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Self.gregorian.date(from: components),
              let next = Self.gregorian.date(byAdding: .day, value: 1, to: date)
        else { return self }
        return ReceiptDay(next, calendar: Self.gregorian)
    }

    public static func < (lhs: ReceiptDay, rhs: ReceiptDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// "2026-09-21".
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
}
