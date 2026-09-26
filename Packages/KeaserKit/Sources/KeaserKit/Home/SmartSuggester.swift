import Foundation

/// Smart Suggestions: while the user types a title in the expense editor,
/// offer past expenses with a matching title so one tap fills in the amount,
/// category and payment method as well. When the user moves on from a title,
/// guess its category and payment method (`guessLabels`).
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

    // MARK: Guessing labels

    /// A category and payment method for a title. Nil where there is no
    /// good guess.
    public struct LabelGuess: Hashable, Sendable {
        public var categoryID: UUID?
        public var paymentMethodID: UUID?

        public init(categoryID: UUID? = nil, paymentMethodID: UUID? = nil) {
            self.categoryID = categoryID
            self.paymentMethodID = paymentMethodID
        }
    }

    /// Guesses the category and payment method of an expense from its title,
    /// using only labels the account has.
    ///
    /// Past expenses come first: the labels used most often on titles that
    /// share a word with this one ("Coffee beans" learns from "Coffee").
    /// Otherwise common words point at a label by name ("Outing" at Travel
    /// and Cash, "Uber" at Transportation), so a new account gets guesses
    /// too. With nothing else to go on, the payment method is the one used
    /// most often.
    public static func guessLabels(
        for title: String,
        categories: [ExpenseCategory],
        paymentMethods: [PaymentMethod],
        history: [Expense],
        excluding excludedID: UUID? = nil
    ) -> LabelGuess {
        let words = words(in: title)
        guard !words.isEmpty else { return LabelGuess() }
        let history = history.filter { $0.id != excludedID }
        let categoryIDs = Set(categories.map(\.id))
        let methodIDs = Set(paymentMethods.map(\.id))

        // Past expenses whose titles share a word, weighted by how many.
        let longWords = words.filter { $0.count >= 3 }
        let similar: [(expense: Expense, weight: Int)] = history.compactMap { expense in
            let theirs = Self.words(in: expense.title)
            let weight = longWords.filter { word in theirs.contains { wordsMatch(word, $0) } }.count
            return weight > 0 ? (expense, weight) : nil
        }

        let learnedCategory = mostUsed(similar.compactMap { item in
            item.expense.categoryID.flatMap { categoryIDs.contains($0) ? Use(id: $0, weight: item.weight, expense: item.expense) : nil }
        })
        let learnedMethod = mostUsed(similar.compactMap { item in
            item.expense.paymentMethodID.flatMap { methodIDs.contains($0) ? Use(id: $0, weight: item.weight, expense: item.expense) : nil }
        })
        let habitualMethod = mostUsed(history.compactMap { expense in
            expense.paymentMethodID.flatMap { methodIDs.contains($0) ? Use(id: $0, weight: 1, expense: expense) : nil }
        })

        let category = learnedCategory
            ?? bestRule(categoryRules, for: words).flatMap { label(in: categories.map { ($0.id, $0.name) }, named: $0.labelNames) }
        let method = learnedMethod
            ?? bestRule(paymentRules, for: words).flatMap { label(in: paymentMethods.map { ($0.id, $0.name) }, named: $0.labelNames) }
            ?? habitualMethod
        return LabelGuess(categoryID: category, paymentMethodID: method)
    }

    private struct Use {
        let id: UUID
        let weight: Int
        let expense: Expense
    }

    /// The id with the highest total weight; ties go to the most recent use.
    private static func mostUsed(_ uses: [Use]) -> UUID? {
        var totals: [UUID: (weight: Int, latest: Expense)] = [:]
        for use in uses {
            if let current = totals[use.id] {
                let latest = ExpenseQuery.isNewer(use.expense, than: current.latest) ? use.expense : current.latest
                totals[use.id] = (current.weight + use.weight, latest)
            } else {
                totals[use.id] = (use.weight, use.expense)
            }
        }
        return totals.max { a, b in
            a.value.weight != b.value.weight
                ? a.value.weight < b.value.weight
                : ExpenseQuery.isNewer(b.value.latest, than: a.value.latest)
        }?.key
    }

    /// The rule matching the most words of the title; on a tie, the one
    /// matching earlier ("Train ticket" is transport, "Movie ticket" is
    /// entertainment).
    private static func bestRule(_ rules: [Rule], for words: [String]) -> Rule? {
        var best: (rule: Rule, count: Int, first: Int)?
        for rule in rules {
            let positions = words.indices.filter { index in
                rule.titleWords.contains { keywordMatches($0, words[index]) }
            }
            guard let first = positions.first else { continue }
            if let current = best, positions.count < current.count || (positions.count == current.count && first >= current.first) {
                continue
            }
            best = (rule, positions.count, first)
        }
        return best?.rule
    }

    /// The first label with a word in its name starting with one of `names`,
    /// trying `names` in order.
    private static func label(in labels: [(id: UUID, name: String)], named names: [String]) -> UUID? {
        for name in names {
            if let match = labels.first(where: { words(in: $0.name).contains { $0.hasPrefix(name) } }) {
                return match.id
            }
        }
        return nil
    }

    /// Lowercased words without diacritics: "Café-bar!" is ["cafe", "bar"].
    static func words(in text: String) -> [String] {
        ExpenseQuery.normalized(text)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Same word give or take an ending: "grocery" and "groceries",
    /// "coffee" and "coffees".
    static func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 4 else { return false }
        let common = zip(a, b).prefix { $0 == $1 }.count
        return common >= max(4, Int((Double(shorter) * 0.8).rounded(.up)))
    }

    /// Keywords of five letters or more also match longer words ("coffee"
    /// matches "coffeeshop"); shorter ones must match whole, so "bar" does
    /// not match "barber".
    private static func keywordMatches(_ keyword: String, _ word: String) -> Bool {
        keyword.count >= 5 ? word.hasPrefix(keyword) : word == keyword
    }

    /// Title words that point at a label, and the words that label's name
    /// may start with, most specific first.
    private struct Rule {
        let labelNames: [String]
        let titleWords: [String]
    }

    private static let categoryRules: [Rule] = [
        Rule(labelNames: ["food", "drink", "dining", "restaurant", "grocer", "meal", "eat"], titleWords: [
            "food", "meal", "meals", "coffee", "cafe", "cafes", "latte", "espresso", "tea", "lunch", "dinner",
            "breakfast", "brunch", "supper", "restaurant", "pizza", "burger", "sushi", "ramen", "taco", "tacos",
            "sandwich", "bakery", "bread", "snack", "snacks", "grocer", "supermarket", "takeaway", "takeout",
            "drink", "drinks", "beer", "beers", "wine", "bar", "pub", "cocktail", "juice", "smoothie", "dessert",
            "icecream", "donut", "donuts", "doughnut", "boba",
        ]),
        Rule(labelNames: ["shop", "cloth", "retail"], titleWords: [
            "shopping", "shop", "shops", "clothes", "clothing", "shirt", "tshirt", "jeans", "dress", "shoes",
            "sneakers", "jacket", "mall", "gift", "gifts", "present", "electronics", "headphones", "book", "books",
            "furniture", "decor", "cosmetics", "makeup", "perfume", "toys", "stationery",
        ]),
        Rule(labelNames: ["travel", "trip", "vacation", "holiday"], titleWords: [
            "outing", "trip", "trips", "travel", "flight", "airline", "airport", "hotel", "hostel", "airbnb",
            "holiday", "vacation", "tour", "tours", "excursion", "visa", "luggage", "souvenir", "resort", "cruise",
            "sightseeing", "beach", "camping",
        ]),
        Rule(labelNames: ["service", "utilit", "bill", "subscription"], titleWords: [
            "haircut", "barber", "salon", "laundry", "cleaning", "cleaner", "repair", "plumber", "electrician",
            "mechanic", "subscription", "internet", "wifi", "phone", "mobile", "electricity", "water", "utilities",
            "insurance", "fee", "fees", "service", "postage", "shipping", "printing", "storage", "hosting",
            "software",
        ]),
        Rule(labelNames: ["entertain", "fun", "leisure", "hobby", "hobbies"], titleWords: [
            "movie", "cinema", "film", "films", "concert", "show", "shows", "theatre", "theater", "netflix",
            "spotify", "streaming", "game", "games", "gaming", "ticket", "festival", "museum", "party", "club",
            "bowling", "karaoke", "arcade", "music", "album", "zoo",
        ]),
        Rule(labelNames: ["health", "medic", "fitness", "wellness", "pharmacy"], titleWords: [
            "pharmacy", "doctor", "dentist", "dental", "medicine", "medication", "pills", "vitamins", "hospital",
            "clinic", "therapy", "therapist", "physio", "gym", "fitness", "yoga", "pilates", "optician", "glasses",
            "checkup", "vaccine", "prescription", "drugstore", "chemist",
        ]),
        Rule(labelNames: ["transport", "commute", "transit", "car", "taxi", "vehicle", "fuel"], titleWords: [
            "uber", "lyft", "taxi", "taxis", "cab", "bus", "train", "metro", "subway", "tram", "ferry", "fuel",
            "gas", "petrol", "diesel", "parking", "toll", "tolls", "bike", "scooter", "car", "carwash", "commute",
            "transit", "ride", "rides", "rideshare",
        ]),
    ]

    private static let paymentRules: [Rule] = [
        Rule(labelNames: ["cash"], titleWords: [
            "cash", "tip", "tips", "outing", "market", "vendor", "kiosk", "street", "stall",
        ]),
        Rule(labelNames: ["credit", "card"], titleWords: [
            "subscription", "online", "netflix", "spotify", "streaming", "flight", "hotel", "airbnb",
        ]),
        Rule(labelNames: ["transfer", "bank"], titleWords: [
            "rent", "transfer", "tuition", "mortgage", "loan", "invoice", "deposit",
        ]),
    ]
}
