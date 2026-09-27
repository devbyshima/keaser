import Foundation

/// What Keaser asks the on-device language model when Smart Suggestions
/// needs a category for a title the person's history and the word rules do
/// not know, and how the answer maps back to the account. Pure and
/// Foundation-only: the app turns it into a Foundation Models request, and
/// the tests pin the exact text.
///
/// Only the category is asked for. The payment method keeps coming from the
/// person's history and the word rules (see `SmartSuggester.guessLabels`).
///
/// Everything except the title is the `promptPrefix`. It depends only on the
/// account's categories, so the app can prewarm the model with it when New
/// Expense opens, before the person has typed anything.
public struct CategoryPrompt: Hashable, Sendable {
    /// The choice that lets the model say no category fits.
    public static let noMatch = "none of these"

    /// Instructions for every request. Constant, so the system can reuse them.
    public static let instructions = """
    You file personal expenses into categories. Given the title of an expense, choose the category \
    it most likely belongs to, using only the categories given. A title is often a shop, brand, \
    service, place or person. Choose "\(noMatch)" when no category clearly fits.
    """

    /// Titles and category names are cut to this many characters.
    public static let maximumLength = 60

    /// Distinct category names in account order, then `noMatch`: the only
    /// strings the model can answer with.
    public let choices: [String]

    /// Nil for an account without categories: there is nothing to choose.
    public init?(categories: [ExpenseCategory]) {
        var seen: Set<String> = [Self.key(Self.noMatch)]
        var names: [String] = []
        for category in categories {
            let name = Self.oneLine(category.name)
            if !name.isEmpty, seen.insert(Self.key(name)).inserted { names.append(name) }
        }
        guard !names.isEmpty else { return nil }
        choices = names + [Self.noMatch]
    }

    /// The categories, each built-in one with what it covers.
    public var promptPrefix: String {
        let lines = choices.dropLast().map { name in
            "- " + name + (Self.hint(forCategoryNamed: name).map { " (\($0))" } ?? "")
        }
        return "Categories:\n" + lines.joined(separator: "\n") + "\n"
    }

    /// The whole prompt for a title; nil for a blank one.
    public func prompt(for title: String) -> String? {
        let title = Self.oneLine(title)
        guard !title.isEmpty else { return nil }
        return promptPrefix + "Expense title: \"\(title)\""
    }

    /// Identifies an answer for reuse: the same title, ignoring case and
    /// spaces, against the same categories.
    public func cacheKey(for title: String) -> String {
        Self.key(Self.oneLine(title)) + "\u{1F}" + choices.joined(separator: "\u{1F}")
    }

    /// The category an answer names, in `categories`. `noMatch` and names
    /// the account does not have give nil.
    public static func category(named answer: String?, in categories: [ExpenseCategory]) -> UUID? {
        guard let answer, key(answer) != key(noMatch) else { return nil }
        return categories.first { oneLine($0.name) == answer }?.id
            ?? categories.first { key(oneLine($0.name)) == key(answer) }?.id
    }

    /// What a built-in category covers, so the model files "Dentist" under
    /// Health rather than Services. Nil for a category the person made: its
    /// name is all the model gets.
    public static func hint(forCategoryNamed name: String) -> String? {
        builtInHints[key(name)]
    }

    // MARK: Private

    /// Measured on the Mac: without these the model files too much under
    /// Services (40 of 50 titles right instead of 46).
    private static let builtInHints: [String: String] = [
        "food & drinks": "restaurants, cafes, fast food, groceries, snacks, drinks, food delivery",
        "shopping": "shops, clothes, shoes, electronics, household goods, gifts, online orders",
        "travel": "flights, hotels, trips, holidays, sightseeing abroad",
        "services": "bills, utilities, phone and internet, repairs, cleaning, laundry, haircuts, fees",
        "entertainment": "streaming, movies, music, games, events, museums, hobbies, going out",
        "health": "doctors, dentists, pharmacies, medicine, gyms and fitness",
        "transportation": "taxis, ride hailing, public transport, fuel and petrol stations, parking, tolls, car costs",
    ]

    /// On one line, without quotes, shortened.
    private static func oneLine(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" })
        return String(words.joined(separator: " ").prefix(maximumLength))
    }

    private static func key(_ text: String) -> String {
        ExpenseQuery.normalized(text).lowercased()
    }
}
