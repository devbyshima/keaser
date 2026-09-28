import Foundation

/// A guide under Settings > Tutorials, laid out as a short article: a
/// headline and an intro, then sections of paragraphs, numbered steps, notes
/// and illustrations. The app renders it; nothing here knows about views.
///
/// Copy marks the names of things to tap with `**bold**` (inline Markdown).
/// `Tutorials.plain(_:)` strips the markers.
public struct Tutorial: Identifiable, Hashable, Sendable {
    public enum ID: String, CaseIterable, Hashable, Sendable {
        case addExpenseShortcut
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
    /// The Shortcuts search finding Keaser's Add Expense action, and the
    /// action once added, with its Title and Amount fields.
    case actionSearch
    /// The Add Expense action opened up, with a payment method and the
    /// current date filled in.
    case prefilledAction
    /// Settings > Accessibility > Touch > Back Tap, then a shortcut picked
    /// under Double Tap.
    case backTapSettings
    /// Control Center in edit mode with Add a Control, then the Run Shortcut
    /// control found in the gallery.
    case addControl
    /// The Run Shortcut control at one, two and four slots.
    case controlSizes
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

    /// Every field of the action, in the order the tutorials draw them.
    public static let addExpenseFieldTitles = [
        titleFieldTitle, amountFieldTitle, categoryFieldTitle,
        paymentMethodFieldTitle, accountFieldTitle, dateFieldTitle,
    ]

    /// Opens the Shortcuts app, from the button at the end of each tutorial.
    public static let shortcutsURL = URL(string: "shortcuts://")!

    /// The scroll anchor of that button; no section or illustration may
    /// take this id.
    public static let endAnchor = "end"

    public static let all: [Tutorial] = [addExpenseShortcut, walletAutomation]

    public static func tutorial(_ id: Tutorial.ID) -> Tutorial {
        switch id {
        case .addExpenseShortcut: addExpenseShortcut
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
    private static let accountField = accountFieldTitle
    private static let dateField = dateFieldTitle

    static let addExpenseShortcut = Tutorial(
        id: .addExpenseShortcut,
        title: "Add Expense Shortcut",
        summary: "Set up a Shortcut that lets you quickly log an expense from anywhere on your device.",
        symbol: "command",
        headline: "Add Expenses with a Shortcut",
        intro: "Keaser gives the Shortcuts app an **\(action)** action. Put it in a shortcut and you can run it from the Lock Screen, Control Center or the back of your iPhone, and log a purchase without opening any app.",
        sections: [
            TutorialSection(id: "create", title: "Create a Shortcut", blocks: [
                .paragraph("You only need to do this once."),
                .steps([
                    "Open the **Shortcuts** app and tap **+** in the top right corner to start a new shortcut.",
                    "Search for **Keaser**, then tap **\(action)** to add the action.",
                ]),
                .illustration(.actionSearch),
                .paragraph("That is all it takes. The action works as it is, and asks for what it needs each time it runs."),
                .note(TutorialNote(
                    symbol: "slider.horizontal.3",
                    title: "Prefill What Stays the Same",
                    text: "If you like, tap the arrow on the action to see all of its fields and fill some in. Set **\(paymentField)** to the method you always use, or **\(dateField)** to **Current Date** so each expense is dated the moment you log it. With more than one account, **\(accountField)** picks where it goes."
                )),
                .illustration(.prefilledAction),
            ]),
            TutorialSection(id: "assign", title: "Assign the Shortcut", blocks: [
                .paragraph("Next, give the shortcut a home, so it is only a tap or a swipe away when you have just paid for something. Two places work especially well."),
            ]),
            TutorialSection(id: "backTap", level: .subsection, title: "Back Tap", blocks: [
                .paragraph("Back Tap runs the shortcut when you tap the back of your iPhone two or three times in a row."),
                .steps([
                    "Open the **Settings** app and go to **Accessibility** > **Touch** > **Back Tap**.",
                    "Choose **Double Tap** or **Triple Tap**.",
                    "Scroll down to the **Shortcuts** section and select your shortcut.",
                ]),
                .illustration(.backTapSettings),
            ]),
            TutorialSection(id: "controlCenter", level: .subsection, title: "Control Center", blocks: [
                .paragraph("A control puts the shortcut one swipe away, whatever is on the screen."),
                .steps([
                    "Swipe down from the top right corner of the screen to open **Control Center**.",
                    "Tap **+** in the top left corner, then tap **Add a Control** at the bottom.",
                    "Search for **Shortcut** and add the **Run Shortcut** control.",
                    "Pick your shortcut from the list. Searching for its name, or for **Keaser**, finds it quickly.",
                ]),
                .illustration(.addControl),
                .note(TutorialNote(
                    symbol: "paintbrush.pointed.fill",
                    title: "Choose Your Own Icon",
                    text: "The control starts out with an app icon. To give it another, open the shortcut in the Shortcuts app, tap the arrow next to its name and choose **Choose Icon**."
                )),
                .paragraph("While Control Center is in edit mode, drag the handle on the corner of the control to resize it. It can take one slot, two side by side, or a square of four."),
                .illustration(.controlSizes),
            ]),
            TutorialSection(id: "closing", title: "Closing Remarks", blocks: [
                .paragraph("We suggest Back Tap and Control Center because few people have anything there yet, so the shortcut is unlikely to push something else out of the way."),
                .paragraph("They are not the only places a shortcut can run from. You can also add it to the Lock Screen as a control, or put it on the Action button of an iPhone that has one."),
                .note(TutorialNote(
                    symbol: "plus.circle.fill",
                    title: "Quickest of All: Keaser's Control",
                    text: "Keaser comes with its own **\(action)** control for Control Center, the Lock Screen and the Action button. It asks the same questions as the shortcut, right where you tap it, with no shortcut to build."
                )),
            ]),
        ]
    )

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
