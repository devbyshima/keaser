import Foundation
import Testing
@testable import KeaserKit

/// A stand-in for the on-device receipt model: answers `answer` after
/// `delay`, within the caller's budget, and records what it was asked.
@MainActor
final class FakeReceiptModel: ReceiptModel {
    var isReady = true
    var answer: ReceiptModelAnswer?
    var delay: Duration
    private(set) var prompts: [String] = []
    private(set) var prewarms = 0

    init(_ answer: ReceiptModelAnswer?, delay: Duration = .zero) {
        self.answer = answer
        self.delay = delay
    }

    func prewarm() {
        prewarms += 1
    }

    func read(_ prompt: String, within budget: Duration) async -> ReceiptModelAnswer? {
        prompts.append(prompt)
        return await Deadline.value(within: budget) { [delay, answer] in
            try? await Task.sleep(for: delay)
            return answer
        }
    }
}

/// Checking the model's reading against the receipt's text, and merging it
/// with the heuristics.
@MainActor
struct IntelligenceReceiptReadingTests {
    private let today = ReceiptSamples.today
    private let paris = ReceiptSamples.named("cafe-paris")!
    private let grocery = ReceiptSamples.named("grocery")!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> ReceiptDay {
        ReceiptDay(year: year, month: month, day: day)!
    }

    // MARK: Checks

