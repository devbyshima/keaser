import Foundation
import Testing
@testable import KeaserKit

struct SettingsTutorialsTests {
    private var everyText: [String] { Tutorials.all.flatMap(\.text) }

    @Test func listsEachTutorialOnceInOrder() {
        #expect(Tutorials.all.map(\.id) == Tutorial.ID.allCases)
        for id in Tutorial.ID.allCases {
            #expect(Tutorials.tutorial(id).id == id)
        }
    }

    /// These are the titles the Shortcuts app shows for `AddExpenseIntent`
    /// and its parameters. Change one only together with the intent.
    @Test func actionAndFieldTitlesMatchTheIntent() {
        #expect(Tutorials.addExpenseActionTitle == "Add Expense")
        #expect(Tutorials.titleFieldTitle == "Title")
        #expect(Tutorials.amountFieldTitle == "Amount")
        #expect(Tutorials.categoryFieldTitle == "Category")
        #expect(Tutorials.paymentMethodFieldTitle == "Payment Method")
        #expect(Tutorials.accountFieldTitle == "Account")
        #expect(Tutorials.dateFieldTitle == "Date")
        #expect(Tutorials.addExpenseFieldTitles == ["Title", "Amount", "Category", "Payment Method", "Account", "Date"])
    }

    @Test func copyNamesTheActionAndEveryFieldExactly() {
        for tutorial in Tutorials.all {
            let text = tutorial.text.joined(separator: " ")
            #expect(text.contains("**\(Tutorials.addExpenseActionTitle)**"), "\(tutorial.id)")
        }
        let text = everyText.joined(separator: " ")
        for field in Tutorials.addExpenseFieldTitles {
            #expect(text.contains("**\(field)**"), "\(field)")
        }
    }

    @Test func noLongerTeachesTheWalletTransactionAction() {
        for text in everyText {
            #expect(!text.contains("Log Wallet Transaction"), "\(text)")
        }
    }

    @Test func copyNeverMentionsAnotherProduct() {
        for text in everyText {
            let lowered = text.lowercased()
            #expect(!lowered.contains("notion"), "\(text)")
            #expect(!lowered.contains("syncspend"), "\(text)")
            #expect(!lowered.contains("sync spend"), "\(text)")
        }
    }

    @Test func copyIsCleanText() {
        for text in everyText {
            #expect(!text.isEmpty)
            #expect(text == text.trimmingCharacters(in: .whitespacesAndNewlines), "\(text)")
            #expect(!text.contains("\u{2014}"), "\(text)")
            #expect(!text.contains("http"), "\(text)")
            // Bold markers come in pairs, so none shows up as literal stars.
            #expect(text.components(separatedBy: "**").count % 2 == 1, "\(text)")
        }
    }

    @Test func plainTextDropsTheBoldMarkers() {
        #expect(Tutorials.plain("Tap **Done** to save.") == "Tap Done to save.")
        for text in everyText {
            #expect(!Tutorials.plain(text).contains("*"), "\(text)")
        }
    }

    @Test func listRowTitlesFitOnOneLineAndSummariesStayShort() {
        for tutorial in Tutorials.all {
            #expect(tutorial.title.count <= 24, "\(tutorial.title)")
            // The summary is the footnote under the row: at most three
            // lines, as the reference's longest one is.
            #expect(tutorial.summary.count <= 150, "\(tutorial.summary)")
            #expect(tutorial.summary.hasSuffix("."), "\(tutorial.summary)")
            #expect(!tutorial.headline.isEmpty)
            #expect(!tutorial.intro.isEmpty)
        }
    }

    @Test func everyIllustrationIsDrawnExactlyOnce() {
        let used = Tutorials.all.flatMap(\.illustrations)
        #expect(Set(used) == Set(TutorialIllustration.allCases))
        #expect(used.count == TutorialIllustration.allCases.count)
    }

    @Test func illustrationsFollowTheWordsTheyPicture() {
        for tutorial in Tutorials.all {
            for section in tutorial.sections {
                guard let first = section.blocks.first else { continue }
                if case .illustration = first {
                    Issue.record("\(section.id) opens with an illustration")
                }
            }
        }
    }

    @Test func sectionsHaveUniqueAnchorsAndStartWithAHeading() {
        let tutorials = Tutorials.all
        for tutorial in tutorials {
            let ids = tutorial.sections.map(\.id)
            #expect(Set(ids).count == ids.count, "\(tutorial.id)")
            #expect(!ids.contains(Tutorials.endAnchor), "\(tutorial.id)")
            // Illustrations are scroll anchors too, by name.
            #expect(Set(ids).isDisjoint(with: TutorialIllustration.allCases.map(\.rawValue)), "\(tutorial.id)")
            #expect(tutorial.sections.first?.level == .section)
            for section in tutorial.sections {
                #expect(!section.blocks.isEmpty, "\(section.id)")
                #expect(tutorial.section(section.id) == section)
            }
        }
        #expect(Tutorials.tutorial(.addExpenseShortcut).section("nowhere") == nil)
    }

    @Test func stepNumbersRunOnThroughASection() throws {
        let section = try #require(Tutorials.tutorial(.walletAutomation).section("automation"))
        let starts = section.blocks.indices.compactMap { index -> Int? in
            guard case .steps = section.blocks[index] else { return nil }
            return section.firstStepNumber(ofBlockAt: index)
        }
        #expect(starts == [1, 3])

        let made = TutorialSection(id: "x", title: "X", blocks: [
            .paragraph("A"), .steps(["1", "2", "3"]), .illustration(.backTapSettings), .steps(["4"]),
        ])
        #expect(made.firstStepNumber(ofBlockAt: 0) == 1)
        #expect(made.firstStepNumber(ofBlockAt: 1) == 1)
        #expect(made.firstStepNumber(ofBlockAt: 3) == 4)
    }

    @Test func shortcutGuideFollowsTheArticleOrder() throws {
        let tutorial = Tutorials.tutorial(.addExpenseShortcut)
        #expect(tutorial.sections.map(\.title) == ["Create a Shortcut", "Assign the Shortcut", "Back Tap", "Control Center", "Closing Remarks"])
        #expect(tutorial.sections.map(\.level) == [.section, .section, .subsection, .subsection, .section])
        try expectInOrder(tutorial, [
            "**Shortcuts**", "**+**", "**Keaser**", "**Add Expense**",
            "**Payment Method**", "**Current Date**",
            "**Accessibility** > **Touch** > **Back Tap**", "**Double Tap**", "**Triple Tap**",
            "**Control Center**", "**Add a Control**", "**Run Shortcut**", "**Choose Icon**",
            "Action button",
        ])
    }

    @Test func walletGuideFollowsTheArticleOrder() throws {
        let tutorial = Tutorials.tutorial(.walletAutomation)
        try expectInOrder(tutorial, [
            "**Automation**", "**Wallet**", "**Run Immediately**", "**Create New Shortcut**",
            "**Add Expense**", "**Title**", "**Select Variable**", "**Merchant**", "**Amount**",
            "**Date**", "**Current Date**", "**Payment Method**", "**Category**", "**Smart Suggestions**",
            "**Confirm Expense Details**",
        ])
    }

    /// Each phrase appears in the tutorial's copy, after the one before it.
    private func expectInOrder(_ tutorial: Tutorial, _ phrases: [String], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let text = tutorial.text.joined(separator: "\n")
        var cursor = text.startIndex
        for phrase in phrases {
            let found = try #require(text.range(of: phrase, range: cursor..<text.endIndex), "\(phrase)", sourceLocation: sourceLocation)
            cursor = found.upperBound
        }
    }
}
