import Foundation

/// The expense fields a Notion property can hold.
public enum NotionExpenseField: String, CaseIterable, Sendable, Identifiable {
    case title, amount, category, paymentMethod, date

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: "Title"
        case .amount: "Amount"
        case .category: "Category"
        case .paymentMethod: "Payment Method"
        case .date: "Date"
        }
    }

    /// SF Symbol for the review rows.
    public var symbol: String {
        switch self {
        case .title: "textformat"
        case .amount: "dollarsign.circle.fill"
        case .category: "tag.fill"
        case .paymentMethod: "creditcard.fill"
        case .date: "calendar"
        }
    }

    /// Property types Keaser can read and write for this field.
    public var supportedTypes: [NotionPropertyType] {
        switch self {
        case .title: [.title]
        case .amount: [.number]
        case .category: [.select, .multiSelect]
        case .paymentMethod: [.select, .richText, .multiSelect]
        case .date: [.date]
        }
    }

    /// Words that suggest a property holds this field, best first.
    var keywords: [String] {
        switch self {
        case .title: []
        case .amount: ["amount", "price", "cost", "total", "spent", "spend", "value", "sum"]
        case .category: ["category", "categories", "type", "kind", "tag", "tags", "group"]
        case .paymentMethod: ["payment method", "payment", "method", "paid with", "card", "account", "wallet", "source"]
        case .date: ["date", "day", "when", "spent on", "paid on"]
        }
    }

    /// Whether a lone property of the right type is a safe guess even when
    /// its name says nothing. A single number or date column almost always
    /// is the amount or the date; a single select could be anything.
    var acceptsUnnamedSingleCandidate: Bool {
        self == .amount || self == .date
    }
}

public enum NotionPropertyMatcher {
    /// Picks a property for each field from the schema: the title property,
    /// then a number named like Amount/Price/Cost/Total, a date named like
    /// Date/Day/When, a select or text named like Payment/Method/Card/Account
    /// and a select named like Category/Type. No property is used twice.
    /// Nil when the schema has no title property.
    public static func autoMap(_ dataSource: NotionDataSource) -> NotionPropertyMap? {
        guard let title = dataSource.properties.first(where: { $0.type == .title }) else { return nil }
        var used: Set<String> = [title.id]
        var chosen: [NotionExpenseField: NotionPropertySchema] = [.title: title]
        // Payment before category: "Payment Type" should land on payment.
        for field in [NotionExpenseField.amount, .date, .paymentMethod, .category] {
            if let match = bestMatch(for: field, in: dataSource.properties, excluding: used) {
                chosen[field] = match
                used.insert(match.id)
            }
        }
        return NotionPropertyMap(
            title: title,
            amount: chosen[.amount],
            category: chosen[.category],
            paymentMethod: chosen[.paymentMethod],
            date: chosen[.date]
        )
    }

    /// Properties the user may pick for a field, best guess first.
    public static func candidates(for field: NotionExpenseField, in dataSource: NotionDataSource) -> [NotionPropertySchema] {
        dataSource.properties
            .filter { field.supportedTypes.contains($0.type) }
            .sorted { score($0, for: field) > score($1, for: field) }
    }

    static func bestMatch(
        for field: NotionExpenseField,
        in properties: [NotionPropertySchema],
        excluding used: Set<String>
    ) -> NotionPropertySchema? {
        let typed = properties.filter { field.supportedTypes.contains($0.type) && !used.contains($0.id) }
        let scored = typed.map { ($0, score($0, for: field)) }.filter { $0.1 > 0 }
        if let best = scored.max(by: { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            // Prefer the first supported type (a select over text), then
            // schema order.
            return typeRank(a.0, field) > typeRank(b.0, field)
        }) {
            return best.0
        }
        if field.acceptsUnnamedSingleCandidate, typed.count == 1 { return typed[0] }
        return nil
    }

    /// Higher is better; 0 means the name does not suggest the field.
    static func score(_ property: NotionPropertySchema, for field: NotionExpenseField) -> Int {
        let name = normalized(property.name)
        let words = Set(name.split(separator: " ").map(String.init))
        var best = 0
        for (index, keyword) in field.keywords.enumerated() {
            let weight = field.keywords.count - index
            if name == keyword {
                best = max(best, 300 + weight)
            } else if keyword.contains(" ") ? name.contains(keyword) : words.contains(keyword) {
                best = max(best, 200 + weight)
            } else if name.contains(keyword) {
                best = max(best, 100 + weight)
            }
        }
        return best
    }

    private static func typeRank(_ property: NotionPropertySchema, _ field: NotionExpenseField) -> Int {
        field.supportedTypes.firstIndex(of: property.type) ?? field.supportedTypes.count
    }

