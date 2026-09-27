import CoreGraphics
import Foundation
import FoundationModels
import KeaserIntelligence
import KeaserKit
import Testing

/// Measures receipt scanning on the sample receipts (`ReceiptSamples`) with
/// the real on-device model: the heuristics alone, the model alone (its
/// checked answers), and what Keaser ships, first on the receipts' text and
/// then on images of them read with Vision, the whole path a photo takes.
///
///     scripts/eval.sh
///
/// Skipped unless KEASER_MODEL_EVALS=1; needs a Mac with Apple Intelligence on.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["KEASER_MODEL_EVALS"] == "1", "set KEASER_MODEL_EVALS=1 to run the on-device model"),
    .serialized
)
@MainActor
struct ReceiptEvaluation {
    /// Four details per receipt: merchant, total, day, currency.
    struct Score {
        var right = 0
        var total = 0

        mutating func add(_ draft: ReceiptDraft, _ expected: ReceiptDraft) -> String {
            let checks = ReceiptEvaluation.checks(draft, expected)
            right += checks.filter { $0 }.count
            total += checks.count
            return zip(["m", "t", "d", "c"], checks).map { $0.1 ? $0.0 : "X" }.joined()
        }

        var text: String { "\(right)/\(total)" }
    }

    nonisolated static func checks(_ draft: ReceiptDraft, _ expected: ReceiptDraft) -> [Bool] {
        let merchant = draft.merchant?.lowercased() == expected.merchant?.lowercased()
        return [merchant, draft.total == expected.total, draft.day == expected.day, draft.currencyCode == expected.currencyCode]
    }

    /// Receipts the heuristics get wrong by design, to show what the model
    /// adds: a slogan above the name, a total label misread by text
    /// recognition, and a French receipt in dollars' notation whose date a
    /// US iPhone would read month first.
    static let hardSamples: [(name: String, lines: [String], expected: ReceiptDraft)] = [
        ("slogan", [
            "Save money. Live better.", "Walmart", "Supercenter", "(650) 555-0199", "MILK 3.48", "EGGS 4.12",
            "SUBTOTAL 7.60", "TAX 0.00", "TOTAL 7.60", "DEBIT TEND 7.60", "CHANGE DUE 0.00", "09/26/26 18:44:03",
        ], ReceiptDraft(merchant: "Walmart Supercenter", total: Decimal(string: "7.60"), day: ReceiptDay(year: 2026, month: 9, day: 26))),
        ("misread-total", [
            "QUICK MART", "Soda 1.99", "Chips 2.49", "T0TAL 4.48", "CASH TEND 10.00", "CHNGE 5.52", "09/25/2026",
        ], ReceiptDraft(merchant: "Quick Mart", total: Decimal(string: "4.48"), day: ReceiptDay(year: 2026, month: 9, day: 25))),
        ("boulangerie", [
            "Boulangerie Paul", "Pain au chocolat 1.40", "Baguette 1.10", "Total 2.50", "05/08/2026", "Merci et à bientôt",
        ], ReceiptDraft(merchant: "Boulangerie Paul", total: Decimal(string: "2.50"), day: ReceiptDay(year: 2026, month: 8, day: 5))),
    ]

