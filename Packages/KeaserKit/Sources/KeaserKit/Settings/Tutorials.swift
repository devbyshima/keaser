import Foundation

/// A step-by-step guide shown under Settings > Tutorials.
public struct Tutorial: Identifiable, Hashable, Sendable {
    public enum ID: String, CaseIterable, Hashable, Sendable {
        case addExpenseShortcut
        case walletAutomation
    }

    public struct Step: Hashable, Sendable {
        public let title: String
        public let detail: String

        public init(_ title: String, _ detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public let id: ID
    public let title: String
    /// One line under the row in the Tutorials list.
    public let summary: String
    public let symbol: String
    public let intro: String
    public let steps: [Step]
    /// A closing remark under the steps, if any.
    public let note: String?
}

public enum Tutorials {
    /// Titles of Keaser's App Intents as they appear in the Shortcuts app.
    /// They must match the intents' titles (see AGENTS.md, "Shared names").
    public static let addExpenseActionTitle = "Add Expense"
    public static let walletActionTitle = "Log Wallet Transaction"

    public static let all: [Tutorial] = [addExpenseShortcut, walletAutomation]

    public static func tutorial(_ id: Tutorial.ID) -> Tutorial {
        switch id {
        case .addExpenseShortcut: addExpenseShortcut
        case .walletAutomation: walletAutomation
        }
    }

    static let addExpenseShortcut = Tutorial(
        id: .addExpenseShortcut,
        title: "Add Expense Shortcut",
        summary: "Make a Shortcut that logs an expense in a couple of taps, from anywhere on your iPhone.",
        symbol: "command",
        intro: "Keaser gives the Shortcuts app an \(addExpenseActionTitle) action. Run it and Keaser asks what the expense is about, how much it was and where to file it, one question at a time, without opening the app.",
        steps: [
            .init("Open Shortcuts", "In the Shortcuts app, tap + to start a new shortcut, then tap Add Action."),
            .init("Add Keaser's action", "Search for Keaser and choose \(addExpenseActionTitle)."),
            .init("Choose what it asks", "Leave the fields empty and Keaser asks for each in turn: the title, the amount, then the account, category and payment method. Fill some in for something you log often, like your morning coffee, and those are never asked."),
            .init("Name it", "Give the shortcut a short name you can say to Siri, then tap Done."),
            .init("Keep it close", "Run it from Siri, the Action button, a Home Screen icon or Back Tap (Settings > Accessibility > Touch > Back Tap). Keaser's own \(addExpenseActionTitle) control asks the same questions from Control Center or the Lock Screen."),
        ],
        note: "Keaser shows the expense for you to check before saving it; Settings > Shortcut can turn that off. Anything a shortcut logs can be edited later in Keaser, like any other expense."
    )

    static let walletAutomation = Tutorial(
        id: .walletAutomation,
        title: "Apple Wallet Automation",
        summary: "Log Apple Pay purchases automatically: a Shortcuts automation hands each payment to Keaser.",
        symbol: "wave.3.right.circle.fill",
        intro: "When you pay with Apple Pay, a Shortcuts automation can pass the merchant, amount and card to Keaser, so the expense is logged before you have put your phone away.",
        steps: [
            .init("Open Automation", "In the Shortcuts app, open the Automation tab and tap + to create a new automation."),
            .init("Choose Transaction", "Scroll to the Wallet section and pick Transaction."),
            .init("Pick your cards", "Select the Apple Pay cards to watch. Leave the other options as they are to catch every purchase."),
            .init("Run without asking", "Choose Run Immediately, then tap Next."),
            .init("Add Keaser's action", "Start a new blank shortcut, search for Keaser and add \(walletActionTitle)."),
            .init("Pass the details", "Tap each field of the action and choose from Shortcut Input: Merchant for Merchant, Amount for Amount and Card for Card."),
            .init("Save", "Tap Done. After your next Apple Pay purchase with those cards, Keaser adds the expense on its own and shows it on a Successfully added expense card."),
        ],
        note: "Wallet automations only run for Apple Pay payments made on this iPhone with the cards you selected."
    )
}
