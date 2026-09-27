import Foundation
import KeaserIntelligence
import KeaserKit

/// The category model New Expense and the intents use: Apple Intelligence's
/// on-device model on iOS 26 and later (see `AppleIntelligence`), nothing
/// before. In DEBUG, `-KeaserCategoryModel` puts a fixed one in its place so
/// screenshots do not depend on the Mac running the simulator.
@MainActor
enum CategoryModels {
    static var current: (any CategoryModel)? {
        #if DEBUG
        if let debug = DebugCategoryModel.shared { return debug.model }
        #endif
        return AppleIntelligence.categoryModel
    }

    /// Whether this iPhone can recognise titles with Apple Intelligence at
    /// all, even if it is turned off for now. Decides whether Smart
    /// Suggestions mentions it.
    static var isDeviceEligible: Bool {
        #if DEBUG
        if let debug = DebugCategoryModel.shared { return debug.model != nil }
        #endif
        return AppleIntelligence.isDeviceEligible
    }
}

#if DEBUG
/// `-KeaserCategoryModel <category name>` answers with that category about a
/// second after being asked, like the real model once loaded; `none` answers
/// "none of these"; `off` behaves like a device without Apple Intelligence.
@MainActor
private final class DebugCategoryModel {
    static let shared: DebugCategoryModel? = DebugLaunch.string("KeaserCategoryModel").map { DebugCategoryModel($0) }

    let model: FixedCategoryModel?

    private init(_ argument: String) {
        switch argument {
        case "off": model = nil
        case "none": model = FixedCategoryModel(answer: nil)
        default: model = FixedCategoryModel(answer: argument)
        }
    }
}

@MainActor
private final class FixedCategoryModel: CategoryModel {
    let answer: String?

    init(answer: String?) {
        self.answer = answer
    }

    var isReady: Bool { true }

    func prewarm(_ prompt: CategoryPrompt) {}

    func category(for title: String, in prompt: CategoryPrompt, within budget: Duration) async -> String? {
        await Deadline.value(within: budget) { [answer] in
            try? await Task.sleep(for: .milliseconds(900))
            return answer.flatMap { name in prompt.choices.first { $0.localizedCaseInsensitiveCompare(name) == .orderedSame } }
        }
    }
}
#endif
