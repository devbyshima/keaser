import Foundation
import KeaserKit

/// Launch arguments that put the app straight into a given state, so every
/// screen can be screenshotted from a cold launch without tapping.
///
/// Arguments are passed as `-Key value` pairs, which Foundation folds into the
/// `UserDefaults` argument domain. They are ignored entirely in Release.
///
/// Keys (see AGENTS.md for the full table):
/// - `-KeaserSeed fresh|onboarded|account|single|demo`
/// - `-KeaserOnboardingPage 0...4`
/// - `-KeaserSheet <name>` (each feature documents its own sheet names)
/// - `-KeaserSettingsPage <name>`
/// - `-KeaserPeriod today|thisWeek|thisMonth|thisYear|allTime`
enum DebugLaunch {
    static func string(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }

    static func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }

    static var seed: DemoData.Seed? {
        string("KeaserSeed").flatMap(DemoData.Seed.init(rawValue:))
    }

    /// The sheet a screenshot wants presented at launch, e.g. "newExpense".
    static var sheet: String? { string("KeaserSheet") }

    /// A page inside Settings, e.g. "currency".
    static var settingsPage: String? { string("KeaserSettingsPage") }

    /// A shortcut card drawn in a stand-in of the system's, e.g. "confirm"
    /// (see `SnippetPreview`).
    static var snippet: String? { string("KeaserSnippet") }
}
