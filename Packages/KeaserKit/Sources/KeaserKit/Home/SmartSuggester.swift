import Foundation

/// Smart Suggestions: while the user types a title in the expense editor,
/// offer past expenses with a matching title so one tap fills in the amount,
/// category and payment method as well.
public enum SmartSuggester {
    public static let defaultLimit = 3

    /// Up to `limit` past expenses whose title matches `query`, one per
    /// distinct title (its most recent use). Titles that start with the query
    /// come before titles that merely contain it; within each group the most
    /// recent comes first. Matching ignores case and diacritics.
    ///
    /// `excluding` leaves out the expense being edited, so it does not
    /// suggest itself.
    public static func suggestions(
        for query: String,
        in expenses: [Expense],
        excluding excludedID: UUID? = nil,
        limit: Int = defaultLimit
    ) -> [Expense] {
        let needle = ExpenseQuery.normalized(query)
        guard !needle.isEmpty, limit > 0 else { return [] }

        var seenTitles = Set<String>()
        var prefixMatches: [Expense] = []
        var containsMatches: [Expense] = []
        for expense in expenses.sorted(by: ExpenseQuery.isNewer) where expense.id != excludedID {
            let title = ExpenseQuery.normalized(expense.title)
            guard !title.isEmpty, !seenTitles.contains(title) else { continue }
            if title.hasPrefix(needle) {
                prefixMatches.append(expense)
            } else if title.contains(needle) {
                containsMatches.append(expense)
            } else {
                continue
            }
            seenTitles.insert(title)
        }
        return Array((prefixMatches + containsMatches).prefix(limit))
    }
}
