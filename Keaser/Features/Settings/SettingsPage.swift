import KeaserKit
import SwiftUI

/// Every page that can be pushed in the Settings tab. The tab's path lives in
/// `AppRouter.settingsPath`, so a route can take it back to the root.
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

    /// The account a page belongs to: Account Settings and an account's
    /// Categories or Payment Methods.
    var accountID: UUID? {
        switch self {
        case .account(let id): id
        case .labels(_, let accountID, _): accountID
        default: nil
        }
    }

    /// The pages `-KeaserSettingsPage <name>` pushes in the Settings tab at
    /// launch (DEBUG), so a screenshot can start deep inside Settings (with
    /// `-KeaserTab settings` to show it). Empty in Release.
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

extension [SettingsPage] {
    /// The path without the first page whose account is not among
    /// `accountIDs`, or any page after it: a deleted account's pages leave
    /// the stack, and so does whatever was pushed over them.
    func keepingAccounts(_ accountIDs: Set<UUID>) -> [SettingsPage] {
        guard let gone = firstIndex(where: { page in
            page.accountID.map { !accountIDs.contains($0) } ?? false
        }) else { return self }
        return Array(prefix(gone))
    }
}
