import Foundation

/// Any JSON value, kept exactly: numbers are `Decimal`, so an amount or a
/// date read from one device is written back digit for digit.
///
/// Sync payloads are held as JSON objects of these, so a field this build
/// does not know (added by a later version of Keaser) survives when this
/// build edits the record and sends it back.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// The one JSON dialect of sync payloads: sorted keys, so the same content
/// is always the same bytes (fingerprints and tie-breaks depend on it), and
/// dates as exact seconds, like the database file.
enum SyncCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// `value` as a JSON object.
    static func body<T: Encodable>(_ value: T) -> [String: JSONValue] {
        guard let data = try? encoder().encode(value),
              let body = try? decoder().decode([String: JSONValue].self, from: data)
        else { return [:] }
        return body
    }

    /// The value a JSON object holds; nil when it does not decode.
    static func value<T: Decodable>(_ type: T.Type, from body: [String: JSONValue]) -> T? {
        guard let data = try? encoder().encode(body) else { return nil }
        return try? decoder().decode(type, from: data)
    }
}
