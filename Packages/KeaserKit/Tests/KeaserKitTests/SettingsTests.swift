import Foundation
import Testing
@testable import KeaserKit

struct SettingsCurrencyTests {
    private let english = Locale(identifier: "en_US")

    @Test func listsEveryCommonCurrencyOnceSortedByCode() {
        let options = CurrencyCatalog.options(locale: english)
        let codes = options.map(\.code)
        #expect(codes == codes.sorted())
        #expect(Set(codes).count == codes.count)
        #expect(options.count >= Locale.commonISOCurrencyCodes.count - 1)
        #expect(codes.contains("USD"))
        #expect(codes.contains("EUR"))
        #expect(codes.contains("KES"))
    }

    @Test func titlesReadNameThenCode() throws {
        let usd = try #require(CurrencyCatalog.options(locale: english).first { $0.code == "USD" })
        #expect(usd.name == "US Dollar")
        #expect(usd.title == "US Dollar (USD)")
    }

    @Test func aCodeWithoutANameShowsTheBareCode() throws {
        let options = CurrencyCatalog.options(locale: english, including: ["zzq "])
        let unknown = try #require(options.first { $0.code == "ZZQ" })
        #expect(unknown.name == nil)
        #expect(unknown.title == "ZZQ")
    }

    @Test func extraCodesAreNotDuplicated() {
        let options = CurrencyCatalog.options(locale: english, including: ["usd", "USD"])
        #expect(options.filter { $0.code == "USD" }.count == 1)
    }

    @Test func searchMatchesCodeOrNameIgnoringCaseAndAccents() {
        let options = CurrencyCatalog.options(locale: english)
        let dollars = CurrencyCatalog.filter(options, matching: "dollar")
        #expect(dollars.contains { $0.code == "USD" })
        #expect(dollars.contains { $0.code == "AUD" })
        #expect(!dollars.contains { $0.code == "EUR" })
        #expect(CurrencyCatalog.filter(options, matching: "  ").count == options.count)
        #expect(CurrencyCatalog.filter(options, matching: "bolivar").contains { $0.code == "VES" })
        #expect(CurrencyCatalog.filter(options, matching: "us dollar").first?.code == "USD")
        #expect(CurrencyCatalog.filter(options, matching: "qqqq").isEmpty)
    }

    @Test func anExactCodeMatchComesFirst() {
        let options = [
            CurrencyOption(code: "AAA", name: "Pegged to USD"),
            CurrencyOption(code: "BBB", name: "Other"),
            CurrencyOption(code: "USD", name: "US Dollar"),
        ]
        #expect(CurrencyCatalog.filter(options, matching: "usd").map(\.code) == ["USD", "AAA"])
        #expect(CurrencyCatalog.filter(options, matching: "pegged").map(\.code) == ["AAA"])
    }
}

struct SettingsLabelTests {
    @Test func categorySymbolsAreCuratedAndUnique() {
        let choices = SymbolCatalog.categories
        #expect(choices.count >= 40)
        #expect(Set(choices.map(\.symbol)).count == choices.count)
        #expect(Set(choices.map(\.suggestedName)).count == choices.count)
    }

    @Test func paymentSymbolsAreUnique() {
        let choices = SymbolCatalog.paymentMethods
        #expect(choices.count >= 10)
        #expect(Set(choices.map(\.symbol)).count == choices.count)
        #expect(Set(choices.map(\.suggestedName)).count == choices.count)
    }

    @Test func defaultLabelsAppearInTheirGrids() {
        let categorySymbols = Set(SymbolCatalog.categories.map(\.symbol))
        for category in ExpenseCategory.defaults() {
            #expect(categorySymbols.contains(category.symbol), "\(category.name)")
        }
        let paymentSymbols = Set(SymbolCatalog.paymentMethods.map(\.symbol))
        for method in PaymentMethod.defaults() {
            #expect(paymentSymbols.contains(method.symbol), "\(method.name)")
        }
    }

    @Test func kindsDescribeThemselves() {
        #expect(LabelKind.category.pluralTitle == "Categories")
        #expect(LabelKind.paymentMethod.singularTitle == "Payment Method")
        #expect(LabelKind.paymentMethod.choices == SymbolCatalog.paymentMethods)
    }

