import AppIntents
import KeaserKit
import SwiftUI

/// The expense card the Add Expense shortcut and the Wallet automation show
/// under their dialog: the amount, then title, account, category, payment
/// method and date. The system draws the platter, the dialog and the buttons
/// around it.
///
/// With a `session` (the interactive confirmation card, iOS 26 and later)
/// Account, Category and Payment carry up and down chevrons, and a tap moves
/// that detail on to its next option; the system then draws the card again.
struct ExpenseCardView: View {
    let card: ShortcutCard
    var session: String?

    var body: some View {
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
            Button(intent: ChangeExpenseDetailIntent(session: session, detail: detail)) {
                ExpenseCardRow(symbol: symbol, label: label, value: value, changes: true)
            }
            .buttonStyle(.plain)
        } else {
            ExpenseCardRow(symbol: symbol, label: label, value: value, changes: false)
        }
    }
}

/// Symbol and label in grey on the leading side, the value trailing.
private struct ExpenseCardRow: View {
    let symbol: String
    let label: String
    let value: String
    /// Whether a tap changes the value, shown with up and down chevrons.
    let changes: Bool

    @ScaledMetric(relativeTo: .callout) private var symbolWidth: CGFloat = 23

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .keaserFont(15, relativeTo: .callout)
                .foregroundStyle(Color.keaserSecondaryText)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            Text(label)
                .font(.callout)
                .foregroundStyle(Color.keaserSecondaryText)
                .fixedSize()
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Text(value)
                    .font(.callout)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .lineLimit(1)
                if changes {
                    Image(systemName: "chevron.up.chevron.down")
                        .keaserFont(10, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(changes ? Text("Changes to the next \(label.lowercased())") : Text(""))
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

    private var drafts: [String: (flow: ShortcutFlow, currencyCode: String)] = [:]

    /// Keeps `flow` until `close(_:)`; returns its session.
    func open(_ flow: ShortcutFlow, currencyCode: String) -> String {
        let session = UUID().uuidString
        drafts[session] = (flow, currencyCode)
        return session
    }

    func flow(_ session: String) -> ShortcutFlow? {
        drafts[session]?.flow
    }

    func card(_ session: String) -> ShortcutCard? {
        guard let draft = drafts[session], let expense = draft.flow.expense else { return nil }
        return ShortcutCard(expense: expense, in: draft.flow.account, currencyCode: draft.currencyCode)
    }

    func cycle(_ detail: ExpenseCardDetail, in session: String) {
        drafts[session]?.flow.cycle(detail.field)
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
        guard let card = AddExpenseDrafts.shared.card(session) else { return .result(view: EmptyView()) }
        return .result(view: ExpenseCardView(card: card, session: session))
    }
}

/// A tap on Account, Category or Payment on the confirmation card. Showing
/// that detail's list from here is not possible: a button's intent can only
/// present its own UI over a result card, not over a confirmation (WWDC25,
/// "Explore new advances in App Intents"). So each tap moves the detail on to
/// its next option instead, wrapping around.
struct ChangeExpenseDetailIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Expense Detail"
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
        AddExpenseDrafts.shared.cycle(detail, in: session)
        return .result()
    }
}

/// The details of the confirmation card a tap changes.
enum ExpenseCardDetail: String, AppEnum {
    case account, category, paymentMethod

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Expense Detail"
    static let caseDisplayRepresentations: [ExpenseCardDetail: DisplayRepresentation] = [
        .account: "Account",
        .category: "Category",
        .paymentMethod: "Payment Method",
    ]

    var field: ShortcutFlow.Field {
        switch self {
        case .account: .account
        case .category: .category
        case .paymentMethod: .paymentMethod
        }
    }
}
