import AppIntents
import Foundation
import KeaserKit
import SwiftUI
import WidgetKit

/// "How Much Did I Spend": the total for a period in an account, optionally
/// on one category or with one payment method, worked out as Home works it
/// out (`SpendingQuestion`). Siri says it, Shortcuts can pass the amount on,
/// and the card under the answer looks like the medium Spending widget.
///
/// Only on this iPhone, unlocked: spending is never read out over the lock
/// screen. This Year, All Time and the category and payment method filters
/// are Keaser Pro, as in the app; without Pro the intent says so instead of
/// answering.
struct GetSpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Did I Spend"
    static var description: IntentDescription {
        IntentDescription(
            "Tells you how much you spent today, this week, this month, this year or in all, in an account, optionally on one category or with one payment method.",
            searchKeywords: ["spending", "spent", "total", "expenses", "how much"],
            resultValueName: "Amount Spent"
        )
    }
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Period", default: .thisWeek)
    var period: SpendingPeriod

    @Parameter(title: "Account", description: "Leave empty for the account selected in Keaser.")
    var account: AccountEntity?

    @Parameter(title: "Category", description: "Only expenses in this category. Part of Keaser Pro.")
    var category: CategoryEntity?

    @Parameter(title: "Payment Method", description: "Only expenses paid this way. Part of Keaser Pro.")
    var paymentMethod: PaymentMethodEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get spending for \(\.$period)") {
            \.$account
            \.$category
            \.$paymentMethod
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentCurrencyAmount> & ProvidesDialog & ShowsSnippetView {
        let store = AppEnvironment.store
        // Catch up with anything written while the app was in the background.
        store.reloadFromDisk()
        if store.loadError != nil { throw KeaserIntentError.dataUnavailable }
        // As the app does when a cached subscription looks over: ask
        // StoreKit before treating Pro as ended (it may have renewed while
        // Keaser was closed).
        if ProEntitlement.needsStoreKitCheck(store.preferences, now: .now) {
            await AppEnvironment.pro.refreshEntitlements()
        }

        let question = SpendingQuestion(
            period: period.period,
            accountID: account?.id,
            category: category.map { ShortcutFlow.Label(id: $0.id, name: $0.name) },
            paymentMethod: paymentMethod.map { ShortcutFlow.Label(id: $0.id, name: $0.name) }
        )
        let outcome = question.answer(in: store.database, isPro: store.isPro(), now: .now)
        guard case .answer(let answer) = outcome else {
            throw IntentRefusal(outcome.refusal ?? "", kind: Self.kind(of: outcome))
        }

        // Spoken without the card: the count and the largest expense too.
        var dialog = IntentDialog(full: "\(answer.spokenSentence())", supporting: "\(answer.sentence())")
        if #available(iOS 27.0, *), systemContext.isVoiceOnly {
            dialog = IntentDialog("\(answer.spokenSentence(locale: systemContext.locale))")
        }
        return .result(
            value: IntentCurrencyAmount(amount: answer.total, currencyCode: answer.currencyCode),
            dialog: dialog,
            view: SpendingSnippetView(snapshot: answer.snapshot)
        )
    }
}

extension GetSpendingIntent {
    /// The system's kind for a question that cannot be answered, where it
    /// has one: no account yet is setup to do in Keaser, a deleted account
    /// or a label the account lacks is something not found. Needing Pro is
    /// said in Keaser's own words only.
    static func kind(of outcome: SpendingOutcome) -> AppIntentError? {
        switch outcome {
        case .noAccount: AppIntentError.UserActionRequired.accountSetup
        case .accountGone, .missingCategory, .missingPaymentMethod: AppIntentError.Unrecoverable.entityNotFound
        case .answer, .needsPro: nil
        }
    }
}

/// The periods a spending question can ask about. Separate from the
/// widget's `WidgetPeriod`, which leaves All Time out.
enum SpendingPeriod: String, AppEnum {
    case today, thisWeek, thisMonth, thisYear, allTime

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [SpendingPeriod: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today", synonyms: ["Today So Far"]),
        .thisWeek: DisplayRepresentation(title: "This Week", synonyms: ["The Week", "This Week So Far"]),
        .thisMonth: DisplayRepresentation(title: "This Month", synonyms: ["The Month", "This Month So Far"]),
        .thisYear: DisplayRepresentation(title: "This Year", synonyms: ["The Year", "This Year So Far"]),
        .allTime: DisplayRepresentation(title: "All Time", synonyms: ["In Total", "Altogether", "Ever"]),
    ]

    var period: Period {
        switch self {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .thisYear: .thisYear
        case .allTime: .allTime
        }
    }
}

/// The card under a spending answer: the medium Spending widget's caption
/// ("Spent This Week") over the total, at the widget's height, on the
/// system's card.
struct SpendingSnippetView: View {
    let snapshot: SpendingSnapshot

    var body: some View {
        SpendingWidgetView(snapshot: snapshot, family: .systemMedium, inApp: true)
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 158)
    }
}
