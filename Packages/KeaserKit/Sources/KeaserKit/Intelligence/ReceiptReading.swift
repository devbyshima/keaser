import Foundation

/// What a language model read on a receipt, exactly as it answered. None of
/// it is trusted: `ReceiptReading.checked` keeps only what the receipt's own
/// text backs up.
public struct ReceiptModelAnswer: Equatable, Sendable {
    public var merchant: String?
    /// The total as the model copied it ("14,50 €").
    public var total: String?
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var currency: String?

    public init(
        merchant: String? = nil,
        total: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        day: Int? = nil,
        currency: String? = nil
    ) {
        self.merchant = merchant
        self.total = total
        self.year = year
        self.month = month
        self.day = day
        self.currency = currency
    }
}

/// Reads the details of a receipt's text with a language model. Receipt
/// scanning only talks to this protocol, so it runs, tests and screenshots
/// without a model. The app's implementation is Apple Intelligence's
/// on-device model (KeaserIntelligence), never a cloud one.
@MainActor
public protocol ReceiptModel: AnyObject, Sendable {
    /// True when asking can help right now (see `CategoryModel.isReady`).
    var isReady: Bool { get }

    /// Loads the model ahead of a request, such as while the camera is open.
    func prewarm()

    /// The model's reading of `prompt` (see `ReceiptPrompt`). Nil when it
    /// is not ready, takes longer than `budget`, or fails. Never throws:
    /// every failure means "keep what the heuristics found".
    func read(_ prompt: String, within budget: Duration) async -> ReceiptModelAnswer?
}

/// What Keaser asks the model about a receipt. Pure, so the tests pin it.
public enum ReceiptPrompt {
    /// Instructions for every request. Constant, so the system can reuse them.
    public static let instructions = """
    You read the text of a shop receipt and copy out the details asked for. The text comes from \
    text recognition on a photo, top to bottom, so it may contain mistakes. Leave out any detail \
    the receipt does not show; never guess one.
    """

    /// What every request starts with, so the model can be prewarmed with it.
    public static let prefix = "The receipt's text:\n"

    /// A long receipt keeps its top and bottom, where the name, the total
    /// and the date are, and the lines in between that name a total or a
    /// date.
    static let headLines = 15
    static let tailLines = 40
    /// Longer lines are cut; item descriptions do not need more.
    static let maximumLineLength = 80

    /// The request for `lines`, or nil when there is no text to read.
    public static func prompt(for lines: [String]) -> String? {
        let lines = lines.map { String(ReceiptParser.oneLine($0).prefix(maximumLineLength)) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        var kept: [String]
        if lines.count <= headLines + tailLines {
            kept = lines
        } else {
            let middle = lines[headLines..<(lines.count - tailLines)].filter { line in
                ReceiptParser.totalRank(ReceiptParser.words(line)) != nil || !ReceiptParser.days(in: line, monthFirst: true).isEmpty
            }
            kept = Array(lines.prefix(headLines)) + middle + Array(lines.suffix(tailLines))
        }
        return prefix + kept.joined(separator: "\n")
    }
}

/// Receipt scanning's reading of the text: the heuristics always, and the
/// model when it is ready, each of its answers kept only when the text backs
/// it up. Nothing here saves anything; New Expense shows the result for the
/// person to check.
@MainActor
public enum ReceiptReading {
    /// How long the person waits for the model after the text is read.
    /// Measured on a Mac: about 1 to 2.5 seconds once loaded, which
    /// prewarming while the camera is open takes care of.
    public static let budget = Duration.seconds(6)

    /// The details of `lines`: the model's checked answers where it gave
    /// them, the heuristics everywhere else.
    public static func read(
        _ lines: [String],
        model: (any ReceiptModel)?,
        budget: Duration = ReceiptReading.budget,
        today: ReceiptDay,
        prefersMonthFirst: Bool
    ) async -> ReceiptDraft {
        let heuristic = ReceiptParser.reading(from: lines, today: today, prefersMonthFirst: prefersMonthFirst)
        guard let model, model.isReady, let prompt = ReceiptPrompt.prompt(for: lines),
              let answer = await model.read(prompt, within: budget)
        else { return heuristic.draft }
        return merged(checked(answer, lines: lines, today: today), over: heuristic)
    }

    /// A receipt photographed in pages, read as one: the lines of every
    /// page in order, top of the first to the bottom of the last, so a
    /// total at the foot of the last page is found under the shop's name
    /// on the first.
    public static func read(
        pages: [[String]],
        model: (any ReceiptModel)?,
        budget: Duration = ReceiptReading.budget,
        today: ReceiptDay,
        prefersMonthFirst: Bool
    ) async -> ReceiptDraft {
        await read(pages.flatMap { $0 }, model: model, budget: budget, today: today, prefersMonthFirst: prefersMonthFirst)
    }

