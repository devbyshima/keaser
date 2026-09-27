import Foundation
import FoundationModels
import KeaserKit

/// Smart Suggestions' category model: Apple Intelligence's on-device
/// language model, asked to pick one of the account's categories for a
/// title (see `CategoryPrompt`). Never Private Cloud Compute.
///
/// Each request gets its own session, so earlier titles cannot sway the
/// next one, with greedy sampling, so the same title gets the same answer on
/// a given model version. Answers are kept in memory for the session of the
/// app; once a title is saved, the person's history answers it instead.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class OnDeviceCategoryModel: CategoryModel {
    public static let shared = OnDeviceCategoryModel()

    /// Deterministic for a given model version; the answer is a few tokens.
    public static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 32)

    private let model = SystemLanguageModel.default
    /// A session loaded for a prompt prefix and not used yet.
    private var warmed: (prefix: String, session: LanguageModelSession)?
    /// Answers by `CategoryPrompt.cacheKey(for:)`, nil inside meaning it
    /// chose none; keys oldest first.
    private var cache: [String: String?] = [:]
    private var cacheOrder: [String] = []
    private static let cacheLimit = 64

    public init() {}

    public var isReady: Bool { AppleIntelligence.isReady }

    public func prewarm(_ prompt: CategoryPrompt) {
        guard isReady, warmed?.prefix != prompt.promptPrefix else { return }
        let session = Self.session(model)
        session.prewarm(promptPrefix: Prompt(prompt.promptPrefix))
        warmed = (prompt.promptPrefix, session)
    }

    public func category(for title: String, in prompt: CategoryPrompt, within budget: Duration) async -> String? {
        let key = prompt.cacheKey(for: title)
        if let cached = cache[key] { return cached }
        guard isReady else { return nil }
        let session: LanguageModelSession
        if let warmed, warmed.prefix == prompt.promptPrefix {
            session = warmed.session
            self.warmed = nil
        } else {
            session = Self.session(model)
        }
        // Every failure (not ready after all, guardrails, rate limits in the
        // background, a cancelled wait) keeps the rule guess.
        let answer: String?? = await Deadline.value(within: budget) {
            try? await Self.answer(for: title, in: prompt, session: session)
        }
        guard let answer else { return nil }
        remember(answer, for: key)
        return answer
    }

    // MARK: One request

    /// A session with Keaser's instructions for one request.
    public static func session(_ model: SystemLanguageModel = .default) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: CategoryPrompt.instructions)
    }

    /// Asks once, without a cache or a time limit, and throws whatever the
    /// framework throws. The outer optional is nil for a blank title; the
    /// inner one for "none of these". Used by the evaluation too.
    public static func answer(for title: String, in prompt: CategoryPrompt, session: LanguageModelSession) async throws -> String?? {
        guard let text = prompt.prompt(for: title) else { return nil }
        let response = try await session.respond(to: text, schema: try schema(for: prompt), options: options)
        return .some(choice(in: response.content))
    }

    /// `{ "category": one of prompt.choices }`: constrained decoding keeps
    /// the answer to those strings.
    public static func schema(for prompt: CategoryPrompt) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(name: "ExpenseCategory", properties: [
            DynamicGenerationSchema.Property(
                name: "category",
                description: "The category the expense most likely belongs to",
                schema: DynamicGenerationSchema(name: "CategoryName", anyOf: prompt.choices)
            ),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The chosen category name; nil for "none of these" or a malformed answer.
    public static func choice(in content: GeneratedContent) -> String? {
        guard let value = try? content.value(String.self, forProperty: "category"),
              value != CategoryPrompt.noMatch
        else { return nil }
        return value
    }

    // MARK: Private

    private func remember(_ choice: String?, for key: String) {
        if cache.updateValue(choice, forKey: key) == nil { cacheOrder.append(key) }
        if cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
