import Foundation

/// One row of the currency picker: "US Dollar (USD)".
public struct CurrencyOption: Identifiable, Hashable, Sendable {
    /// ISO 4217 code, upper case.
    public let code: String
    /// The locale's name for the currency, or nil when it has none, so the
    /// row shows the bare code instead of repeating it.
    public let name: String?

    public init(code: String, name: String?) {
        self.code = code
        self.name = name
    }

    public var id: String { code }

    /// "US Dollar (USD)", or "XYZ" when there is no localized name.
    public var title: String {
        name.map { "\($0) (\(code))" } ?? code
    }
}

/// Every currency the picker offers, and its search.
public enum CurrencyCatalog {
    /// All common ISO 4217 currencies plus any `extra` codes (so a stored code
    /// that is no longer "common" still shows up checked), sorted by code.
    public static func options(locale: Locale = .current, including extra: [String] = []) -> [CurrencyOption] {
        var codes = Set(Locale.commonISOCurrencyCodes.map { $0.uppercased() })
        for code in extra {
            let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !cleaned.isEmpty { codes.insert(cleaned) }
        }
        return codes.sorted().map { CurrencyOption(code: $0, name: name(for: $0, locale: locale)) }
    }

    /// The locale's name for `code`, or nil when the locale only echoes the
    /// code back.
    public static func name(for code: String, locale: Locale = .current) -> String? {
        guard let name = locale.localizedString(forCurrencyCode: code),
              !name.isEmpty,
              name.caseInsensitiveCompare(code) != .orderedSame
        else { return nil }
        return name
    }

    /// Options whose code or name contains every word of `query`, ignoring
    /// case and accents ("bolivar" finds "Bolívar"). Ranked so what the user
    /// most likely means comes first: an exact code, then options where every
    /// word starts a word ("us dol" finds US Dollar before Australian
    /// Dollar), then the rest; ties keep the order of `options`. An empty
    /// query returns `options` unchanged.
    public static func filter(_ options: [CurrencyOption], matching query: String) -> [CurrencyOption] {
        let words = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return options }
        let exact = words.joined(separator: " ")
        var ranked: [(rank: Int, option: CurrencyOption)] = []
        for option in options {
            let haystack = normalized(option.code + " " + (option.name ?? ""))
            guard words.allSatisfy({ haystack.contains($0) }) else { continue }
            let tokens = haystack.split { !$0.isLetter && !$0.isNumber }
            let rank: Int
            if normalized(option.code) == exact {
                rank = 0
            } else if words.allSatisfy({ word in tokens.contains { $0.hasPrefix(word) } }) {
                rank = 1
            } else {
                rank = 2
            }
            ranked.append((rank, option))
        }
        // `sorted` is not guaranteed stable, so break ties on original order.
        return ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.option)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
