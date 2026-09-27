import KeaserKit
import StoreKit
import SwiftUI
import UIKit
import os

/// Pro status for the UI: the 7-day pass plus StoreKit purchases.
///
/// StoreKit is the source of truth for purchases. Its verdict is cached in
/// `Preferences.hasProPurchase`, with the subscription's end in
/// `Preferences.proExpirationDate`, so the widget extension sees the same
/// answer without asking StoreKit on every redraw, and locks itself when a
/// subscription lapses.
@MainActor
@Observable
final class ProStore {
    @ObservationIgnored private let store: KeaserStore
    @ObservationIgnored private let passRecord: any ProPassRecord

    init(store: KeaserStore, passRecord: (any ProPassRecord)? = nil) {
        self.store = store
        self.passRecord = passRecord ?? Self.defaultPassRecord
        watchEntitlementEnd()
    }

    private static var defaultPassRecord: any ProPassRecord {
        #if DEBUG
        // Seeded launches keep their data in memory, and their pass too, so
        // screenshots never leave a pass behind in the simulator.
        if DebugLaunch.seed != nil { return InMemoryProPassRecord() }
        #endif
        return KeychainProPassRecord()
    }

    /// True while the pass is live or after a purchase. Gate Pro features on
    /// this. It turns false on its own when the pass or a subscription runs
    /// out, and views reading it redraw then.
    var isPro: Bool {
        _ = entitlementClock
        return store.isPro()
    }

    /// Whole days left in the pass; nil if no pass was started, 0 once over.
    var trialDaysRemaining: Int? {
        _ = entitlementClock
        return ProEntitlement.trialDaysRemaining(trialStart: store.preferences.trialStartDate, now: .now)
    }

    /// True while a purchase grants Pro (not merely the pass): a lifetime
    /// purchase, or a subscription that has not lapsed.
    var hasPurchased: Bool {
        _ = entitlementClock
        return ProEntitlement.hasActivePurchase(store.preferences, now: .now)
    }

    // MARK: Entitlement end

    /// Moved on when the pass or a subscription runs out. The properties
    /// above depend on the time as well as on the cache, and Observation
    /// only sees the cache; reading this makes every view that shows Pro
    /// state redraw at that moment instead of at the next edit.
    private var entitlementClock = 0
    @ObservationIgnored private var entitlementEnd: Date?
    @ObservationIgnored private var entitlementEndTask: Task<Void, Never>?
    @ObservationIgnored private var timeChangeObserver: (any NSObjectProtocol)?
    /// False in DEBUG launches that force a Pro state, which StoreKit must
    /// not overwrite.
    @ObservationIgnored private var readsStoreKit = false

