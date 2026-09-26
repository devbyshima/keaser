import Foundation

extension DateInterval {
    /// `start <= date < end`. `contains` includes `end`, which would put an
    /// expense dated exactly at midnight in two adjacent days, weeks or
    /// months; expense dates are often exactly midnight.
    func holds(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

extension Account {
    /// Sum of expenses dated in `interval` (half-open); all expenses when nil.
    func spending(in interval: DateInterval?) -> Decimal {
        expenses.reduce(into: Decimal(0)) { sum, expense in
            if interval.map({ $0.holds(expense.date) }) ?? true { sum += expense.amount }
        }
    }
}
