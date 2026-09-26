import Foundation

/// A JSON value, for request bodies. Numbers are `Decimal` so an amount is
/// written to Notion exactly as it is stored ("16.99", never
/// "16.989999999999998").
public enum NotionJSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([NotionJSON])
    case object([String: NotionJSON])

    public subscript(key: String) -> NotionJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [NotionJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var numberValue: Decimal? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }
}

extension NotionJSON: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([NotionJSON].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: NotionJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}

extension NotionJSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Decimal(value)) }
    public init(arrayLiteral elements: NotionJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, NotionJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension NotionJSON {
    /// Rich text as Notion accepts it on writes: one plain text run.
    /// Notion caps a text run at 2,000 characters.
    static func richText(_ text: String) -> NotionJSON {
        guard !text.isEmpty else { return [] }
        return [["type": "text", "text": ["content": .string(String(text.prefix(2000)))]]]
    }
}
