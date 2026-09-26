import Foundation

/// The two ways to buy Keaser Pro. Raw values are the App Store product IDs,
/// matching `Keaser/Resources/Keaser.storekit`.
public enum ProProduct: String, CaseIterable, Identifiable, Sendable {
    case yearly = "com.fulltimestudio.keaser.pro.yearly"
    case lifetime = "com.fulltimestudio.keaser.pro.lifetime"

    /// The auto-renewable subscription group `yearly` belongs to.
    public static let subscriptionGroupName = "Keaser Pro"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .yearly: "Yearly"
        case .lifetime: "Lifetime"
        }
    }

    public var detail: String {
        switch self {
        case .yearly: "Renews every year. Cancel anytime."
        case .lifetime: "Pay once, keep Pro for good."
        }
    }

    /// What one StoreKit transaction grants: nothing for another product or
    /// a refunded or revoked one, Pro for good for a purchase that does not
    /// expire, and Pro until the later of its expiry and `gracePeriodEnd` for
    /// the subscription.
    ///
    /// Pass `gracePeriodEnd` only while the subscription is in its billing
    /// grace period: its transaction then carries the original, already past
    /// expiry, and Pro continues until the grace period ends. A subscription
    /// in billing retry without a grace period has no `gracePeriodEnd` and
    /// grants nothing, as Apple recommends.
    public static func grant(
        productID: String,
        revocationDate: Date?,
        expirationDate: Date?,
        gracePeriodEnd: Date? = nil,
        now: Date
    ) -> ProGrant {
        guard ProProduct(rawValue: productID) != nil, revocationDate == nil else { return .none }
        guard let expirationDate else { return .forever }
        let end = max(expirationDate, gracePeriodEnd ?? expirationDate)
        return end > now ? .until(end) : .none
    }
}

/// Pro ownership worked out from StoreKit, in the shape
/// `Preferences.hasProPurchase` and `Preferences.proExpirationDate` cache it.
public enum ProGrant: Equatable, Sendable {
    case none
    /// A subscription, through this date.
    case until(Date)
    /// A lifetime purchase.
    case forever

    /// The better of two grants, for combining every current transaction.
    public func combined(with other: ProGrant) -> ProGrant {
        switch (self, other) {
        case (.forever, _), (_, .forever): .forever
        case (.until(let a), .until(let b)): .until(max(a, b))
        case (.until, .none): self
        case (.none, _): other
        }
    }

    /// The value for `Preferences.hasProPurchase`.
    public var hasPurchase: Bool { self != .none }

    /// The value for `Preferences.proExpirationDate`.
    public var expirationDate: Date? {
        if case .until(let date) = self { return date }
        return nil
    }
}

extension ProFeature {
    /// One line for the paywall.
    public var detail: String {
        switch self {
        case .widgets: "Spending on your Home and Lock Screen."
        case .moreFilters: "Filter by category and payment method."
        case .multipleAccounts: "Keep personal and work spending apart."
        case .longTermInsights: "Totals and charts for years, not weeks."
        }
    }

    /// All features with `highlighted` moved to the front, so the paywall
    /// leads with whatever the user just tried to use.
    public static func ordered(highlighting highlighted: ProFeature?) -> [ProFeature] {
        guard let highlighted else { return allCases }
        return [highlighted] + allCases.filter { $0 != highlighted }
    }
}

/// Wording for Pro status in the Settings banner and on the paywall.
public enum ProStatusText {
    /// "7 days left in trial", "1 day left in trial", "Your Pro pass has
    /// ended", or "Unlock the full experience" before any pass.
    public static func subtitle(trialDaysRemaining: Int?, hasPurchased: Bool) -> String {
        if hasPurchased { return "Thanks for supporting Keaser" }
        guard let days = trialDaysRemaining else { return "Unlock the full experience" }
        if days <= 0 { return "Your Pro pass has ended" }
        return days == 1 ? "1 day left in trial" : "\(days) days left in trial"
    }
}
