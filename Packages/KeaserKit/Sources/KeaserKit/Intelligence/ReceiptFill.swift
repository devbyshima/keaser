import Foundation

/// What a read receipt fills in on the expense editor's card: only what is
/// still empty, never what the person typed or picked. The title when it
/// is blank, the amount when there is none, and the day while the date is
/// still the one the editor opened with.
public struct ReceiptFill: Equatable, Sendable {
    public var title: String?
    public var total: Decimal?
    public var day: ReceiptDay?

    public init(_ draft: ReceiptDraft, titleIsEmpty: Bool, amountIsEmpty: Bool, dateIsUntouched: Bool) {
        title = titleIsEmpty ? draft.merchant : nil
        total = amountIsEmpty ? draft.total : nil
        day = dateIsUntouched ? draft.day : nil
    }

    /// Nothing to fill in.
    public var isEmpty: Bool { title == nil && total == nil && day == nil }

    /// Whether a receipt added now is worth reading at all: only while the
    /// title or the amount is still empty. A later receipt added to an
    /// expense already filled in is only kept.
    public static func wantsReading(titleIsEmpty: Bool, amountIsEmpty: Bool) -> Bool {
        titleIsEmpty || amountIsEmpty
    }
}
