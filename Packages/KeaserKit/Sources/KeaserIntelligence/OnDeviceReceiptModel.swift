import Foundation
import FoundationModels
import KeaserKit

/// Receipt scanning's model: Apple Intelligence's on-device language model,
/// asked to copy the merchant, total, date and currency out of a receipt's
/// text with guided generation. Never Private Cloud Compute.
///
/// What it answers is not trusted: `ReceiptReading` keeps a detail only
/// when the receipt's text backs it up, and falls back to the heuristics
/// otherwise. It never picks a category or a payment method.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class OnDeviceReceiptModel: ReceiptModel {
    public static let shared = OnDeviceReceiptModel()

    /// Deterministic for a given model version; the answer is a few dozen
    /// tokens.
    public static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 160)

    private let model = SystemLanguageModel.default
    /// A session loaded ahead of the request and not used yet.
    private var warmed: LanguageModelSession?

    public init() {}

    public var isReady: Bool { AppleIntelligence.isReady }

    public func prewarm() {
        guard isReady, warmed == nil else { return }
        let session = Self.session(model)
        session.prewarm(promptPrefix: Prompt(ReceiptPrompt.prefix))
        warmed = session
    }

    public func read(_ prompt: String, within budget: Duration) async -> ReceiptModelAnswer? {
        guard isReady else { return nil }
        let session = warmed ?? Self.session(model)
        warmed = nil
        // Every failure (not ready after all, guardrails, a context too
        // long, a cancelled wait) keeps the heuristics.
        return await Deadline.value(within: budget) {
            try? await Self.answer(to: prompt, session: session)
        }
    }

    // MARK: One request

    /// A session with Keaser's receipt instructions, for one request.
    public static func session(_ model: SystemLanguageModel = .default) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: ReceiptPrompt.instructions)
    }

    /// Asks once, without a time limit, and throws whatever the framework
    /// throws. Used by the evaluation too.
    public static func answer(to prompt: String, session: LanguageModelSession) async throws -> ReceiptModelAnswer {
        let fields = try await session.respond(to: prompt, generating: ReceiptFields.self, options: options).content
        return fields.answer
    }
}

/// The shape the model answers in. Guided generation keeps each detail to
/// its type, and a date's parts to real ranges; `ReceiptReading` checks the
/// rest against the text.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Details printed on a shop receipt")
struct ReceiptFields {
    @Guide(description: "The name of the shop, restaurant or business, usually on the first lines. Not an address, phone number or greeting.")
    var merchant: String?

    @Guide(description: "The final amount paid, tax and tip included, copied exactly as printed, such as 12.50 or 1.234,56. Not one item's price, the subtotal, a tax line, the cash handed over or the change.")
    var total: String?

    @Guide(description: "The date of the purchase. Receipts from outside the United States usually write the day before the month.")
    var date: PurchaseDate?

    @Guide(description: "The three-letter ISO 4217 code of the total's currency, such as USD, EUR or RWF, only when a currency symbol or code is printed.")
    var currency: String?

    var answer: ReceiptModelAnswer {
        ReceiptModelAnswer(merchant: merchant, total: total, year: date?.year, month: date?.month, day: date?.day, currency: currency)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A calendar date")
struct PurchaseDate {
    @Guide(description: "Four-digit year", .range(2000...2100))
    var year: Int

    @Guide(description: "Month, 1 to 12", .range(1...12))
    var month: Int

    @Guide(description: "Day of the month, 1 to 31", .range(1...31))
    var day: Int
}
