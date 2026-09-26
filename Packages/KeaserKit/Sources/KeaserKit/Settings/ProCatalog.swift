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

    /// Whether one StoreKit transaction still grants Pro: a Keaser Pro product
    /// that was not refunded or revoked and, for the subscription, has not
    /// expired.
    public static func grantsPro(productID: String, revocationDate: Date?, expirationDate: Date?, now: Date) -> Bool {
        guard ProProduct(rawValue: productID) != nil, revocationDate == nil else { return false }
        if let expirationDate { return expirationDate > now }
        return true
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
