import AppIntents
import Foundation

/// Ends an intent with a sentence instead of a result: Siri says it and
/// Shortcuts shows it where the run stopped. For answers the person should
/// hear in full ("Spending for This Year is part of Keaser Pro..."), worked
/// out in KeaserKit.
struct IntentRefusal: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    /// The kind of problem, when the system has one for it (iOS 27 presents
    /// it; see below). Nil for a plain sentence.
    let kind: AppIntentError?

    init(_ message: String, kind: AppIntentError? = nil) {
        self.message = message
        self.kind = kind
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// From iOS 27 the system takes an error's kind along with its sentence, and
// presents the kinds it knows its own way. Only the errors that are one of
// those kinds name it; the rest keep just their sentence, exactly as on
// earlier systems. (With both protocols the system reads only this one, so
// every case gives its sentence here too.)

@available(iOS 27.0, *)
extension IntentRefusal: CustomAppIntentErrorConvertible {
    var appIntentError: AppIntentError {
        guard let kind else { return AppIntentError(description: localizedStringResource) }
        return AppIntentError(predefinedError: kind, description: localizedStringResource)
    }
}

@available(iOS 27.0, *)
extension KeaserIntentError: CustomAppIntentErrorConvertible {
    var appIntentError: AppIntentError {
        switch self {
        case .noAccount:
            // Nothing can be added or answered until an account exists:
            // setup the person has to do in Keaser.
            AppIntentError(predefinedError: AppIntentError.UserActionRequired.accountSetup, description: localizedStringResource)
        case .invalidAmount, .dataUnavailable, .saveFailed:
            AppIntentError(description: localizedStringResource)
        }
    }
}
