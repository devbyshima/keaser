import AppIntents
import Foundation

/// Ends an intent with a sentence instead of a result: Siri says it and
/// Shortcuts shows it where the run stopped. For answers the person should
/// hear in full ("Spending for This Year is part of Keaser Pro..."), worked
/// out in KeaserKit.
struct IntentRefusal: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