    /// Keeps a timer on the next moment `isPro` can change by itself
    /// (`ProEntitlement.nextChange`), rescheduled whenever the cache changes
    /// or the clock is set.
    private func watchEntitlementEnd() {
        store.addObserver { [weak self] change in
            switch change {
            case .preferencesChanged, .reloaded: self?.scheduleEntitlementEnd()
            default: break
            }
        }
        timeChangeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The timer counts elapsed time; a new wall clock moves the end.
                self.entitlementEndTask?.cancel()
                self.entitlementEndTask = nil
                self.entitlementEnd = nil
                self.entitlementClock &+= 1
                self.scheduleEntitlementEnd()
            }
        }
        scheduleEntitlementEnd()
    }

    private func scheduleEntitlementEnd() {
        let end = ProEntitlement.nextChange(after: .now, preferences: store.preferences)
        guard end != entitlementEnd || entitlementEndTask == nil else { return }
        entitlementEndTask?.cancel()
        entitlementEnd = end
        guard let end else {
            entitlementEndTask = nil
            return
        }
        entitlementEndTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            } catch {
                return
            }
            await self?.entitlementEndReached()
        }
    }

    private func entitlementEndReached() async {
        // Detached from the timer first, so the reschedule that the refresh
        // below triggers cannot cancel it halfway through.
        entitlementEndTask = nil
        entitlementEnd = nil
        // A subscription that looks over may have renewed, or entered its
        // grace period, while nothing was listening. Ask before locking.
        if readsStoreKit, ProEntitlement.needsStoreKitCheck(store.preferences, now: .now) {
            await refreshEntitlements()
        }
        entitlementClock &+= 1
        scheduleEntitlementEnd()
    }

    // MARK: Pass

    /// Starts the 7-day pass if it has never been started. Called by
    /// onboarding when the user continues past the "7-Day Pro Pass" page.
    /// A pass started before a reinstall is picked up again rather than
    /// restarted.
    func startTrialIfNeeded(now: Date = .now) {
        guard store.preferences.trialStartDate == nil else { return }
        let remembered = passRecord.firstStart
        let start = ProPass.startDate(database: nil, remembered: remembered) ?? now
        if remembered == nil { passRecord.remember(start) }
        store.updatePreferences { $0.trialStartDate = start }
    }

    /// Keeps the database and the Keychain on the same, earliest pass start.
    /// Also records passes that began before the Keychain copy existed.
    private func reconcilePass() {
        let stored = store.preferences.trialStartDate
        let remembered = passRecord.firstStart
        guard let start = ProPass.startDate(database: stored, remembered: remembered) else { return }
        if remembered != start { passRecord.remember(start) }
        if let stored, stored != start { store.updatePreferences { $0.trialStartDate = start } }
    }

    // MARK: Products

    enum ProductsState: Equatable {
        case idle
        case loading
        case loaded
        /// The App Store could not be reached or returned nothing.
        case unavailable
    }

    /// One plan on the paywall. `product` is nil only for DEBUG sample prices.
    struct Plan: Identifiable {
        let kind: ProProduct
        let price: Decimal
        let displayPrice: String
        /// The storefront's currency format, for prices worked out here (the
        /// struck-through lifetime price).
        let priceFormat: Decimal.FormatStyle.Currency
        let product: Product?

        var id: ProProduct { kind }

        init(product: Product, kind: ProProduct) {
            self.kind = kind
            price = product.price
            displayPrice = product.displayPrice
            priceFormat = product.priceFormatStyle
            self.product = product
        }

        #if DEBUG
        init(sample kind: ProProduct, price: Decimal) {
            self.kind = kind
            self.price = price
            priceFormat = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
            displayPrice = price.formatted(priceFormat)
            product = nil
        }
        #endif

        func formatted(_ amount: Decimal) -> String {
            amount.formatted(priceFormat)
        }
    }

    /// Purchasable plans in `ProProduct` order (monthly, yearly, lifetime).
    private(set) var plans: [Plan] = []
    private(set) var productsState: ProductsState = .idle
    /// The plan being bought right now, if any.
    private(set) var purchasingPlan: ProProduct?
    private(set) var isRestoring = false
    /// The last purchase or restore problem, shown inline on the paywall.
    var errorMessage: String?

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "ProStore")

    func plan(_ kind: ProProduct) -> Plan? {
        plans.first { $0.kind == kind }
    }

    /// Called once at launch: loads products, listens for transactions and
    /// refreshes entitlements, then refreshes them again every time the app
    /// becomes active (a subscription that lapses sends no transaction).
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        #if DEBUG
        if applyDebugOverrides() { return }
        #endif
        readsStoreKit = true
        listenForTransactions()
        refreshWhenActive()
        reconcilePass()
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        guard productsState != .loading else { return }
        productsState = .loading
        do {
            let products = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            plans = ProProduct.allCases.compactMap { kind in
                products.first { $0.id == kind.rawValue }.map { Plan(product: $0, kind: kind) }
            }
            productsState = plans.isEmpty ? .unavailable : .loaded
        } catch {
            log.error("Loading products failed: \(error.localizedDescription, privacy: .public)")
            productsState = plans.isEmpty ? .unavailable : .loaded
        }
    }

    // MARK: Purchasing

    /// Buys `plan` with SwiftUI's purchase action (which presents the App
    /// Store sheet in the right scene). True when Pro is owned afterwards.
    func purchase(_ plan: Plan, using purchase: PurchaseAction) async -> Bool {
        guard purchasingPlan == nil else { return false }
        guard let product = plan.product else {
            // Only DEBUG sample plans have no product.
            errorMessage = "The App Store is not available in this build."
            return false
        }
        purchasingPlan = plan.kind
        errorMessage = nil
        defer { purchasingPlan = nil }
        do {
            switch try await purchase(product) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "The App Store could not verify this purchase. Tap Restore in a moment."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return hasPurchased
            case .pending:
                errorMessage = "Your purchase is waiting for approval. Keaser Pro unlocks as soon as it goes through."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Asks the App Store for this Apple Account's purchases. True when Pro
    /// is owned afterwards.
    func restore() async -> Bool {
        guard !isRestoring else { return hasPurchased }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return hasPurchased
        } catch {
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = Self.message(for: error)
        }
        await refreshEntitlements()
        if !hasPurchased && errorMessage == nil {
            errorMessage = "No Keaser Pro purchase was found for this Apple Account."
        }
        return hasPurchased
    }

    // MARK: Entitlements

    /// Recomputes ownership from the verified, unrevoked transactions
    /// StoreKit reports, and caches it and the subscription's end for the
    /// widget. A subscription that is set to renew is cached past its
    /// renewal date (`ProRenewal.end(expiringAt:)`), so it does not look
    /// lapsed before the renewal reaches the app.
    func refreshEntitlements() async {
        let now = Date.now
        var grant = ProGrant.none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            grant = grant.combined(with: ProProduct.grant(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                renewal: await Self.renewal(of: transaction),
                now: now
            ))
        }
        store.updatePreferences { grant.cache(in: &$0) }
    }

    /// What StoreKit says about the subscription's next renewal. Nil for a
    /// lifetime purchase, or when StoreKit cannot tell (Pro then ends at the
    /// transaction's expiry).
    private static func renewal(of transaction: StoreKit.Transaction) async -> ProRenewal? {
        guard transaction.productType == .autoRenewable,
              let status = await transaction.subscriptionStatus,
              case .verified(let info) = status.renewalInfo
        else { return nil }
        return ProRenewal(
            willAutoRenew: info.willAutoRenew,
            isInBillingRetry: info.isInBillingRetry,
            gracePeriodEnd: status.state == .inGracePeriod ? info.gracePeriodExpirationDate : nil
        )
    }

    private func refreshWhenActive() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshEntitlements() }
            }
        }
    }

    /// Renewals, refunds, Ask to Buy approvals and purchases made on other
    /// devices arrive here while the app runs.
    private func listenForTransactions() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                guard let self else { return }
                await self.refreshEntitlements()
            }
        }
    }

    private static func message(for error: any Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return "Could not reach the App Store. Check your connection and try again."
            case .notAvailableInStorefront:
                return "Keaser Pro is not available in your country or region."
            case .notEntitled:
                return "This Apple Account does not own Keaser Pro."
            default:
                break
            }
        }
        if let purchaseError = error as? Product.PurchaseError, case .purchaseNotAllowed = purchaseError {
            return "Purchases are not allowed on this iPhone. Check Screen Time restrictions."
        }
        return "Something went wrong with the App Store. Please try again."
    }

    #if DEBUG
    /// Screenshot states, from `-KeaserPro purchased|expired|never` and
    /// `-KeaserProPrices sample`. Returns true when StoreKit should be left
    /// alone so it does not overwrite the forced state.
    private func applyDebugOverrides() -> Bool {
        var overridden = false
        switch DebugLaunch.string("KeaserPro") {
        case "purchased":
            store.updatePreferences {
                $0.hasProPurchase = true
                $0.proExpirationDate = nil
            }
            overridden = true
        case "expired":
            store.updatePreferences { $0.trialStartDate = Calendar.current.date(byAdding: .day, value: -10, to: .now) }
        case "never":
            store.updatePreferences { $0.trialStartDate = nil }
        default:
            break
        }
        if DebugLaunch.string("KeaserProPrices") == "sample" {
            // The prices in Keaser.storekit; simctl launches cannot use the
            // StoreKit configuration, so the paywall would show no prices.
            plans = [
                Plan(sample: .monthly, price: Decimal(string: "3.99")!),
                Plan(sample: .yearly, price: Decimal(string: "24.99")!),
                Plan(sample: .lifetime, price: Decimal(string: "29.99")!),
            ]
            productsState = .loaded
            overridden = true
        }
        return overridden
    }
    #endif
}
