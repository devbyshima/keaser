import Foundation
import FoundationModels
import KeaserIntelligence
import KeaserKit
import Testing

/// The model wrapper's own logic, without asking the model: the schema it
/// sends, how it reads an answer, and that it never waits past its budget.
/// Each test needs macOS 26 or later, where Foundation Models exists.
@MainActor
struct OnDeviceCategoryModelTests {
    private let prompt = CategoryPrompt(categories: ExpenseCategory.defaults())!

    @Test func theSchemaOffersOnlyTheChoices() throws {
        guard #available(macOS 26.0, *) else { return }
        let schema = try OnDeviceCategoryModel.schema(for: prompt)
        let json = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
        for choice in prompt.choices {
            #expect(json.contains("\"\(choice)\""))
        }
        #expect(json.contains("\"category\""))
    }

    @Test func answersAreReadFromTheCategoryProperty() {
        guard #available(macOS 26.0, *) else { return }
        #expect(OnDeviceCategoryModel.choice(in: GeneratedContent(properties: ["category": "Health"])) == "Health")
        #expect(OnDeviceCategoryModel.choice(in: GeneratedContent(properties: ["category": CategoryPrompt.noMatch])) == nil)
        #expect(OnDeviceCategoryModel.choice(in: GeneratedContent(properties: ["other": "Health"])) == nil)
    }

    @Test func itIsGreedyAndShort() {
        guard #available(macOS 26.0, *) else { return }
        #expect(OnDeviceCategoryModel.options.samplingMode == .greedy)
        #expect(OnDeviceCategoryModel.options.maximumResponseTokens == 32)
    }

    @Test func noTimeOrNoTitleMeansNoAnswer() async {
        guard #available(macOS 26.0, *) else { return }
        let model = OnDeviceCategoryModel()
        #expect(await model.category(for: "Watsons", in: prompt, within: .zero) == nil)
        let start = ContinuousClock.now
        #expect(await model.category(for: "   ", in: prompt, within: .milliseconds(200)) == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func availabilityIsConsistent() {
        guard #available(macOS 26.0, *) else {
            #expect(!AppleIntelligence.isDeviceEligible && !AppleIntelligence.isReady && AppleIntelligence.categoryModel == nil)
            return
        }
        // Ready implies eligible, whatever this Mac has turned on.
        #expect(!AppleIntelligence.isReady || AppleIntelligence.isDeviceEligible)
        #expect(AppleIntelligence.categoryModel != nil)
        #expect(OnDeviceCategoryModel.shared.isReady == AppleIntelligence.isReady)
    }
}
