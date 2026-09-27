import Foundation
import FoundationModels
import KeaserIntelligence
import KeaserKit
import Testing

/// Measures Smart Suggestions' categories with the real on-device model, on
/// a fixed set of titles: the word rules and history alone, the model alone,
/// and what Keaser ships (`SmartLabels`). Greedy answers only hold for one
/// model version, so run it again after every prompt or ranking change and
/// every OS update.
///
///     scripts/eval.sh
///
/// Skipped unless KEASER_MODEL_EVALS=1; needs a Mac with Apple Intelligence on.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["KEASER_MODEL_EVALS"] == "1", "set KEASER_MODEL_EVALS=1 to run the on-device model"),
    .serialized
)
@MainActor
struct CategoryEvaluation {
    /// A title and the categories a person would accept for it. An empty
    /// name means leaving it empty is right too.
    struct Sample {
        let title: String
        let accepted: [String]

        init(_ title: String, _ accepted: String...) {
            self.title = title
            self.accepted = accepted
        }
    }

    static let defaultSet: [Sample] = [
        Sample("Uber to airport", "Transportation"), Sample("Watsons", "Health", "Shopping"),
        Sample("Netflix", "Entertainment"), Sample("Coffee with Sam", "Food & Drinks"),
        Sample("Starbucks", "Food & Drinks"), Sample("Shell", "Transportation"),
        Sample("7-Eleven", "Food & Drinks", "Shopping"), Sample("Uber Eats", "Food & Drinks"),
        Sample("Grab ride", "Transportation"), Sample("Spotify Premium", "Entertainment"),
        Sample("iCloud storage", "Services"), Sample("Electricity bill", "Services"),
        Sample("Water bill", "Services"), Sample("Gas bill", "Services"),
        Sample("Haircut", "Services"), Sample("Dentist", "Health"),
        Sample("Gym membership", "Health"), Sample("Ibuprofen", "Health"),
        Sample("Airbnb Lisbon", "Travel"), Sample("Hotel in Tokyo", "Travel"),
        Sample("Flight to Manila", "Travel"), Sample("Train ticket", "Transportation", "Travel"),
        Sample("Parking", "Transportation"), Sample("IKEA", "Shopping"),
        Sample("Zara", "Shopping"), Sample("Amazon order", "Shopping"),
        Sample("Nike shoes", "Shopping"), Sample("Birthday gift for mom", "Shopping"),
        Sample("Movie tickets", "Entertainment"), Sample("Concert", "Entertainment"),
        Sample("Steam game", "Entertainment"), Sample("McDonald's", "Food & Drinks"),
        Sample("Groceries at Whole Foods", "Food & Drinks"), Sample("Beer with friends", "Food & Drinks"),
        Sample("Laundry", "Services"), Sample("Car wash", "Transportation", "Services"),
        Sample("Phone plan", "Services"), Sample("Pharmacy", "Health"),
        Sample("Bus fare", "Transportation"), Sample("Museum entry", "Entertainment", "Travel"),
        Sample("Plumber", "Services"), Sample("Rent", "", "Services"),
        Sample("Zxqv", ""), Sample("Condoms", "Health", "Shopping"),
        Sample("Lottery ticket", "Entertainment"), Sample("Jollibee", "Food & Drinks"),
        Sample("Petron", "Transportation"), Sample("Mercury Drug", "Health"),
        Sample("Toll fee", "Transportation"), Sample("Street food", "Food & Drinks"),
    ]

    static let customNames = ["Eating Out", "Groceries", "Kids", "Car", "Home", "Fun", "Subscriptions", "Pets"]
    static let customSet: [Sample] = [
        Sample("Diapers", "Kids"), Sample("Netflix", "Subscriptions"), Sample("Trader Joe's", "Groceries"),
        Sample("Chipotle", "Eating Out"), Sample("Oil change", "Car"), Sample("Lightbulbs", "Home"),
        Sample("Dog food", "Pets"), Sample("Bowling night", "Fun"), Sample("School shoes", "Kids"),
        Sample("Spotify", "Subscriptions"), Sample("Costco", "Groceries"), Sample("Vet", "Pets"),
    ]

