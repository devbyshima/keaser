import Foundation

/// The app's version as shown in the Settings footer and support emails.
public struct AppVersion: Hashable, Sendable {
    /// `CFBundleShortVersionString`: "1.0.0".
    public let marketing: String
    /// `CFBundleVersion`: "1".
    public let build: String

    public init(marketing: String, build: String) {
        self.marketing = marketing
        self.build = build
    }

    /// Reads a bundle's Info.plist values; missing keys read as "0".
    public init(infoDictionary: [String: Any]?) {
        marketing = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// "1.0.0 (1)".
    public var display: String { "\(marketing) (\(build))" }
}

/// The "Support Email" row's message.
public enum SupportMail {
    public static let subject = "Keaser Support"

    /// A `mailto:` URL with the subject filled in and the app and system
    /// versions at the end of the body, so a report arrives with the context
    /// needed to answer it. Nil for an address that cannot form a URL.
    public static func url(to address: String, version: AppVersion, system: String) -> URL? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !address.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\n\n\nKeaser \(version.display), \(system)"),
        ]
        // URLComponents leaves "+" alone in queries, and some mail apps read
        // it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
