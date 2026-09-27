import AppIntents
import Foundation
import KeaserKit
import WidgetKit

/// "Delete Expense": deletes expenses after asking, by name, whether to.
/// Run while Keaser is open (iOS 26 and later), the system's undo brings
/// them back. Only on this iPhone, unlocked, like opening an expense.
struct DeleteExpenseIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Expense"
    static var description: IntentDescription {
        IntentDescription("Deletes expenses from Keaser after you confirm. Run in Keaser, Undo puts them back.")
    }
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Expenses", requestValueDialog: "Which expense?")
    var entities: [ExpenseEntity]

    static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$entities)")
    }

    init() {}

    init(entities: [ExpenseEntity]) {
        self.entities = entities
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentSupport.freshStore()
        let asked = ExpenseDeletion(ids: entities.map(\.id), in: store.database)
        guard !asked.isEmpty else { throw Self.gone(count: entities.count) }
        try await requestConfirmation(
            actionName: .custom(
                acceptLabel: "Delete",
                acceptAlternatives: ["Remove", "Yes"],
                denyLabel: "Cancel",
                denyAlternatives: ["Keep", "No"],
                destructive: true
            ),
            dialog: "\(asked.question(currencyCode: store.preferences.currencyCode))"
        )

        // The question may have been up a while: delete what is there now.
        let latest = try IntentSupport.freshStore()
        let deletion = ExpenseDeletion(ids: asked.items.map(\.expense.id), in: latest.database)
        guard !deletion.isEmpty else { throw Self.gone(count: asked.items.count) }
        try await IntentSupport.delete(deletion, store: latest)
        if #available(iOS 26.0, *) {
            registerUndo(of: deletion)
        }
        return .result(dialog: "\(deletion.doneSentence)")
    }

    private static func gone(count: Int) -> IntentRefusal {
        IntentRefusal(count == 1 ? "That expense is no longer in Keaser." : "Those expenses are no longer in Keaser.")
    }
}

/// Undo after a deletion that ran in Keaser: the system hands the intent the
/// app's undo manager, so shaking or the three-finger gesture puts the
/// expenses back, unchanged.
@available(iOS 26.0, *)
extension DeleteExpenseIntent: UndoableIntent {
    @MainActor
    fileprivate func registerUndo(of deletion: ExpenseDeletion) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: AppEnvironment.store) { store in
            Task { await IntentSupport.restore(deletion.items, store: store) }
        }
        undoManager.setActionName(deletion.items.count == 1 ? "Delete Expense" : "Delete Expenses")
    }
}

extension IntentSupport {
    /// Deletes, then brings the widgets, the weekly summary and Spotlight up
    /// to date before the intent returns, as `save` does. Throws when the
    /// deletion did not reach the disk; the expenses are then back in memory
    /// too (see `KeaserStore.delete(_:)`).
    static func delete(_ deletion: ExpenseDeletion, store: KeaserStore) async throws {
        guard store.delete(deletion) else {
            throw IntentRefusal("Keaser couldn't delete this. Free up space on your iPhone and try again.")
        }
        await catchUpAfterChange(in: store)
    }

    /// Undo of `delete`: puts the expenses back where they were.
    static func restore(_ items: [ExpenseDeletion.Item], store: KeaserStore) async {
        store.reloadFromDisk()
        guard store.loadError == nil, store.restore(items) else { return }
        await catchUpAfterChange(in: store)
    }

    private static func catchUpAfterChange(in store: KeaserStore) async {
        WidgetCenter.shared.reloadAllTimelines()
        WeeklySummaryScheduler.shared.attach(to: store)
        await WeeklySummaryScheduler.shared.refreshNow()
        SpotlightIndexer.shared.attach(to: store)
        await SpotlightIndexer.shared.flush()
    }
}