    /// The model's checked details where the receipt did not settle them:
    ///
    /// - Merchant: the model's, which tells a shop's name from a slogan or
    ///   a heading better than "the first line that could be one".
    /// - Total: a line labelled as the total wins; otherwise the model's,
    ///   which reads labels in any language, then the largest price.
    /// - Day: a date only readable one way, or settled by the receipt's
    ///   currency or decimal commas, wins; otherwise the model's, which can
    ///   tell a French receipt's "03/04" from an American one's, then the
    ///   person's region.
    /// - Currency: the one printed most often next to the amounts, else the
    ///   model's (both are printed on the receipt), else the shared symbol
    ///   printed next to them.
    public static func merged(_ model: ReceiptDraft, over heuristic: ReceiptParser.Reading) -> ReceiptDraft {
        let rules = heuristic.draft
        return ReceiptDraft(
            merchant: model.merchant ?? rules.merchant,
            total: heuristic.totalIsLabelled ? rules.total : (model.total ?? rules.total),
            day: heuristic.dayIsSettled ? rules.day : (model.day ?? rules.day),
            currencyCode: rules.currencyCode ?? model.currencyCode,
            currencySymbol: rules.currencySymbol
        )
    }

    /// The parts of the model's answer the receipt's text backs up: a name
    /// printed on it, an amount printed on it, a date printed on it (in
    /// either reading of "03/04") and a currency printed on it. A language
    /// model can make up a plausible total; this never lets one through.
    public static func checked(_ answer: ReceiptModelAnswer, lines: [String], today: ReceiptDay) -> ReceiptDraft {
        ReceiptDraft(
            merchant: merchant(answer.merchant, in: lines),
            total: total(answer.total, in: lines),
            day: day(answer, in: lines, today: today),
            currencyCode: currency(answer.currency, in: lines)
        )
    }

    // MARK: Checks

    static func merchant(_ answer: String?, in lines: [String]) -> String? {
        guard let answer, let name = ReceiptParser.cleanMerchant(answer),
              ReceiptParser.amounts(in: answer).allSatisfy({ !$0.looksLikeMoney }),
              ReceiptParser.days(in: answer, monthFirst: true).isEmpty
        else { return nil }
        let nameWords = ReceiptParser.words(name).filter { $0.count >= 2 }
        guard !nameWords.isEmpty else { return nil }
        let textWords = Set(lines.flatMap(ReceiptParser.words))
        if nameWords.allSatisfy({ word in textWords.contains { isClose(word, $0) } }) { return name }
        // Words run together by text recognition ("TRADERJOES").
        let squeezed = { (text: String) in ReceiptParser.folded(text).filter { $0.isLetter || $0.isNumber } }
        let text = lines.map(squeezed).joined(separator: " ")
        let squeezedName = squeezed(name)
        return squeezedName.count >= 3 && text.contains(squeezedName) ? name : nil
    }

    static func total(_ answer: String?, in lines: [String]) -> Decimal? {
        let separator = ReceiptParser.decimalSeparator(in: lines)
        guard let answer,
              let value = ReceiptParser.amounts(in: answer, decimalSeparator: separator).first(where: { !$0.isNegative && $0.value > 0 })?.value
        else { return nil }
        let printed = lines.flatMap { ReceiptParser.amounts(in: $0, decimalSeparator: separator) }.filter { !$0.isNegative }.map(\.value)
        return printed.contains(value) ? value : nil
    }

    static func day(_ answer: ReceiptModelAnswer, in lines: [String], today: ReceiptDay) -> ReceiptDay? {
        guard let year = answer.year, let month = answer.month, let dayOfMonth = answer.day,
              let day = ReceiptDay(year: year, month: month, day: dayOfMonth),
              ReceiptParser.isPlausible(day, today: today)
        else { return nil }
        let printed = lines.flatMap { ReceiptParser.days(in: $0, monthFirst: true).joined() }
        return printed.contains(day) ? day : nil
    }

    static func currency(_ answer: String?, in lines: [String]) -> String? {
        guard let answer else { return nil }
        let upper = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let code = ReceiptParser.currencyAliases[upper] ?? (ReceiptParser.isoCurrencyCodes.contains(upper) ? upper : nil),
              ReceiptParser.receiptShows(currency: code, in: lines)
        else { return nil }
        return code
    }

    /// The same word, give or take a letter misread by text recognition
    /// (two in long words, none in one or two letters).
    static func isClose(_ word: String, _ other: String) -> Bool {
        if word == other { return true }
        let allowed = word.count >= 8 ? 2 : (word.count >= 3 ? 1 : 0)
        guard allowed > 0, abs(word.count - other.count) <= allowed else { return false }
        return editDistance(Array(word), Array(other), limit: allowed) <= allowed
    }

    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            if current.min() ?? 0 > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}