    @Test func keepsAnswersTheTextBacksUp() {
        let answer = ReceiptModelAnswer(merchant: "Café de Flore", total: "14,50 €", year: 2026, month: 4, day: 3, currency: "EUR")
        #expect(ReceiptReading.checked(answer, lines: paris.lines, today: today)
            == ReceiptDraft(merchant: "Café de Flore", total: 14.5, day: day(2026, 4, 3), currencyCode: "EUR"))
    }

    @Test func dropsATotalThatIsNotPrinted() {
        // A blank photo once came back with a total of 15.00.
        #expect(ReceiptReading.total("15.00", in: grocery.lines) == nil)
        #expect(ReceiptReading.total("-12.50", in: grocery.lines) == nil)
        #expect(ReceiptReading.total("twelve", in: grocery.lines) == nil)
        #expect(ReceiptReading.total("12.5", in: grocery.lines) == Decimal(string: "12.50"))
        #expect(ReceiptReading.total("$12.50", in: grocery.lines) == Decimal(string: "12.50"))
        #expect(ReceiptReading.total("6300", in: ReceiptSamples.named("supermarket-kigali")!.lines) == 6300)
    }

    @Test func dropsADateThatIsNotPrintedOrIsInTheFuture() {
        func check(_ year: Int, _ month: Int, _ dayOfMonth: Int, _ lines: [String]) -> ReceiptDay? {
            ReceiptReading.day(ReceiptModelAnswer(year: year, month: month, day: dayOfMonth), in: lines, today: today)
        }
        #expect(check(2026, 9, 21, grocery.lines) == day(2026, 9, 21))
        #expect(check(2026, 9, 27, grocery.lines) == nil)
        // Either reading of "03/04/2026" is printed; the model may settle it.
        #expect(check(2026, 4, 3, ["03/04/2026"]) == day(2026, 4, 3))
        #expect(check(2026, 3, 4, ["03/04/2026"]) == day(2026, 3, 4))
        #expect(check(2026, 11, 24, ["Return by 11/24/2026"]) == nil)
        #expect(check(2026, 2, 30, ["02/30/2026"]) == nil)
        #expect(ReceiptReading.day(ReceiptModelAnswer(year: 2026, month: 9), in: grocery.lines, today: today) == nil)
    }

    @Test func dropsANameThatIsNotPrinted() {
        #expect(ReceiptReading.merchant("TRADER JOE'S", in: grocery.lines) == "Trader Joe's")
        // A letter misread by text recognition, or words run together.
        #expect(ReceiptReading.merchant("Trader Joe's", in: ["TRADER JDE'S", "TOTAL 4.00"]) == "Trader Joe's")
        #expect(ReceiptReading.merchant("Trader Joe's", in: ["TRADERJOES", "TOTAL 4.00"]) == "Trader Joe's")
        #expect(ReceiptReading.merchant("Whole Foods", in: grocery.lines) == nil)
        #expect(ReceiptReading.merchant("Receipt", in: ["Receipt", "Total 4.00"]) == nil)
        #expect(ReceiptReading.merchant("12.50", in: grocery.lines) == nil)
        #expect(ReceiptReading.merchant(nil, in: grocery.lines) == nil)
    }

    @Test func dropsACurrencyTheReceiptDoesNotName() {
        #expect(ReceiptReading.currency("EUR", in: paris.lines) == "EUR")
        #expect(ReceiptReading.currency(" eur ", in: paris.lines) == "EUR")
        #expect(ReceiptReading.currency("FRW", in: ["3,000 Frw"]) == "RWF")
        // "$" could be any dollar: USD only when the receipt says so.
        #expect(ReceiptReading.currency("USD", in: grocery.lines) == nil)
        #expect(ReceiptReading.currency("GBP", in: paris.lines) == nil)
        #expect(ReceiptReading.currency("XYZ", in: ["XYZ 4.00"]) == nil)
    }

    @Test func eachDetailFallsBackToTheHeuristics() {
        let model = ReceiptDraft(merchant: "Trader Joe's", total: nil, day: day(2026, 9, 20), currencyCode: nil)
        let heuristic = ReceiptDraft(merchant: "Trader Joes", total: 12.5, day: day(2026, 9, 21), currencyCode: "USD")
        #expect(ReceiptReading.merged(model, over: heuristic)
            == ReceiptDraft(merchant: "Trader Joe's", total: 12.5, day: day(2026, 9, 20), currencyCode: "USD"))
    }

    // MARK: Reading

    @Test func theModelSettlesWhatTheHeuristicsCannot() async {
        // No currency and a decimal point: a US iPhone reads "03/04" as
        // March 4; the model, seeing "Merci", says April 3.
        let lines = ["Chez Marcel", "Total 18.00", "03/04/2026", "Merci"]
        let model = FakeReceiptModel(ReceiptModelAnswer(merchant: "Chez Marcel", total: "18.00", year: 2026, month: 4, day: 3))
        let withModel = await ReceiptReading.read(lines, model: model, today: today, prefersMonthFirst: true)
        let without = await ReceiptReading.read(lines, model: nil, today: today, prefersMonthFirst: true)
        #expect(withModel.day == day(2026, 4, 3))
        #expect(without.day == day(2026, 3, 4))
        #expect(model.prompts == [ReceiptPrompt.prompt(for: lines)!])
    }

    @Test func aMadeUpAnswerLeavesTheHeuristics() async {
        let model = FakeReceiptModel(ReceiptModelAnswer(merchant: "Whole Foods", total: "99.99", year: 2026, month: 1, day: 2, currency: "EUR"))
        let draft = await ReceiptReading.read(grocery.lines, model: model, today: today, prefersMonthFirst: true)
        #expect(draft == grocery.expected)
    }

    @Test func withoutHelpItIsExactlyTheHeuristics() async {
        let off = FakeReceiptModel(ReceiptModelAnswer(total: "0.54"))
        off.isReady = false
        let models: [FakeReceiptModel?] = [nil, off, FakeReceiptModel(ReceiptModelAnswer(total: "0.54"), delay: .seconds(5)), FakeReceiptModel(nil)]
        for model in models {
            let draft = await ReceiptReading.read(grocery.lines, model: model, budget: .milliseconds(100), today: today, prefersMonthFirst: true)
            #expect(draft == grocery.expected)
        }
        #expect(off.prompts.isEmpty)
    }

    @Test func blankTextNeverAsks() async {
        let model = FakeReceiptModel(ReceiptModelAnswer(merchant: "Anything", total: "15.00"))
        let draft = await ReceiptReading.read(["  ", ""], model: model, today: today, prefersMonthFirst: true)
        #expect(draft == ReceiptDraft())
        #expect(!draft.isReceipt)
        #expect(model.prompts.isEmpty)
    }

    // MARK: Prompt

    @Test func thePromptIsTheReceiptsText() {
        #expect(ReceiptPrompt.prompt(for: ["TOTAL  $12.50", "", "09/21/2026"]) == "The receipt's text:\nTOTAL $12.50\n09/21/2026")
        #expect(ReceiptPrompt.prompt(for: ["", " "]) == nil)
        #expect(!ReceiptPrompt.instructions.isEmpty)
    }

    @Test func aLongReceiptKeepsItsTopBottomTotalsAndDates() throws {
        let items = (1...100).map { "Item \($0) 1.00" }
        let lines = ["Costco Wholesale"] + items[0..<50] + ["Balance due 108.25", "09/21/2026"] + items[50...] + ["TOTAL 108.25"]
        let prompt = try #require(ReceiptPrompt.prompt(for: lines))
        let kept = prompt.split(separator: "\n").dropFirst().map(String.init)
        #expect(kept.count == ReceiptPrompt.headLines + 2 + ReceiptPrompt.tailLines)
        #expect(kept.first == "Costco Wholesale")
        #expect(kept.contains("Balance due 108.25") && kept.contains("09/21/2026"))
        #expect(kept.last == "TOTAL 108.25")
        #expect(!kept.contains("Item 30 1.00"))

        let long = String(repeating: "A", count: 200)
        #expect(ReceiptPrompt.prompt(for: [long])?.count == "The receipt's text:\n".count + ReceiptPrompt.maximumLineLength)
    }
}
