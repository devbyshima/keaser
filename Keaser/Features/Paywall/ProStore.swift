import KeaserKit
import StoreKit
import SwiftUI
import os

/// Pro status for the UI: the 7-day pass plus StoreKit purchases.
///
/// StoreKit is the source of truth for purchases. Its verdict is cached in
/// `Preferences.hasProPurchase` so the widget extension, which cannot ask
/// StoreKit cheaply, sees the same answer.
@MainActor
@Observable
final class ProStore {
    @ObservationIgnored private let store: KeaserStore

    init(store: KeaserStore) {
        self.store = store
    }

    /// True while the pass is live or after a purchase. Gate Pro features on this.
    var isPro: Bool { store.isPro() }

    /// Whole days left in the pass; nil if no pass was started, 0 once over.
    var trialDaysRemaining: Int? {
        ProEntitlement.trialDaysRemaining(trialStart: store.preferences.trialStartDate, now: .now)
    }

    /// True once the user has bought Pro (not merely trialling).
    var hasPurchased: Bool { store.preferences.hasProPurchase }

    /// Starts the 7-day pass if it has never been started. Called by
    /// onboarding when the user continues past the "7-Day Pro Pass" page.
    func startTrialIfNeeded(now: Date = .now) {
        guard store.preferences.trialStartDate == nil else { return }
        store.updatePreferences { $0.trialStartDate = now }
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
        let displayPrice: String
        let product: Product?

        var id: ProProduct { kind }

        /// "$14.99 / year" or "$29.99 once".
        var priceLabel: String {
            switch kind {
            case .yearly: "\(displayPrice) / year"
            case .lifetime: "\(displayPrice) once"
            }
        }
    }

    /// Purchasable plans in `ProProduct` order (yearly, then lifetime).
    private(set) var plans: [Plan] = []
    private(set) var productsState: ProductsState = .idle
    /// The plan being bought right now, if any.
    private(set) var purchasingPlan: ProProduct?
    private(set) var isRestoring = false
    /// The last purchase or restore problem, shown inline on the paywall.
    var errorMessage: String?

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.fulltimestudio.keaser", category: "ProStore")

    func plan(_ kind: ProProduct) -> Plan? {
        plans.first { $0.kind == kind }
    }

    /// Called once at launch: loads products, listens for transactions and
    /// refreshes entitlements.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        #if DEBUG
        if applyDebugOverrides() { return }
        #endif
        listenForTransactions()
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        guard productsState != .loading else { return }
        productsState = .loading
        do {
            let products = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            plans = ProProduct.allCases.compactMap { kind in
                products.first { $0.id == kind.rawValue }.map { Plan(kind: kind, displayPrice: $0.displayPrice, product: $0) }
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
                    errorMessage = "The App Store could not verify this purchase. Try Restore Purchases in a moment."
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

    /// Recomputes ownership from the verified, unrevoked, unexpired
    /// transactions StoreKit reports, and caches it for the widget.
    func refreshEntitlements() async {
        let now = Date.now
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProProduct.grantsPro(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                now: now
            ) {
                entitled = true
            }
        }
        if store.preferences.hasProPurchase != entitled {
            store.updatePreferences { $0.hasProPurchase = entitled }
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
            store.updatePreferences { $0.hasProPurchase = true }
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
                Plan(kind: .yearly, displayPrice: "$14.99", product: nil),
                Plan(kind: .lifetime, displayPrice: "$29.99", product: nil),
            ]
            productsState = .loaded
            overridden = true
        }
        return overridden
    }
    #endif
}
