import KeaserKit
import SwiftUI

/// Every page that can be pushed inside the Settings sheet.
enum SettingsPage: Hashable {
    case account(UUID)
    /// Categories or payment methods of an account. `opening` shows the
    /// editor on arrival (used by screenshots).
    case labels(LabelKind, accountID: UUID, opening: LabelListView.Opening = .list)
    case currency
    case startWeek
    case smartSuggestions
    case weeklySummary
    case shortcut
    case tutorials
    case tutorial(Tutorial.ID)
    case whatsNew
    case release(String)
    case help
    case followUs
    case privacy
    case terms

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .account(let id): AccountSettingsView(accountID: id)
        case .labels(let kind, let accountID, let opening):
            LabelListView(kind: kind, accountID: accountID, opening: opening)
        case .currency: CurrencyPickerView()
        case .startWeek: StartWeekView()
        case .smartSuggestions: SmartSuggestionsView()
        case .weeklySummary: WeeklySummaryView()
        case .shortcut: ShortcutSettingsView()
        case .tutorials: TutorialsView()
        case .tutorial(let id): TutorialDetailView(tutorial: Tutorials.tutorial(id))
        case .whatsNew: WhatsNewView()
        case .release(let version): ReleaseDetailView(version: version)
        case .help: HelpFeedbackView()
        case .followUs: FollowUsView()
        case .privacy: LegalDocumentView(document: .privacy)
        case .terms: LegalDocumentView(document: .terms)
        }
    }

    /// The pages `-KeaserSettingsPage <name>` opens at launch (DEBUG), so a
    /// screenshot can start deep inside Settings. Empty in Release.
    @MainActor
    static func launchPath(store: KeaserStore) -> [SettingsPage] {
        guard let name = DebugLaunch.settingsPage else { return [] }
        let account = store.selectedAccount?.id
        switch name {
        case "account": return account.map { [.account($0)] } ?? []
        case "categories": return account.map { [.account($0), .labels(.category, accountID: $0)] } ?? []
        case "newCategory": return account.map { [.account($0), .labels(.category, accountID: $0, opening: .newLabel)] } ?? []
        case "editCategory": return account.map { [.account($0), .labels(.category, accountID: $0, opening: .firstLabel)] } ?? []
        case "paymentMethods": return account.map { [.account($0), .labels(.paymentMethod, accountID: $0)] } ?? []
        case "newPaymentMethod": return account.map { [.account($0), .labels(.paymentMethod, accountID: $0, opening: .newLabel)] } ?? []
        case "editPaymentMethod": return account.map { [.account($0), .labels(.paymentMethod, accountID: $0, opening: .firstLabel)] } ?? []
        case "currency": return [.currency]
        case "startWeek": return [.startWeek]
        case "smartSuggestions": return [.smartSuggestions]
        case "weeklySummary": return [.weeklySummary]
        case "shortcut": return [.shortcut]
        case "tutorials": return [.tutorials]
        case "tutorialShortcut": return [.tutorials, .tutorial(.addExpenseShortcut)]
        case "tutorialWallet": return [.tutorials, .tutorial(.walletAutomation)]
        case "whatsNew": return [.whatsNew]
        case "release": return [.whatsNew, .release(ReleaseHistory.releases[0].version)]
        case "help": return [.help]
        case "followUs": return [.followUs]
        case "privacy": return [.privacy]
        case "terms": return [.terms]
        default: return []
        }
    }
}