    static func normalized(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension NotionPropertyMap {
    /// A map pointing at these schema properties, names and IDs both.
    public init(
        title: NotionPropertySchema,
        amount: NotionPropertySchema? = nil,
        category: NotionPropertySchema? = nil,
        paymentMethod: NotionPropertySchema? = nil,
        date: NotionPropertySchema? = nil
    ) {
        self.init(
            title: title.name,
            amount: amount?.name,
            category: category?.name,
            paymentMethod: paymentMethod?.name,
            date: date?.name,
            titleID: title.id,
            amountID: amount?.id,
            categoryID: category?.id,
            paymentMethodID: paymentMethod?.id,
            dateID: date?.id
        )
    }

    public func name(for field: NotionExpenseField) -> String? {
        switch field {
        case .title: title
        case .amount: amount
        case .category: category
        case .paymentMethod: paymentMethod
        case .date: date
        }
    }

    public func propertyID(for field: NotionExpenseField) -> String? {
        switch field {
        case .title: titleID
        case .amount: amountID
        case .category: categoryID
        case .paymentMethod: paymentMethodID
        case .date: dateID
        }
    }

    /// Points `field` at `property` (nil unmaps it). The title cannot be
    /// unmapped.
    public mutating func set(_ field: NotionExpenseField, to property: NotionPropertySchema?) {
        switch field {
        case .title:
            if let property { title = property.name; titleID = property.id }
        case .amount: amount = property?.name; amountID = property?.id
        case .category: category = property?.name; categoryID = property?.id
        case .paymentMethod: paymentMethod = property?.name; paymentMethodID = property?.id
        case .date: date = property?.name; dateID = property?.id
        }
    }

    /// Finds each mapped property in the current schema, by ID first so a
    /// rename in Notion is followed, then by name. A property that is gone or
    /// changed to a type Keaser cannot use drops out of the map. Nil when the
    /// schema has no title property.
    public func resolved(in dataSource: NotionDataSource) -> NotionResolvedMap? {
        guard let title = dataSource.properties.first(where: { $0.type == .title }) else { return nil }
        func find(_ field: NotionExpenseField) -> NotionPropertySchema? {
            let byID = propertyID(for: field).flatMap { id in dataSource.properties.first { $0.id == id } }
            let byName = name(for: field).flatMap { name in dataSource.properties.first { $0.name == name } }
            guard let property = byID ?? byName, field.supportedTypes.contains(property.type) else { return nil }
            return property
        }
        return NotionResolvedMap(
            title: title,
            amount: find(.amount),
            category: find(.category),
            paymentMethod: find(.paymentMethod),
            date: find(.date)
        )
    }
}

/// A property map checked against the live schema: every entry exists and
/// has a usable type.
public struct NotionResolvedMap: Hashable, Sendable {
    public var title: NotionPropertySchema
    public var amount: NotionPropertySchema?
    public var category: NotionPropertySchema?
    public var paymentMethod: NotionPropertySchema?
    public var date: NotionPropertySchema?

    public init(
        title: NotionPropertySchema,
        amount: NotionPropertySchema? = nil,
        category: NotionPropertySchema? = nil,
        paymentMethod: NotionPropertySchema? = nil,
        date: NotionPropertySchema? = nil
    ) {
        self.title = title
        self.amount = amount
        self.category = category
        self.paymentMethod = paymentMethod
        self.date = date
    }

    /// The stored form, with current names and IDs.
    public var map: NotionPropertyMap {
        NotionPropertyMap(title: title, amount: amount, category: category, paymentMethod: paymentMethod, date: date)
    }
}

/// The schema of a database Keaser creates, and the Notion number format
/// for the user's currency.
public enum NotionKeaserSchema {
    public static let title = "Name"
    public static let amount = "Amount"
    public static let category = "Category"
    public static let paymentMethod = "Payment"
    public static let date = "Date"

    public static func properties(
        currencyCode: String,
        categories: [String],
        paymentMethods: [String]
    ) -> [String: NotionNewProperty] {
        [
            title: .title,
            amount: .number(format: numberFormat(for: currencyCode)),
            category: .select(options: categories.map(NotionSelectName.sanitized)),
            paymentMethod: .select(options: paymentMethods.map(NotionSelectName.sanitized)),
            date: .date,
        ]
    }

    /// Notion's currency number formats; other currencies get plain numbers
    /// with thousands separators.
    public static func numberFormat(for currencyCode: String) -> String {
        formats[currencyCode.uppercased()] ?? "number_with_commas"
    }

    private static let formats: [String: String] = [
        "USD": "dollar", "AUD": "australian_dollar", "CAD": "canadian_dollar", "SGD": "singapore_dollar",
        "EUR": "euro", "GBP": "pound", "JPY": "yen", "RUB": "ruble", "INR": "rupee", "KRW": "won",
        "CNY": "yuan", "BRL": "real", "TRY": "lira", "IDR": "rupiah", "CHF": "franc",
        "HKD": "hong_kong_dollar", "NZD": "new_zealand_dollar", "SEK": "krona", "NOK": "norwegian_krone",
        "MXN": "mexican_peso", "ZAR": "rand", "TWD": "new_taiwan_dollar", "DKK": "danish_krone",
        "PLN": "zloty", "THB": "baht", "HUF": "forint", "CZK": "koruna", "ILS": "shekel",
        "CLP": "chilean_peso", "PHP": "philippine_peso", "AED": "dirham", "COP": "colombian_peso",
        "SAR": "riyal", "MYR": "ringgit", "RON": "leu", "ARS": "argentine_peso", "UYU": "uruguayan_peso",
        "PEN": "peruvian_sol", "VND": "vietnamese_dong", "PKR": "pakistani_rupee", "NGN": "nigerian_naira",
    ]
}

/// Select option names in Notion cannot contain commas and are capped at
/// 100 characters; names are compared loosely so "Food, Drinks" in Keaser
/// still matches the "Food Drinks" option it became in Notion.
public enum NotionSelectName {
    public static func sanitized(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(cleaned.prefix(100))
    }

    public static func key(_ name: String) -> String {
        sanitized(name).lowercased()
    }

    public static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): key(a) == key(b)
        default: false
        }
    }
}
