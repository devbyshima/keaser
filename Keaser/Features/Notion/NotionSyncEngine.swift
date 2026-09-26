import KeaserKit
import Observation
import SwiftUI
import UIKit
import os

/// What the UI shows about one linked account's sync. The last successful
/// sync time is persisted in `NotionConnection.lastSyncedAt`; this is the
/// live part.
struct NotionSyncStatus: Equatable {
    var isSyncing = false
    /// The last attempt's error, readable as is. Nil after a success.
    var lastError: String?
    var lastAttempt: Date?
}

/// Mirrors Notion-linked accounts: pushes local edits, pulls remote ones.
///
/// - An expense saved or deleted in a linked account schedules a push two
///   seconds later, so a burst of edits costs one sync.
/// - The app becoming active pulls every linked account.
/// - Deleting an account removes its token.
/// Syncs of one account never overlap; a request made while one runs waits
/// for it and then runs again with the newer data.
@MainActor
@Observable
final class NotionSyncEngine {
    static let shared = NotionSyncEngine()

    /// Debounce between a local edit and its push.
    static let pushDelay: Duration = .seconds(2)
    /// Becoming active within this long of the last attempt does not pull
    /// again (pulling down Control Center also toggles activity).
    static let pullInterval: TimeInterval = 30

    private(set) var statuses: [UUID: NotionSyncStatus] = [:]

