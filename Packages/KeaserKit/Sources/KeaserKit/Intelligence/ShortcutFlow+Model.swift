import Foundation

// The Add Expense shortcut with the on-device model: the flow itself stays
// pure and synchronous, and these async steps ask the model just before a
// move that would guess the category of a title nothing else knows.

extension ShortcutFlow {
    /// What the model said about a title. A nil name means it chose none or
    /// did not answer in time; either way it is not asked again.
    struct ModelAnswer: Hashable, Sendable {
        var title: String
        var categoryName: String?
    }

    /// `start()`, first asking `model` for the category when this move
    /// guesses it for a title that neither the history nor the word rules
    /// know. Waits at most `budget`; without an answer the category is asked
    /// (or guessed) exactly as without a model. Loads the model early when
    /// the title may still need it.
    @MainActor
    public mutating func start(model: (any CategoryModel)?, budget: Duration) async -> Step? {
        if guessesCategory, title.isEmpty || SmartLabels.wantsModel(model, for: title, in: account) {
            SmartLabels.prewarm(model, for: account)
        }
        return await move(from: nil, model: model, budget: budget) { $0.start() }
    }

    /// `next(after:answer:)`, asking `model` first like `start(model:budget:)`.
    @MainActor
    public mutating func next(after step: Step, answer: Answer, model: (any CategoryModel)?, budget: Duration) async -> Step? {
        await move(from: step, model: model, budget: budget) { $0.next(after: step, answer: answer) }
    }

    /// Makes `transition` on a copy first. When that reaches or passes the
    /// category question with a guess the model could still change, asks the
    /// model, then makes the move for real with its answer.
    @MainActor
    private mutating func move(
        from step: Step?,
        model: (any CategoryModel)?,
        budget: Duration,
        _ transition: (inout ShortcutFlow) -> Step?
    ) async -> Step? {
        var probe = self
        let next = transition(&probe)
        let startsBeforeCategory = step.map { $0 < .category } ?? true
        let reachesCategory = next.map { $0 >= .category } ?? true
        guard startsBeforeCategory, reachesCategory, probe.guessesCategory, probe.modelAnswer?.title != probe.title,
              SmartLabels.wantsModel(model, for: probe.title, in: probe.account)
        else {
            self = probe
            return next
        }
        let name = await SmartLabels.modelCategoryName(for: probe.title, in: probe.account, model: model, budget: budget)
        modelAnswer = ModelAnswer(title: probe.title, categoryName: name)
        return transition(&self)
    }
}
