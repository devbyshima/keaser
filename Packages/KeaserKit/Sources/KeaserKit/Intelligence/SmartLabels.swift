import Foundation

/// Picks a category for an expense title with a language model. New
/// Expense and the intents only talk to this protocol, so they run, test and
/// screenshot without a model. The app's implementation is Apple
/// Intelligence's on-device model (KeaserIntelligence), never a cloud one.
@MainActor
public protocol CategoryModel: AnyObject, Sendable {
    /// True when asking can help right now: the device can run the model,
    /// Apple Intelligence is on, the model is downloaded and the language
    /// is supported.
    var isReady: Bool { get }

    /// Loads the model ahead of a request for `prompt`'s categories. Call
    /// only with a second or more to spare, such as when New Expense opens.
    func prewarm(_ prompt: CategoryPrompt)

    /// The category name the model chose for `title`: one of
    /// `prompt.choices` other than `CategoryPrompt.noMatch`. Nil when it
    /// chose none, is not ready, takes longer than `budget`, or fails.
    /// Never throws: every failure means "keep the history and word-rule
    /// guess".
    func category(for title: String, in prompt: CategoryPrompt, within budget: Duration) async -> String?
}

/// Smart Suggestions' guess for a title, shared by New Expense and the Add
/// Expense and Log Wallet Transaction intents: the person's history and the
/// word rules at once, and the model only for a title they do not know.
///
/// The category ranks history, then a word rule on a built-in category, then
/// the model, then a word rule on a category the person made (see
/// `SmartSuggester.guessLabels`). The payment method never comes from the
/// model.
@MainActor
public enum SmartLabels {
    /// How long New Expense holds its guess back for the model. Measured on
    /// a Mac: 0.9 s typical and 1.4 s slow once the model is loaded, which
    /// prewarming when the editor opens takes care of.
    public static let editorBudget = Duration.seconds(2)

    /// How long the shortcut and the Wallet automation wait for the model
    /// before asking for the category, or leaving it empty.
    public static let intentBudget = Duration.milliseconds(1500)

    /// The labels to fill in for `title`. Waits at most `budget` for the
    /// model; without it the result is exactly `SmartSuggester.guessLabels`.
    public static func guess(
        for title: String,
        in account: Account,
        excluding excludedID: UUID? = nil,
        model: (any CategoryModel)?,
        budget: Duration
    ) async -> SmartSuggester.LabelGuess {
        let name = await modelCategoryName(for: title, in: account, excluding: excludedID, model: model, budget: budget)
        return SmartSuggester.guessLabels(
            for: title,
            categories: account.categories,
            paymentMethods: account.paymentMethods,
            history: account.expenses,
            excluding: excludedID,
            modelCategoryID: CategoryPrompt.category(named: name, in: account.categories)
        )
    }

    /// The model's category name for `title`, asked only when `wantsModel`.
    /// For callers that merge it themselves, such as `ShortcutFlow`.
    public static func modelCategoryName(
        for title: String,
        in account: Account,
        excluding excludedID: UUID? = nil,
        model: (any CategoryModel)?,
        budget: Duration
    ) async -> String? {
        guard let model, wantsModel(model, for: title, in: account, excluding: excludedID),
              let prompt = CategoryPrompt(categories: account.categories)
        else { return nil }
        return await model.category(for: title, in: prompt, within: budget)
    }

    /// Whether asking `model` about `title` could change the guess: it is
    /// ready, and neither the history nor a word rule on a built-in category
    /// settles the category.
    public static func wantsModel(
        _ model: (any CategoryModel)?,
        for title: String,
        in account: Account,
        excluding excludedID: UUID? = nil
    ) -> Bool {
        guard let model, model.isReady else { return false }
        return SmartSuggester.wantsModelGuess(for: title, categories: account.categories, history: account.expenses, excluding: excludedID)
    }

    /// Loads the model for `account`'s categories, when it is ready.
    public static func prewarm(_ model: (any CategoryModel)?, for account: Account) {
        guard let model, model.isReady, let prompt = CategoryPrompt(categories: account.categories) else { return }
        model.prewarm(prompt)
    }
}

extension QuickLog {
    /// `walletExpense(merchant:amount:card:in:now:)`, with a category for a
    /// merchant not seen before: Smart Suggestions' guess, from the history
    /// and word rules at once and from the model within `budget`. Left
    /// empty when nothing knows the merchant or suggestions are off. The
    /// payment method still comes only from the card or the last expense.
    @MainActor
    public static func walletExpense(
        merchant: String,
        amount: Decimal,
        card: String?,
        in account: Account,
        suggestionsEnabled: Bool,
        model: (any CategoryModel)?,
        budget: Duration = SmartLabels.intentBudget,
        now: Date = .now
    ) async -> Expense {
        var expense = walletExpense(merchant: merchant, amount: amount, card: card, in: account, now: now)
        let named = !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if expense.categoryID == nil, suggestionsEnabled, named {
            expense.categoryID = await SmartLabels.guess(for: expense.title, in: account, model: model, budget: budget).categoryID
        }
        return expense
    }
}