    @Test func blankNamesFallBackToTheSuggestion() {
        #expect(LabelNaming.resolvedName(typed: "  Rent ", suggestion: "Home") == "Rent")
        #expect(LabelNaming.resolvedName(typed: "   ", suggestion: "Shopping") == "Shopping")
        #expect(LabelNaming.resolvedName(typed: "", suggestion: nil) == nil)
        #expect(LabelNaming.resolvedName(typed: "", suggestion: " ") == nil)
    }

    @Test func duplicateNamesIgnoreCaseAccentsAndTheLabelItself() {
        let food = UUID()
        let cafe = UUID()
        let existing = [(id: food, name: "Food & Drinks"), (id: cafe, name: "Café")]
        #expect(LabelNaming.isTaken("food & drinks", by: existing, excluding: nil))
        #expect(LabelNaming.isTaken(" cafe ", by: existing, excluding: nil))
        #expect(!LabelNaming.isTaken("Food & Drinks", by: existing, excluding: food))
        #expect(!LabelNaming.isTaken("Travel", by: existing, excluding: nil))
    }

    @Test func newLabelsStartOnAnUnusedSymbol() {
        let used = Set(ExpenseCategory.defaults().map(\.symbol))
        let start = LabelNaming.startingChoice(from: SymbolCatalog.categories, usedSymbols: used)
        #expect(start?.symbol == "cup.and.saucer.fill")
        let all = Set(SymbolCatalog.categories.map(\.symbol))
        #expect(LabelNaming.startingChoice(from: SymbolCatalog.categories, usedSymbols: all)?.symbol == "fork.knife")
        #expect(LabelNaming.startingChoice(from: [], usedSymbols: []) == nil)
    }
}

struct SettingsContentTests {
    @Test func releasesAreNewestFirstWithValidDates() throws {
        let releases = ReleaseHistory.releases
        #expect(!releases.isEmpty)
        #expect(releases.first?.version == "1.0.0")
        #expect(releases.first?.title == "v1.0.0")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = try releases.map { try #require(formatter.date(from: $0.date)) }
        #expect(dates == dates.sorted(by: >))
        #expect(Set(releases.map(\.version)).count == releases.count)
        for release in releases { #expect(!release.highlights.isEmpty) }
    }

    @Test func tutorialsReferToTheSharedIntentTitles() {
        #expect(Tutorials.all.map(\.id) == Tutorial.ID.allCases)
        let shortcut = Tutorials.tutorial(.addExpenseShortcut)
        #expect(shortcut.steps.contains { $0.detail.contains("Add Expense") })
        let wallet = Tutorials.tutorial(.walletAutomation)
        let text = wallet.steps.map { $0.title + " " + $0.detail }.joined(separator: " ")
        for word in ["Automation", "Transaction", "Log Wallet Transaction", "Merchant", "Amount", "Card"] {
            #expect(text.contains(word), "\(word)")
        }
    }

    @Test func parsesTheMarkdownTheLegalPagesUse() {
        let source = """
        # Privacy Policy

        Keaser keeps your data
        on your iPhone.

        ## What we collect
        - Nothing that leaves the device
        - No **analytics**
          or tracking

        1. First
        2. Second
        ---
        #Not a heading
        """
        #expect(MarkdownBlocks.parse(source) == [
            .heading(level: 1, text: "Privacy Policy"),
            .paragraph("Keaser keeps your data on your iPhone."),
            .heading(level: 2, text: "What we collect"),
            .bullets(["Nothing that leaves the device", "No **analytics** or tracking"]),
            .numbered(["First", "Second"]),
            .rule,
            .paragraph("#Not a heading"),
        ])
        #expect(MarkdownBlocks.parse("").isEmpty)
    }
}