    @ObservationIgnored let tokens: any NotionTokenStore
    @ObservationIgnored private let makeClient: @Sendable (String) -> any NotionAPI
    @ObservationIgnored private weak var store: KeaserStore?
    @ObservationIgnored private var pushTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var running: [UUID: Task<Void, any Error>] = [:]
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?
    /// Each linked expense's category and payment method names as last
    /// seen, to notice a rename or delete in Settings that changes what an
    /// expense says in Notion without touching the expense itself.
    @ObservationIgnored private var labels: [UUID: [UUID: ExpenseLabels]] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "NotionSync")

    init(tokens: any NotionTokenStore, makeClient: @escaping @Sendable (String) -> any NotionAPI) {
        self.tokens = tokens
        self.makeClient = makeClient
    }

    private convenience init() {
        #if DEBUG
        if NotionDemo.isEnabled {
            self.init(tokens: NotionDemo.tokens, makeClient: { NotionDemoClient(service: NotionDemo.service, token: $0) })
            return
        }
        #endif
        self.init(tokens: KeychainNotionTokenStore(), makeClient: { NotionClient(token: $0) })
    }

    func status(for accountID: UUID) -> NotionSyncStatus {
        statuses[accountID] ?? NotionSyncStatus()
    }

    /// A client for a token that is not stored yet (the connect flow).
    func client(token: String) -> any NotionAPI {
        makeClient(token)
    }

    // MARK: Wiring

    func attach(to store: KeaserStore) {
        guard self.store == nil else { return }
        self.store = store
        for account in store.accounts where account.isNotionLinked {
            labels[account.id] = Self.labels(of: account)
        }
        store.addObserver { [weak self] change in
            self?.handle(change)
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Let KeaserApp reload the file first, so expenses an App
                // Intent added in the background are part of this sync.
                try? await Task.sleep(for: .milliseconds(500))
                self?.pullAll()
            }
        }
    }

    private func handle(_ change: StoreChange) {
        switch change {
        case .expenseSaved(let accountID, _), .expenseDeleted(let accountID, _, _):
            guard let account = store?.account(id: accountID), account.isNotionLinked else { return }
            labels[accountID] = Self.labels(of: account)
            schedulePush(accountID)
        case .accountUpdated(let accountID):
            relabel(accountID)
        case .accountDeleted(let accountID):
            forget(accountID)
        case .accountCreated, .accountsReordered, .reloaded:
            // Pulled or reloaded data is the new baseline.
            for account in store?.accounts ?? [] where account.isNotionLinked {
                labels[account.id] = Self.labels(of: account)
            }
        case .preferencesChanged:
            break
        }
    }

    /// After a category or payment method was renamed or deleted, marks the
    /// affected expenses as edited so the next push writes the new names
    /// (otherwise the next pull would bring the old names back).
    private func relabel(_ accountID: UUID) {
        guard let store, let account = store.account(id: accountID), account.isNotionLinked else {
            labels[accountID] = nil
            return
        }
        let current = Self.labels(of: account)
        let before = labels[accountID] ?? current
        labels[accountID] = current
        let changed = Set(current.compactMap { id, now in before[id].map { $0 == now } == false ? id : nil })
        guard !changed.isEmpty else { return }
        // Not from inside the store's observer callback.
        Task { @MainActor in
            store.updateAccount(accountID, notify: false) { account in
                let now = Date.now
                for index in account.expenses.indices where changed.contains(account.expenses[index].id) {
                    account.expenses[index].updatedAt = now
                }
            }
            self.schedulePush(accountID)
        }
    }

    private struct ExpenseLabels: Equatable {
        var category: String?
        var paymentMethod: String?
    }

    private static func labels(of account: Account) -> [UUID: ExpenseLabels] {
        Dictionary(account.expenses.map { expense in
            (expense.id, ExpenseLabels(
                category: account.category(id: expense.categoryID)?.name,
                paymentMethod: account.paymentMethod(id: expense.paymentMethodID)?.name
            ))
        }, uniquingKeysWith: { first, _ in first })
    }

    private func schedulePush(_ accountID: UUID) {
        pushTasks[accountID]?.cancel()
        pushTasks[accountID] = Task { [weak self] in
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled, let self else { return }
            self.pushTasks[accountID] = nil
            try? await self.syncNow(accountID: accountID)
        }
    }

    /// Pulls every linked account that is idle and was not tried recently.
    func pullAll() {
        guard let store else { return }
        for account in store.accounts where account.isNotionLinked {
            let status = status(for: account.id)
            if status.isSyncing { continue }
            if let last = status.lastAttempt, Date.now.timeIntervalSince(last) < Self.pullInterval { continue }
            Task { try? await self.syncNow(accountID: account.id) }
        }
    }

    // MARK: Syncing

    /// A full pull and push of one account. Throws the sync's error after
    /// recording it in `statuses`; whatever succeeded before the error is
    /// kept.
    func syncNow(accountID: UUID) async throws {
        let previous = running[accountID]
        let task = Task { @MainActor [weak self] in
            _ = await previous?.result
            try await self?.perform(accountID)
        }
        running[accountID] = task
        defer { if running[accountID] == task { running[accountID] = nil } }
        try await task.value
    }

    private func perform(_ accountID: UUID) async throws {
        guard let store, let account = store.account(id: accountID), account.isNotionLinked else { return }
        guard let token = tokens.token(for: accountID) else {
            statuses[accountID] = NotionSyncStatus(lastError: NotionError.missingToken.errorDescription, lastAttempt: .now)
            throw NotionError.missingToken
        }
        statuses[accountID, default: NotionSyncStatus()].isSyncing = true
        // A push starts two seconds after an edit, often as the person
        // leaves the app: ask for time to finish and save what it did.
        let background = BackgroundTime(name: "Notion sync")
        defer { background.end() }
        let outcome = await NotionSync.run(
            account: account,
            api: makeClient(token),
            calendar: store.preferences.calendar,
            startedAt: .now
        )
        // notify: false so writing pulled data does not schedule a push.
        store.updateAccount(accountID, notify: false) { outcome.apply(to: &$0) }
        statuses[accountID] = NotionSyncStatus(
            isSyncing: false,
            lastError: outcome.error?.errorDescription,
            lastAttempt: .now
        )
        if let error = outcome.error {
            log.error("Sync failed: \(error.errorDescription ?? "", privacy: .public)")
            throw error
        }
    }

    // MARK: Linking

    /// Creates a Notion-linked account, keeps its token and runs the first
    /// sync. Returns the account ID and the first sync's error, if any (the
    /// account stays linked either way).
    func connect(name: String, connection: NotionConnection, token: String) async throws -> (UUID, NotionError?) {
        guard let store else { throw NotionError.noDataSource }
        let account = store.createAccount(name: name, notion: connection)
        do {
            try tokens.setToken(token, for: account.id)
        } catch {
            store.deleteAccount(account.id)
            throw error
        }
        do {
            try await syncNow(accountID: account.id)
            return (account.id, nil)
        } catch let error as NotionError {
            return (account.id, error)
        } catch {
            return (account.id, .network(error.localizedDescription))
        }
    }

    /// Unlinks the account from Notion. Expenses stay; the database in
    /// Notion is not touched.
    func disconnect(accountID: UUID) {
        store?.updateAccount(accountID) { account in
            account.notion = nil
            account.deletedNotionPageIDs = []
            for index in account.expenses.indices { account.expenses[index].notionPageID = nil }
        }
        forget(accountID)
    }

    private func forget(_ accountID: UUID) {
        labels[accountID] = nil
        pushTasks.removeValue(forKey: accountID)?.cancel()
        tokens.removeToken(for: accountID)
        statuses[accountID] = nil
    }
}

/// A UIKit background task, ended exactly once: by the caller, or by the
/// system when the time runs out.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

#if DEBUG
/// `-KeaserNotionDemo 1`: an in-memory Notion workspace instead of the
/// network, so every step of the flow can be screenshotted offline.
enum NotionDemo {
    static var isEnabled: Bool { DebugLaunch.int("KeaserNotionDemo") == 1 }
    static let service = NotionDemoService(latency: .milliseconds(350))
    static let tokens = InMemoryNotionTokenStore()
}
#endif