    @Test func defaultCategories() async throws {
        let result = try await evaluate("Default categories, new account", Self.defaultSet, in: Account(name: "Personal"))
        #expect(result.shipped >= 45, "shipped \(result.shipped)/\(Self.defaultSet.count)")
        #expect(result.errors == 0)
    }

    @Test func customCategories() async throws {
        let account = Account(name: "Family", categories: Self.customNames.map { ExpenseCategory(name: $0, symbol: "tag") })
        let result = try await evaluate("Custom categories, new account", Self.customSet, in: account)
        #expect(result.shipped >= 10, "shipped \(result.shipped)/\(Self.customSet.count)")
        #expect(result.errors == 0)
    }

    // MARK: Running

    struct Result {
        var rules = 0
        var model = 0
        var shipped = 0
        var asked = 0
        var errors = 0
    }

    private func evaluate(_ name: String, _ samples: [Sample], in account: Account) async throws -> Result {
        guard #available(macOS 26.0, *) else {
            Issue.record("Foundation Models needs macOS 26 or later")
            return Result()
        }
        try #require(AppleIntelligence.isReady, "Apple Intelligence is not ready on this Mac")
        let prompt = try #require(CategoryPrompt(categories: account.categories))
        let shipped = OnDeviceCategoryModel()
        let names = Dictionary(uniqueKeysWithValues: account.categories.map { ($0.id, $0.name) })

        // The first request after the model idles loads it (3 to 9 s here).
        _ = try? await OnDeviceCategoryModel.answer(for: "Warm up", in: prompt, session: OnDeviceCategoryModel.session())

        var result = Result()
        var times: [Duration] = []
        var lines: [String] = []
        for sample in samples {
            let rules = SmartSuggester.guessLabels(
                for: sample.title, categories: account.categories, paymentMethods: account.paymentMethods, history: account.expenses
            ).categoryID.flatMap { names[$0] } ?? ""

            var alone = ""
            do {
                let answer = try await OnDeviceCategoryModel.answer(for: sample.title, in: prompt, session: OnDeviceCategoryModel.session())
                alone = (answer ?? nil) ?? ""
            } catch {
                result.errors += 1
                alone = "error: \(type(of: error))"
            }

            let asks = SmartLabels.wantsModel(shipped, for: sample.title, in: account)
            let start = ContinuousClock.now
            let guess = await SmartLabels.guess(for: sample.title, in: account, model: shipped, budget: .seconds(10))
            if asks {
                result.asked += 1
                times.append(ContinuousClock.now - start)
            }
            let final = guess.categoryID.flatMap { names[$0] } ?? ""

            func mark(_ value: String) -> String {
                (value.isEmpty ? "-" : value) + (sample.accepted.contains(value) ? "" : " X")
            }
            if sample.accepted.contains(rules) { result.rules += 1 }
            if sample.accepted.contains(alone) { result.model += 1 }
            if sample.accepted.contains(final) { result.shipped += 1 }
            lines.append([
                sample.title.padding(toLength: 26, withPad: " ", startingAt: 0),
                (asks ? "asks" : "    "),
                "rules " + mark(rules).padding(toLength: 18, withPad: " ", startingAt: 0),
                "model " + mark(alone).padding(toLength: 18, withPad: " ", startingAt: 0),
                "shipped " + mark(final),
            ].joined(separator: " "))
        }

        let sorted = times.sorted()
        func seconds(_ duration: Duration?) -> String {
            guard let duration else { return "-" }
            return String(format: "%.2fs", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
        var variant = ""
        if #available(macOS 27.0, *) { variant = SystemLanguageModel.default.variant.displayName + ", " }
        print("""

        === \(name) (\(samples.count) titles; \(variant)greedy) ===
        \(lines.joined(separator: "\n"))
        right: rules and history \(result.rules)/\(samples.count), model alone \(result.model)/\(samples.count), \
        shipped \(result.shipped)/\(samples.count); model asked for \(result.asked)/\(samples.count); errors \(result.errors)
        shipped latency when asked: p50 \(seconds(sorted.isEmpty ? nil : sorted[sorted.count / 2])), \
        p90 \(seconds(sorted.isEmpty ? nil : sorted[Int(Double(sorted.count - 1) * 0.9)])), max \(seconds(sorted.last))
        """)
        return result
    }
}