struct SettingsSupportTests {
    @Test func versionReadsTheInfoDictionary() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"])
        #expect(version.display == "1.0.0 (1)")
        #expect(AppVersion(infoDictionary: nil).display == "0 (0)")
    }

    @Test func supportMailCarriesSubjectAndVersion() throws {
        let version = AppVersion(marketing: "1.0.0", build: "7")
        let url = try #require(SupportMail.url(to: "help@example.com", version: version, system: "iOS 18.6"))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "help@example.com")
        #expect(components.queryItems?.first { $0.name == "subject" }?.value == "Keaser Support")
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("Keaser 1.0.0 (7), iOS 18.6"))
        #expect(url.absoluteString.hasPrefix("mailto:help@example.com?subject=Keaser%20Support"))
    }

    @Test func supportMailEncodesPlusSigns() throws {
        let url = try #require(SupportMail.url(to: "a@b.co", version: AppVersion(marketing: "1+2", build: "1"), system: "iOS"))
        #expect(url.absoluteString.contains("1%2B2"))
    }

    @Test func supportMailRejectsBadAddresses() {
        let version = AppVersion(marketing: "1", build: "1")
        #expect(SupportMail.url(to: "not an address", version: version, system: "iOS") == nil)
        #expect(SupportMail.url(to: "", version: version, system: "iOS") == nil)
    }
}

