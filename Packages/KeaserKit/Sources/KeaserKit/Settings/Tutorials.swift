import Foundation

/// A guide under Settings > Tutorials, laid out as a short article: a
/// headline and an intro, then sections of paragraphs, numbered steps, notes
/// and illustrations. The app renders it; nothing here knows about views.
///
/// Copy marks the names of things to tap with `**bold**` (inline Markdown).
/// `Tutorials.plain(_:)` strips the markers.
public struct Tutorial: Identifiable, Hashable, Sendable {
    public enum ID: String, CaseIterable, Hashable, Sendable {
        case walletAutomation
    }

    public let id: ID
    /// The row in the Tutorials list, and the page's navigation title.
    public let title: String
    /// The footnote under the row in the Tutorials list.
    public let summary: String
    public let symbol: String
    /// The large title at the top of the article.
    public let headline: String
    public let intro: String
    public let sections: [TutorialSection]

    public init(id: ID, title: String, summary: String, symbol: String, headline: String, intro: String, sections: [TutorialSection]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.headline = headline
        self.intro = intro
        self.sections = sections
    }

    /// The section with this id (a scroll anchor), if there is one.
    public func section(_ id: String) -> TutorialSection? {
        sections.first { $0.id == id }
    }

    /// Every illustration, in reading order.
    public var illustrations: [TutorialIllustration] {
        sections.flatMap(\.blocks).compactMap {
            if case .illustration(let illustration) = $0 { illustration } else { nil }
        }
    }

    /// All of the copy, Markdown markers included, in reading order.
    public var text: [String] {
        var text = [title, summary, headline, intro]
        for section in sections {
            text.append(section.title)
            for block in section.blocks {
                switch block {
                case .paragraph(let paragraph): text.append(paragraph)
                case .steps(let steps): text += steps
                case .note(let note): text += [note.title, note.text]
                case .illustration: break
                }
            }
        }
        return text
    }
}

/// A heading and what follows it, up to the next heading.
public struct TutorialSection: Identifiable, Hashable, Sendable {
    public enum Level: Hashable, Sendable {
        /// A heading of its own.
        case section
        /// A sub-heading, part of the section before it.
        case subsection
    }

    /// A stable name, also the scroll anchor for screenshots.
    public let id: String
    public let level: Level
    public let title: String
    public let blocks: [TutorialBlock]

    public init(id: String, level: Level = .section, title: String, blocks: [TutorialBlock]) {
        self.id = id
        self.level = level
        self.title = title
        self.blocks = blocks
    }

    /// The number of the first step in the block at `index`. Numbering runs
    /// on through every step list of a section, so an illustration or a
    /// paragraph can sit between two steps without restarting the count.
    public func firstStepNumber(ofBlockAt index: Int) -> Int {
        var number = 1
        for block in blocks.prefix(index) {
            if case .steps(let steps) = block { number += steps.count }
        }
        return number
    }
}

public enum TutorialBlock: Hashable, Sendable {
    case paragraph(String)
    /// Numbered steps, a sentence or two each.
    case steps([String])
    /// A remark set apart from the steps: an optional extra, or another way.
    case note(TutorialNote)
    /// A drawing of the screen the steps around it describe. Decorative: the
    /// copy always says the same in words.
    case illustration(TutorialIllustration)
}

public struct TutorialNote: Hashable, Sendable {
    public let symbol: String
    public let title: String
    public let text: String

    public init(symbol: String, title: String, text: String) {
        self.symbol = symbol
        self.title = title
        self.text = text
    }
}

/// The schematic drawings the tutorials use. The app draws each one.
public enum TutorialIllustration: String, CaseIterable, Hashable, Sendable {
    /// The automation triggers, scrolled to Wallet.
    case walletTrigger
    /// The Wallet trigger's cards and categories, and Run Immediately.
    case walletOptions
    /// Title and Amount taken from the Shortcut Input's Merchant and Amount.
    case walletVariables
    /// The Date field set to the Current Date variable above the keyboard.
    case currentDate
    /// Keaser asking, as the automation runs, for the category left empty.
    case askForCategory
}

