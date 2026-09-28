import AppIntents
import KeaserKit
import SwiftUI

/// The expense card the Add Expense shortcut and the Wallet automation show
/// under their dialog: the amount, then title, account, category, payment
/// method and date. The system draws the platter, the dialog and the buttons
/// around it.
///
/// With a `session` (the interactive confirmation card, iOS 26 and later)
/// Account, Category and Payment carry up and down chevrons. A tap opens that
/// detail's options inside the card (`options`); picking one sets it and
/// closes the list again. The system draws the card again after every tap.
///
/// Values are medium and labels a lighter grey (`keaserSnippetLabel`), as the
/// reference card draws them.
struct ExpenseCardView: View {
    let card: ShortcutCard
    var session: String?
    /// The detail open on its options, on the interactive card only.
    var options: ShortcutCardList.Source?

    var body: some View {
        if let session, let options {
            ExpenseCardOptions(card: card, source: options, session: session)
        } else {
            details
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            Text(card.amount)
                .keaserFont(38, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20.5)
            VStack(spacing: 17.5) {
                row(symbol: "text.alignleft", label: "Title", value: card.title)
                row(symbol: "person.fill", label: "Account", value: card.account, detail: .account)
                row(symbol: "tag.fill", label: "Category", value: card.category, detail: .category)
                row(symbol: "creditcard.fill", label: "Payment", value: card.paymentMethod, detail: .paymentMethod)
                row(symbol: "calendar", label: "Date", value: card.date)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 19)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func row(symbol: String, label: String, value: String, detail: ExpenseCardDetail? = nil) -> some View {
        if let detail, let session {
            Button(intent: ShowExpenseCardOptionsIntent(session: session, detail: detail)) {
                ExpenseCardRow(symbol: symbol, label: label, value: value, changes: true, hint: "Shows the \(detail.pluralName)")
            }
            .buttonStyle(.plain)
        } else {
            ExpenseCardRow(symbol: symbol, label: label, value: value, changes: false)
        }
    }
}

/// Symbol and label in grey on the leading side, the value trailing, in
/// medium.
///
/// `yieldsLabel` (the open list's header): when the label and the whole
/// value do not both fit on the line, as at the accessibility text sizes,
/// the value takes the label's place beside the symbol, shrinking a little
/// before it is cut. The row stays one line, so the card keeps its height.
private struct ExpenseCardRow: View {
    let symbol: String
    let label: String
    let value: String
    /// Whether a tap opens the detail's options, shown with up and down
    /// chevrons.
    let changes: Bool
    var hint: String = ""
    var yieldsLabel = false

    @ScaledMetric(relativeTo: .callout) private var symbolWidth: CGFloat = 23

    var body: some View {
        Group {
            if yieldsLabel {
                ViewThatFits(in: .horizontal) {
                    labelled
                    HStack(spacing: 8) {
                        icon
                        valueText
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                labelled
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(hint))
    }

    private var labelled: some View {
        HStack(spacing: 8) {
            icon
            Text(label)
                .font(.callout)
                .foregroundStyle(Color.keaserSnippetLabel)
                .fixedSize()
            Spacer(minLength: 12)
            valueText
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .keaserFont(15, relativeTo: .callout)
            .foregroundStyle(Color.keaserSnippetLabel)
            .frame(width: symbolWidth)
    }

    private var valueText: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
            if changes {
                Image(systemName: "chevron.up.chevron.down")
                    .keaserFont(10, weight: .semibold, relativeTo: .caption2)
                    .foregroundStyle(Color.keaserSnippetLabel)
            }
        }
    }
}

/// The card with one detail open: that detail's row on top (tapping it
/// closes the list), a hairline, then its options, More and Go Back. Rows
/// keep the card's 38.5-point rhythm, and the list takes only as many lines
/// as fit at the person's text size, so the whole card stays under the 340
/// points a snippet may take.
private struct ExpenseCardOptions: View {
    let card: ShortcutCard
    let source: ShortcutCardList.Source
    let session: String

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .callout) private var symbolWidth: CGFloat = 23
    /// A line of callout text: 21 points at the default text size.
    @ScaledMetric(relativeTo: .callout) private var lineHeight: CGFloat = 21

    /// Fitted to the text size: fewer lines as it grows, and one column at
    /// the accessibility sizes.
    private var list: ShortcutCardList {
        source.list(forLineHeight: Double(lineHeight))
    }

    /// Half the card's 17.5-point row spacing above and below each row, so
    /// the whole line is the tap target.
    static let rowPadding: CGFloat = 8.75

    private var detail: ExpenseCardDetail { ExpenseCardDetail(list.field) }

    var body: some View {
        VStack(spacing: 0) {
            Button(intent: CloseExpenseCardOptionsIntent(session: session)) {
                ExpenseCardRow(symbol: detail.symbol, label: detail.label, value: detail.value(on: card), changes: true, hint: "Closes the list", yieldsLabel: true)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
            Rectangle()
                .fill(Color.keaserSeparator)
                .frame(height: 1 / displayScale)
            VStack(spacing: 0) {
                indented {
                    if let empty = list.emptyText {
                        Text(empty)
                            .font(.callout)
                            .foregroundStyle(Color.keaserSnippetLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Self.rowPadding)
                    } else {
                        optionRows(list)
                    }
                }
                if list.offersMore {
                    Button(intent: PageExpenseCardOptionsIntent(session: session, page: list.page + 1)) {
                        ActionRow(symbol: "ellipsis", title: "More", trailing: list.pageText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows more \(detail.pluralName)"))
                }
                if list.offersGoBack {
                    Button(intent: CloseExpenseCardOptionsIntent(session: session)) {
                        ActionRow(symbol: "arrow.uturn.backward", title: "Go Back")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Closes the list without changing anything"))
                }
            }
            .padding(.top, 14 - Self.rowPadding)
        }
        .padding(.horizontal, 20)
        .padding(.top, 19)
        .padding(.bottom, 12 - Self.rowPadding)
    }

    /// The options line by line (`ShortcutCardList.rows`). In two columns
    /// each line holds both columns' options on one baseline, in halves of
    /// the width; VoiceOver still reads down the first column, then the
    /// second.
    private func optionRows(_ list: ShortcutCardList) -> some View {
        let order = Dictionary(list.options.enumerated().map { ($1.id, $0) }) { first, _ in first }
        let twoColumns = list.columnCount == 2
        return VStack(spacing: 0) {
            ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    ForEach(row) { option in
                        Button(intent: PickExpenseCardOptionIntent(session: session, detail: detail, option: option.id.uuidString)) {
                            OptionRow(option: option, compact: twoColumns)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilitySortPriority(Double(list.options.count - (order[option.id] ?? 0)))
                    }
                    if twoColumns && row.count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Lines the options up with the labels above them.
    private func indented(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: symbolWidth, height: 1)
                .accessibilityHidden(true)
            content()
        }
    }
}

/// An option's name, with a checkmark when it is the chosen one: at the
/// trailing edge in one column, as the card's values sit, and right after
/// the name in two, where the edge belongs to the next column. A name too
/// long for its line shrinks a little before it is cut; it stays on the
/// line's baseline.
private struct OptionRow: View {
    let option: ShortcutCardList.Option
    /// In two columns.
    let compact: Bool

    var body: some View {
        // On the name's baseline, so the checkmark cannot move the name off
        // the line's baseline in two columns.
        HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
            Text(option.name)
                .font(.callout)
                .foregroundStyle(Color.keaserPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if compact { checkmark }
            Spacer(minLength: 0)
            if !compact { checkmark }
        }
        .padding(.vertical, ExpenseCardOptions.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option.isCurrent ? [.isSelected] : [])
    }

    @ViewBuilder
    private var checkmark: some View {
        if option.isCurrent {
            Image(systemName: "checkmark")
                .keaserFont(14, weight: .semibold, relativeTo: .callout)
                .foregroundStyle(Color.keaserInk)
                .accessibilityHidden(true)
        }
    }
}

/// More and Go Back: a grey symbol and title, like the card's labels.
private struct ActionRow: View {
    let symbol: String
    let title: String
    var trailing: String?

    @ScaledMetric(relativeTo: .callout) private var symbolWidth: CGFloat = 23

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .keaserFont(15, relativeTo: .callout)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(.callout)
            }
        }
        .foregroundStyle(Color.keaserSnippetLabel)
        .padding(.vertical, ExpenseCardOptions.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The interactive confirmation card (iOS 26 and later)

/// The drafts behind the confirmation cards on screen, by session. The card
/// and each tap on it are separate intents; the system performs them in this
/// process and keeps it running while the card is up, so memory is enough.
/// `AddExpenseIntent` reads its draft back when Continue is tapped.
@MainActor
final class AddExpenseDrafts {
    static let shared = AddExpenseDrafts()

    private struct Draft {
        var flow: ShortcutFlow
        let currencyCode: String
        /// The detail showing its options, if any.
        var open: ShortcutFlow.Field?
        /// The page of options shown; nil for the one with the current option.
        var page: Int?
    }

    private var drafts: [String: Draft] = [:]

    /// Keeps `flow` until `close(_:)`; returns its session.
    func open(_ flow: ShortcutFlow, currencyCode: String) -> String {
        let session = UUID().uuidString
        drafts[session] = Draft(flow: flow, currencyCode: currencyCode)
        return session
    }

    func flow(_ session: String) -> ShortcutFlow? {
        drafts[session]?.flow
    }

    func card(_ session: String) -> ShortcutCard? {
        guard let draft = drafts[session], let expense = draft.flow.expense else { return nil }
        return ShortcutCard(expense: expense, in: draft.flow.account, currencyCode: draft.currencyCode)
    }

    /// The options of the open detail, or nil when none is open. The card
    /// fits them to the text size.
    func options(_ session: String) -> ShortcutCardList.Source? {
        guard let draft = drafts[session], let field = draft.open else { return nil }
        return ShortcutCardList.Source(flow: draft.flow, field: field, page: draft.page)
    }

    func showOptions(_ field: ShortcutFlow.Field, in session: String) {
        drafts[session]?.open = field
        drafts[session]?.page = nil
    }

    func showPage(_ page: Int, in session: String) {
        drafts[session]?.page = page
    }

    /// Sets the detail to the picked option and closes the list.
    func pick(_ id: UUID, for field: ShortcutFlow.Field, in session: String) {
        drafts[session]?.flow.change(field, to: id)
        closeOptions(in: session)
    }

    func closeOptions(in session: String) {
        drafts[session]?.open = nil
        drafts[session]?.page = nil
    }

    func close(_ session: String) {
        drafts[session] = nil
    }
}

/// Draws the confirmation card from its draft, each time the system asks
/// (after every tap, and when the appearance changes).
@available(iOS 26.0, *)
struct ExpenseCardSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Expense Details"

    @Parameter(title: "Session")
    var session: String

    init() {}

    init(session: String) {
        self.session = session
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let drafts = AddExpenseDrafts.shared
        guard let card = drafts.card(session) else { return .result(view: EmptyView()) }
        return .result(view: ExpenseCardView(card: card, session: session, options: drafts.options(session)))
    }
}

// The taps on the confirmation card. A button's intent may only present its
// own UI over a result card, not over a confirmation (WWDC25, "Explore new
// advances in App Intents"), so each one only changes the draft, and the
// card is drawn again with the list inside it.

/// A tap on Account, Category or Payment: shows that detail's options.
struct ShowExpenseCardOptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Expense Detail Options"
    static let isDiscoverable = false

    @Parameter(title: "Session")
    var session: String

    @Parameter(title: "Detail")
    var detail: ExpenseCardDetail

    init() {}

    init(session: String, detail: ExpenseCardDetail) {
        self.session = session
        self.detail = detail
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AddExpenseDrafts.shared.showOptions(detail.field, in: session)
        return .result()
    }
}

/// A tap on an option: sets the detail to it and closes the list.
struct PickExpenseCardOptionIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick Expense Detail Option"
    static let isDiscoverable = false

    @Parameter(title: "Session")
    var session: String

    @Parameter(title: "Detail")
    var detail: ExpenseCardDetail

    /// The option's ID.
    @Parameter(title: "Option")
    var option: String

    init() {}

    init(session: String, detail: ExpenseCardDetail, option: String) {
        self.session = session
        self.detail = detail
        self.option = option
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: option) {
            AddExpenseDrafts.shared.pick(id, for: detail.field, in: session)
        }
        return .result()
    }
}

/// More: shows another page of options. It carries the page to show, so a
/// repeated tap cannot skip one.
struct PageExpenseCardOptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show More Expense Detail Options"
    static let isDiscoverable = false

    @Parameter(title: "Session")
    var session: String

    @Parameter(title: "Page")
    var page: Int

    init() {}

    init(session: String, page: Int) {
        self.session = session
        self.page = page
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AddExpenseDrafts.shared.showPage(page, in: session)
        return .result()
    }
}

/// Go Back, or a tap on the open detail's row: closes the list, changing
/// nothing.
struct CloseExpenseCardOptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Close Expense Detail Options"
    static let isDiscoverable = false

    @Parameter(title: "Session")
    var session: String

    init() {}

    init(session: String) {
        self.session = session
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AddExpenseDrafts.shared.closeOptions(in: session)
        return .result()
    }
}

/// The details of the confirmation card that open a list of options.
enum ExpenseCardDetail: String, AppEnum {
    case account, category, paymentMethod

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Expense Detail"
    static let caseDisplayRepresentations: [ExpenseCardDetail: DisplayRepresentation] = [
        .account: "Account",
        .category: "Category",
        .paymentMethod: "Payment Method",
    ]

    init(_ field: ShortcutFlow.Field) {
        switch field {
        case .account: self = .account
        case .category: self = .category
        case .paymentMethod: self = .paymentMethod
        }
    }

    var field: ShortcutFlow.Field {
        switch self {
        case .account: .account
        case .category: .category
        case .paymentMethod: .paymentMethod
        }
    }

    /// The symbol and label of its row on the card.
    var symbol: String {
        switch self {
        case .account: "person.fill"
        case .category: "tag.fill"
        case .paymentMethod: "creditcard.fill"
        }
    }

    var label: String {
        switch self {
        case .account: "Account"
        case .category: "Category"
        case .paymentMethod: "Payment"
        }
    }

    var pluralName: String {
        switch self {
        case .account: "accounts"
        case .category: "categories"
        case .paymentMethod: "payment methods"
        }
    }

    func value(on card: ShortcutCard) -> String {
        switch self {
        case .account: card.account
        case .category: card.category
        case .paymentMethod: card.paymentMethod
        }
    }
}