    @Test func readsTheHardReceipts() async throws {
        guard #available(macOS 26.0, *) else {
            Issue.record("Foundation Models needs macOS 26 or later")
            return
        }
        try #require(AppleIntelligence.isReady, "Apple Intelligence is not ready on this Mac")
        let today = ReceiptSamples.today
        let shipped = OnDeviceReceiptModel()
        _ = try? await OnDeviceReceiptModel.answer(to: ReceiptPrompt.prefix + "TOTAL 1.00", session: OnDeviceReceiptModel.session())
        var heuristics = Score(), text = Score()
        var rows: [String] = []
        for sample in Self.hardSamples {
            let rules = ReceiptParser.draft(from: sample.lines, today: today, prefersMonthFirst: true)
            let final = await ReceiptReading.read(sample.lines, model: shipped, budget: .seconds(20), today: today, prefersMonthFirst: true)
            rows.append([
                sample.name.padding(toLength: 22, withPad: " ", startingAt: 0),
                "rules " + heuristics.add(rules, sample.expected),
                "shipped " + text.add(final, sample.expected),
                "rules " + describe(rules), "shipped " + describe(final),
            ].joined(separator: "  "))
        }
        print("""

        === Hard receipts (\(Self.hardSamples.count), what the model adds) ===
        \(rows.joined(separator: "\n"))
        right: heuristics \(heuristics.text), shipped \(text.text)
        """)
        #expect(text.right >= heuristics.right)
    }

    @Test func readsTheSampleReceipts() async throws {
        guard #available(macOS 26.0, *) else {
            Issue.record("Foundation Models needs macOS 26 or later")
            return
        }
        try #require(AppleIntelligence.isReady, "Apple Intelligence is not ready on this Mac")
        let today = ReceiptSamples.today
        let shipped = OnDeviceReceiptModel()

        // The first request after the model idles loads it.
        _ = try? await OnDeviceReceiptModel.answer(to: ReceiptPrompt.prefix + "TOTAL 1.00", session: OnDeviceReceiptModel.session())

        var heuristics = Score(), alone = Score(), text = Score(), visionHeuristics = Score(), vision = Score()
        var errors = 0
        var times: [Duration] = []
        var visionTimes: [Duration] = []
        var rows: [String] = []
        for sample in ReceiptSamples.all {
            let expected = sample.expected
            let rules = ReceiptParser.draft(from: sample.lines, today: today, prefersMonthFirst: true)

            var checked = ReceiptDraft()
            do {
                let answer = try await OnDeviceReceiptModel.answer(to: ReceiptPrompt.prompt(for: sample.lines) ?? "", session: OnDeviceReceiptModel.session())
                checked = ReceiptReading.checked(answer, lines: sample.lines, today: today)
            } catch {
                errors += 1
            }

            var start = ContinuousClock.now
            let final = await ReceiptReading.read(sample.lines, model: shipped, budget: .seconds(20), today: today, prefersMonthFirst: true)
            times.append(ContinuousClock.now - start)

            // The same receipt printed on an image and read back with Vision.
            let image = try #require(ReceiptImageRenderer.image(of: sample.lines))
            start = ContinuousClock.now
            let recognized = await ReceiptTextRecognizer.lines(in: [image])
            visionTimes.append(ContinuousClock.now - start)
            let seenRules = ReceiptParser.draft(from: recognized, today: today, prefersMonthFirst: true)
            let seen = await ReceiptReading.read(recognized, model: shipped, budget: .seconds(20), today: today, prefersMonthFirst: true)

            rows.append([
                sample.name.padding(toLength: 22, withPad: " ", startingAt: 0),
                "rules " + heuristics.add(rules, expected),
                "model " + alone.add(checked, expected),
                "shipped " + text.add(final, expected),
                "| vision rules " + visionHeuristics.add(seenRules, expected),
                "vision shipped " + vision.add(seen, expected),
                describe(final),
            ].joined(separator: "  "))
            for (label, draft) in [("text", final), ("vision", seen)] where !Self.checks(draft, expected).allSatisfy({ $0 }) {
                rows.append("    \(label): \(describe(draft)) expected \(describe(expected))")
            }
        }

        func seconds(_ list: [Duration], _ quantile: Double) -> String {
            let sorted = list.sorted()
            guard !sorted.isEmpty else { return "-" }
            let duration = sorted[Int(Double(sorted.count - 1) * quantile)]
            return String(format: "%.2fs", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
        var variant = ""
        if #available(macOS 27.0, *) { variant = SystemLanguageModel.default.variant.displayName + ", " }
        print("""

        === Receipts (\(ReceiptSamples.all.count) samples, 4 details each; \(variant)greedy) ===
        m t d c = merchant, total, day, currency; X = wrong
        \(rows.joined(separator: "\n"))
        right on the text: heuristics \(heuristics.text), model alone \(alone.text), shipped \(text.text); errors \(errors)
        right through Vision: heuristics \(visionHeuristics.text), shipped \(vision.text)
        model latency (text read): p50 \(seconds(times, 0.5)), p90 \(seconds(times, 0.9)), max \(seconds(times, 1))
        Vision text recognition: p50 \(seconds(visionTimes, 0.5)), p90 \(seconds(visionTimes, 0.9)), max \(seconds(visionTimes, 1))
        """)
        #expect(errors == 0)
        #expect(text.right >= heuristics.right, "the model must never make receipts worse")
        #expect(vision.right >= visionHeuristics.right, "the model must never make receipts worse")
        #expect(vision.right * 10 >= vision.total * 9, "shipped through Vision \(vision.text)")
    }

    private func describe(_ draft: ReceiptDraft) -> String {
        let total = draft.total.map { "\($0)" } ?? "-"
        return "[\(draft.merchant ?? "-") | \(total) | \(draft.day?.description ?? "-") | \(draft.currencyCode ?? "-")]"
    }
}