public enum Tutorials {
    /// Titles of Keaser's Add Expense action and its fields as the Shortcuts
    /// app shows them. They must match `AddExpenseIntent`'s title and
    /// parameter titles (see AGENTS.md, "Shared names").
    public static let addExpenseActionTitle = "Add Expense"
    public static let titleFieldTitle = "Title"
    public static let amountFieldTitle = "Amount"
    public static let categoryFieldTitle = "Category"
    public static let paymentMethodFieldTitle = "Payment Method"
    public static let accountFieldTitle = "Account"
    public static let dateFieldTitle = "Date"

    /// Opens the Shortcuts app, from the button at the end of each tutorial.
    public static let shortcutsURL = URL(string: "shortcuts://")!

    /// The scroll anchor of that button; no section or illustration may
    /// take this id.
    public static let endAnchor = "end"

    public static let all: [Tutorial] = [walletAutomation]

    public static func tutorial(_ id: Tutorial.ID) -> Tutorial {
        switch id {
        case .walletAutomation: walletAutomation
        }
    }

    /// `text` without the `**` bold markers.
    public static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }

    // Shorter names for the copy below.
    private static let action = addExpenseActionTitle
    private static let titleField = titleFieldTitle
    private static let amountField = amountFieldTitle
    private static let categoryField = categoryFieldTitle
    private static let paymentField = paymentMethodFieldTitle
    private static let dateField = dateFieldTitle

    static let walletAutomation = Tutorial(
        id: .walletAutomation,
        title: "Apple Wallet Automation",
        summary: "Set up a Shortcuts Automation that detects when you tap to pay with Apple Wallet and automatically passes transaction details to the shortcut.",
        symbol: "wave.3.right.circle.fill",
        headline: "Add Expenses as You Pay with Apple Wallet",
        intro: "A Shortcuts automation can run the moment you tap a card from Apple Wallet to pay. Give it Keaser's **\(action)** action and each purchase lands in Keaser with the merchant and the amount already filled in.",
        sections: [
            TutorialSection(id: "automation", title: "Create the Automation", blocks: [
                .steps([
                    "Open the **Shortcuts** app, go to the **Automation** tab and tap **+** in the top right corner.",
                    "Scroll down to **Wallet** and choose it as the trigger.",
                ]),
                .illustration(.walletTrigger),
                .steps([
                    "Select the cards that should start the automation, and the categories of purchase it should run for. Deselect any you want to leave out.",
                    "Choose **Run Immediately**, so it runs without asking you to confirm each time, then tap **Next**.",
                ]),
                .illustration(.walletOptions),
            ]),
            TutorialSection(id: "action", title: "Add Keaser's Action", blocks: [
                .paragraph("The automation hands each payment to its shortcut as the **Shortcut Input**. Keaser's action takes the merchant and the amount from there."),
                .steps([
                    "Tap **Create New Shortcut**.",
                    "Search for **\(action)** and tap Keaser's action to add it.",
                    "Tap the **\(titleField)** field, choose **Select Variable**, then **Shortcut Input**.",
                    "Tap the **Shortcut Input** variable you just placed and choose **Merchant**.",
                    "Do the same in the **\(amountField)** field: select **Shortcut Input**, tap it and choose **Amount**.",
                ]),
                .illustration(.walletVariables),
            ]),
            TutorialSection(id: "extras", title: "Optional Extras", blocks: [
                .paragraph("Because the automation runs while you pay, the right date is always the current one, so you can fill it in here once and for all."),
                .steps([
                    "Tap the arrow on the action to show the rest of its fields.",
                    "Tap **\(dateField)**, then choose the **Current Date** variable above the keyboard.",
                ]),
                .illustration(.currentDate),
                .note(TutorialNote(
                    symbol: "creditcard.fill",
                    title: "One Card, One Payment Method",
                    text: "If only one card starts the automation, set **\(paymentField)** to the method that matches it. The list shows the payment methods in your Keaser account, so add it in Keaser first if it is missing."
                )),
            ]),
            TutorialSection(id: "done", title: "All Set", blocks: [
                .paragraph("Tap **Done** to save the automation. From now on it runs each time you pay with one of the cards you chose."),
                .paragraph("Keaser only asks for what the shortcut leaves empty, such as the **\(categoryField)**. With **Smart Suggestions** on in Settings > Shortcut, it may already know the category from the merchant and fill it in for you."),
                .paragraph("Keaser also shows you the expense to check before adding it. To have it added straight away, turn off **Confirm Expense Details** in Settings > Shortcut."),
                .illustration(.askForCategory),
            ]),
        ]
    )
}
