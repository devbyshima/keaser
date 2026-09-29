import Foundation
import KeaserKit

/// Whether iCloud sync runs in this build. Both must hold:
///
/// - The build has the iCloud entitlements. Only builds signed with
///   `Keaser/App/KeaserCloud.entitlements` (the `CloudSyncSigning` template
///   in project.yml) have them, and that template is also what defines
///   `KEASER_CLOUD`. The free personal team cannot sign them, and touching
///   CloudKit without them crashes the app, so this is settled when the app
///   is compiled.
/// - The flag says so: `KeaserCloudSync` in Info.plist, which the same
///   template sets to true. Setting it to false there ships the
///   entitlements with sync held back. In DEBUG, `-KeaserCloudSync off`
///   turns sync off for one launch.
///
/// Seeded DEBUG launches never sync: their data is made up. Nor does a
/// DEBUG install the App Intents tests have written their fixture into.
enum CloudSyncSwitch {
    static var buildHasEntitlements: Bool {
        #if KEASER_CLOUD
        true
        #else
        false
        #endif
    }

    static var flagIsOn: Bool {
        Bundle.main.object(forInfoDictionaryKey: "KeaserCloudSync") as? Bool == true
    }

    @MainActor
    static var isEnabled: Bool {
        guard buildHasEntitlements, flagIsOn else { return false }
        #if DEBUG
        if DebugLaunch.seed != nil || DebugLaunch.string("KeaserCloudSync") == "off" { return false }
        if UserDefaults.standard.bool(forKey: testDataKey) { return false }
        #endif
        return true
    }

    #if DEBUG
    /// Set by `ResetTestDataIntent`, whose fixture replaces the whole
    /// database: synced, it would replace the person's iCloud data too.
    static let testDataKey = "KeaserCloudSyncOffForTestData"
    #endif
}