struct SettingsProTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func productIDsMatchTheStoreKitConfiguration() {
        #expect(ProProduct.yearly.rawValue == "com.fulltimestudio.keaser.pro.yearly")
        #expect(ProProduct.lifetime.rawValue == "com.fulltimestudio.keaser.pro.lifetime")
        #expect(ProProduct.subscriptionGroupName == "Keaser Pro")
    }

    @Test func onlyLiveKeaserTransactionsGrantPro() {
        let lifetime = ProProduct.lifetime.rawValue
        let yearly = ProProduct.yearly.rawValue
        let renews = now.addingTimeInterval(60)
        #expect(ProProduct.grant(productID: lifetime, revocationDate: nil, expirationDate: nil, now: now) == .forever)
        #expect(ProProduct.grant(productID: lifetime, revocationDate: now, expirationDate: nil, now: now) == .none)
        #expect(ProProduct.grant(productID: yearly, revocationDate: nil, expirationDate: renews, now: now) == .until(renews))
        #expect(ProProduct.grant(productID: yearly, revocationDate: nil, expirationDate: now.addingTimeInterval(-60), now: now) == .none)
        #expect(ProProduct.grant(productID: yearly, revocationDate: now, expirationDate: renews, now: now) == .none)
        #expect(ProProduct.grant(productID: "com.example.other", revocationDate: nil, expirationDate: nil, now: now) == .none)
    }

    /// Transaction.currentEntitlements yields subscriptions in the billing
    /// grace period with their original, already past expiry; the grace end
    /// comes from RenewalInfo.gracePeriodExpirationDate.
    @Test func aSubscriptionInBillingGracePeriodStillGrantsPro() {
        let expiredTwoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        let graceEnds = now.addingTimeInterval(4 * 86_400)
        let grant = ProProduct.grant(
            productID: ProProduct.yearly.rawValue, revocationDate: nil,
            expirationDate: expiredTwoDaysAgo, gracePeriodEnd: graceEnds, now: now
        )
        #expect(grant == .until(graceEnds))
        #expect(grant.hasPurchase)
        #expect(grant.expirationDate == graceEnds)
    }

    /// Billing retry without a grace period (or after it ends) keeps no Pro.
    @Test func billingRetryWithoutGraceGrantsNothing() {
        let yearly = ProProduct.yearly.rawValue
        let expired = now.addingTimeInterval(-2 * 86_400)
        #expect(ProProduct.grant(productID: yearly, revocationDate: nil, expirationDate: expired, gracePeriodEnd: nil, now: now) == .none)
        let graceOver = now.addingTimeInterval(-60)
        #expect(ProProduct.grant(productID: yearly, revocationDate: nil, expirationDate: expired, gracePeriodEnd: graceOver, now: now) == .none)
    }

    @Test func grantsCombineToTheBestOne() {
        let soon = now.addingTimeInterval(60)
        let later = now.addingTimeInterval(600)
        #expect(ProGrant.none.combined(with: .until(soon)) == .until(soon))
        #expect(ProGrant.until(later).combined(with: .until(soon)) == .until(later))
        #expect(ProGrant.until(soon).combined(with: .forever) == .forever)
        #expect(ProGrant.forever.combined(with: .none) == .forever)
        #expect(!ProGrant.none.hasPurchase)
        #expect(ProGrant.forever.expirationDate == nil)
    }

    /// The cached flag alone never expired, so a lapsed yearly subscription
    /// kept Pro, and the widget unlocked, until the next UI cold launch.
    @Test func aLapsedYearlySubscriptionStopsGrantingPro() {
        let purchased = Date(timeIntervalSince1970: 1_760_000_000)
        let renewal = purchased.addingTimeInterval(365 * 86_400)
        let prefs = Preferences(trialStartDate: purchased, hasProPurchase: true, proExpirationDate: renewal)
        #expect(ProEntitlement.isPro(prefs, now: renewal.addingTimeInterval(-60)))
        let twoYearsLater = purchased.addingTimeInterval(2 * 365 * 86_400)
        #expect(!ProEntitlement.isPro(prefs, now: twoYearsLater))
        let database = Database(accounts: [Account(name: "P")], preferences: prefs)
        let snap = SpendingSnapshot.make(database: database, accountID: nil, period: .thisMonth, now: twoYearsLater)
        #expect(snap.state == .locked)
    }

    @Test func aLifetimePurchaseNeverLapses() {
        let purchased = Date(timeIntervalSince1970: 1_760_000_000)
        let prefs = Preferences(trialStartDate: purchased, hasProPurchase: true, proExpirationDate: nil)
        #expect(ProEntitlement.isPro(prefs, now: purchased.addingTimeInterval(20 * 365 * 86_400)))
        #expect(ProEntitlement.nextChange(after: purchased, preferences: prefs) == nil)
    }

    @Test func theWidgetRedrawsWhenTheSubscriptionEnds() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_790_000_000 - 1_790_000_000.truncatingRemainder(dividingBy: 86_400) + 43_200)
        let renewsTonight = noon.addingTimeInterval(6 * 3_600)
        let prefs = Preferences(trialStartDate: noon.addingTimeInterval(-30 * 86_400), hasProPurchase: true, proExpirationDate: renewsTonight)
        #expect(SpendingSnapshot.nextRefresh(after: noon, preferences: prefs, calendar: cal) == renewsTonight)
        // Already lapsed: nothing ahead but midnight.
        let lapsed = Preferences(hasProPurchase: true, proExpirationDate: noon.addingTimeInterval(-60))
        #expect(SpendingSnapshot.nextRefresh(after: noon, preferences: lapsed, calendar: cal) == noon.addingTimeInterval(12 * 3_600))
    }

    @Test func thePassStartsAtTheEarliestRecord() {
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        let later = first.addingTimeInterval(30 * 86_400)
        #expect(ProPass.startDate(database: nil, remembered: nil) == nil)
        #expect(ProPass.startDate(database: later, remembered: nil) == later)
        // After a reinstall the database is empty; the Keychain remembers.
        #expect(ProPass.startDate(database: nil, remembered: first) == first)
        #expect(ProPass.startDate(database: later, remembered: first) == first)
        #expect(ProPass.startDate(database: first, remembered: later) == first)
    }

    @Test func theInMemoryPassRecordRemembers() {
        let record = InMemoryProPassRecord()
        #expect(record.firstStart == nil)
        record.remember(now)
        #expect(record.firstStart == now)
        #expect(InMemoryProPassRecord(now).firstStart == now)
    }

    @Test func paywallLeadsWithTheHighlightedFeature() {
        #expect(ProFeature.ordered(highlighting: nil) == ProFeature.allCases)
        let ordered = ProFeature.ordered(highlighting: .longTermInsights)
        #expect(ordered.first == .longTermInsights)
        #expect(Set(ordered) == Set(ProFeature.allCases))
        #expect(ordered.count == ProFeature.allCases.count)
        for feature in ProFeature.allCases { #expect(!feature.detail.isEmpty) }
    }

    @Test func statusTextCoversEveryState() {
        #expect(ProStatusText.subtitle(trialDaysRemaining: 7, hasPurchased: false) == "7 days left in trial")
        #expect(ProStatusText.subtitle(trialDaysRemaining: 1, hasPurchased: false) == "1 day left in trial")
        #expect(ProStatusText.subtitle(trialDaysRemaining: 0, hasPurchased: false) == "Your Pro pass has ended")
        #expect(ProStatusText.subtitle(trialDaysRemaining: nil, hasPurchased: false) == "Unlock the full experience")
        #expect(ProStatusText.subtitle(trialDaysRemaining: 3, hasPurchased: true) == "Thanks for supporting Keaser")
    }
}
