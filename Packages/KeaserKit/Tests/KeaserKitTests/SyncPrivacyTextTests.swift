import Foundation
import Testing
@testable import KeaserKit

struct SyncPrivacyTextTests {
    @Test func conditionalSectionsFollowTheirFlag() {
        let source = """
        Always.
        <!-- if icloud -->
        Synced.
        <!-- else -->
        Local only.
        <!-- end -->
        <!-- a note for editors -->
        After.
        """
        #expect(MarkdownConditions.resolve(source, flags: ["icloud"]) == "Always.\nSynced.\nAfter.")
        #expect(MarkdownConditions.resolve(source, flags: []) == "Always.\nLocal only.\nAfter.")
    }

    /// The bundled policy mentions iCloud only in builds that sync.
    @Test func thePrivacyPolicyWordsICloudBehindTheSwitch() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Keaser/Resources/Legal/privacy.md")
        let source = try String(contentsOf: url, encoding: .utf8)
        let off = MarkdownConditions.resolve(source, flags: [])
        let on = MarkdownConditions.resolve(source, flags: ["icloud"])
        #expect(!off.contains("iCloud"))
        #expect(!off.contains("<!--"))
        #expect(off.contains("nothing you enter leaves your iPhone"))
        #expect(on.contains("your own private iCloud database, which Apple stores and the makers of Keaser cannot read"))
        #expect(!on.contains("nothing you enter leaves your iPhone"))
        #expect(!MarkdownBlocks.parse(on).isEmpty)
    }
}
