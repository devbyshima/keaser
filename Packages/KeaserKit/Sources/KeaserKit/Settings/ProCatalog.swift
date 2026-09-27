import Foundation

/// The ways to buy Keaser Pro, in paywall order. Raw values are the App Store
/// product IDs, matching `Keaser/Resources/Keaser.storekit`.
public enum ProProduct: String, CaseIterable, Identifiable, Sendable {
    case monthly = "com.fulltimestudio.keaser.pro.monthly"
    case yearly = "com.fulltimestudio.keaser.pro.yearly"
    case lifetime = "com.fulltimestudio.keaser.pro.lifetime"

    /// The auto-renewable subscription group `monthly` and `yearly` share,
    /// so a subscriber can switch between them without paying twice.
    public static let subscriptionGroupName = "Keaser Pro"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Annual"
        case .lifetime: "Lifetime"
        }
    }

    /// Written after a subscription's price: "$3.99 / mo".
    public var priceSuffix: String? {
        switch self {
        case .monthly: "/ mo"
        case .yearly: "/ yr"
        case .lifetime: nil
        }
    }

    /// How long past its renewal date a subscription that is set to renew
    /// keeps Pro in the cache. The App Store charges a renewal in the day
    /// before that date, but the new transaction only reaches Keaser when
    /// the app runs, so without this a paying subscriber would look lapsed
    /// at every renewal. Once it is over, the widget and the app ask StoreKit
    /// again before they lock (`ProEntitlement.needsStoreKitCheck`). It is
    /// also as long as Pro can outlive a cancellation that the app has not
    /// seen yet.
    public static let renewalAllowance: TimeInterval = 86_400

    /// What one StoreKit transaction grants: nothing for another product or
    /// a refunded or revoked one, Pro for good for a purchase that does not
    /// expire, and Pro until the end `renewal` allows for the subscription.
    ///
    /// Pass `renewal` for the subscription (from its renewal info and
    /// status). Without it, Pro ends at `expirationDate`.
    public static func grant(
        productID: String,
        revocationDate: Date?,
        expirationDate: Date?,
        renewal: ProRenewal? = nil,
        now: Date
    ) -> ProGrant {
        guard ProProduct(rawValue: productID) != nil, revocationDate == nil else { return .none }
        guard let expirationDate else { return .forever }
        let end = renewal?.end(expiringAt: expirationDate) ?? expirationDate
        return end > now ? .until(end) : .none
    }
}

/// What StoreKit says about a subscription's next renewal: its
/// `RenewalInfo`, and its `RenewalState` for the grace period.
public struct ProRenewal: Equatable, Sendable {
    /// Auto-renew is still on.
    public var willAutoRenew: Bool
    /// The App Store is retrying a renewal payment that failed.
    public var isInBillingRetry: Bool
    /// The end of the billing grace period, only while the subscription is
    /// in it (`RenewalState.inGracePeriod`).
    public var gracePeriodEnd: Date?

    public init(willAutoRenew: Bool, isInBillingRetry: Bool = false, gracePeriodEnd: Date? = nil) {
        self.willAutoRenew = willAutoRenew
        self.isInBillingRetry = isInBillingRetry
        self.gracePeriodEnd = gracePeriodEnd
    }

    /// When Pro ends for a subscription whose current period ends at
    /// `expiration`:
    /// - in the billing grace period, at the end of the grace period;
    /// - in billing retry without a grace period, at `expiration` (already
    ///   past), so it grants nothing, as Apple recommends;
    /// - while it will renew, `ProProduct.renewalAllowance` after
    ///   `expiration`, so the renewal date is not mistaken for a lapse;
    /// - once auto-renew is off, at `expiration`.
    public func end(expiringAt expiration: Date) -> Date {
        if let gracePeriodEnd { return max(expiration, gracePeriodEnd) }
        if willAutoRenew && !isInBillingRetry { return expiration.addingTimeInterval(ProProduct.renewalAllowance) }
        return expiration
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

    /// Writes this grant into the cache the widget reads.
    public func cache(in preferences: inout Preferences) {
        preferences.hasProPurchase = hasPurchase
        preferences.proExpirationDate = expirationDate
    }
}

extension ProFeature {
    /// One line for the paywall.
    public var detail: String {
        switch self {
        case .widgets: "Quick access from your Home Screen."
        case .moreFilters: "Filter by categories and payment methods."
        case .multipleAccounts: "Remove the limit of one account."
        case .longTermInsights: "View all data and trends from past years."
        }
    }

    /// All features with `highlighted` moved to the front, so the paywall
    /// leads with whatever the user just tried to use.
    public static func ordered(highlighting highlighted: ProFeature?) -> [ProFeature] {
        guard let highlighted else { return allCases }
        return [highlighted] + allCases.filter { $0 != highlighted }
    }
}

/// Price wording on the paywall, worked out from the App Store's prices so it
/// stays true in every storefront and after a price change.
public enum ProPricing {
    /// The "regular" lifetime price shown struck through beside the real one,
    /// as a multiple of the lifetime price, keeping the price's own ending
    /// (2 shows $59.99 beside $29.99, as in the reference).
    /// Change it to adjust the comparison, or set it to nil to show the
    /// lifetime price alone.
    public static let lifetimeRegularPriceMultiplier: Decimal? = 2

    /// Under Lifetime on the paywall.
    public static let lifetimeSubtitle = "Founding member price"

    /// The struck-through price for a lifetime price, or nil when
    /// `lifetimeRegularPriceMultiplier` is off or would not be higher.
    public static func regularLifetimePrice(for lifetime: Decimal) -> Decimal? {
        guard let multiplier = lifetimeRegularPriceMultiplier, multiplier > 1, lifetime > 0 else { return nil }
        // Whole units of the multiple, plus the lifetime price's own cents:
        // 29.99 x 2 is 59.98, shown as 59.99 so both prices end alike.
        var whole = Decimal()
        var scaled = lifetime * multiplier
        NSDecimalRound(&whole, &scaled, 0, .down)
        var lifetimeWhole = Decimal()
        var lifetimeCopy = lifetime
        NSDecimalRound(&lifetimeWhole, &lifetimeCopy, 0, .down)
        let regular = whole + (lifetime - lifetimeWhole)
        return regular > lifetime ? regular : nil
    }

    /// How much cheaper a year of the annual plan is than twelve months of
    /// the monthly one, in whole percent rounded down (so it never
    /// overstates the saving). Nil when it is not a saving.
    public static func annualSavingsPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        var fraction = (1 - yearly / (monthly * 12)) * 100
        var percent = Decimal()
        NSDecimalRound(&percent, &fraction, 0, .down)
        let whole = NSDecimalNumber(decimal: percent).intValue
        return whole > 0 ? whole : nil
    }

    /// "47% off monthly plan" under Annual, or nil when there is no saving
    /// to show.
    public static func annualSubtitle(monthly: Decimal, yearly: Decimal) -> String? {
        annualSavingsPercent(monthly: monthly, yearly: yearly).map { "\($0)% off monthly plan" }
    }
}

/// Wording for Pro status in the Settings banner.
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
