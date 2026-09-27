# Keaser

iOS SwiftUI expense tracker: accounts, expenses, categories, payment methods,
charts, filters, widgets, Shortcuts, weekly summary notifications, and a
Keaser Pro upgrade with a 7-day pass. Light and dark, monochrome,
Liquid Glass on iOS 26+.

- `Packages/KeaserKit/` - models, persistence, the `KeaserStore`, and all pure
  logic. Foundation only (no SwiftUI, UIKit or WidgetKit). Tested on the Mac with
  `./scripts/test.sh` (Swift Testing), no simulator needed. Anything testable
  belongs here, with `public` access.
- `Keaser/` - the app: SwiftUI views, App Intents, notifications, StoreKit.
- `KeaserWidgets/` - WidgetKit extension (home screen, lock screen, control).

The Xcode project is generated. After editing `project.yml`, run
`xcodegen generate`. Never hand-edit `Keaser.xcodeproj` (it is gitignored).

## Commands

    ./scripts/build.sh           # xcodegen + simulator build; prints errors only
    ./scripts/test.sh            # KeaserKit tests on the Mac
    ./scripts/screenshots.sh     # headless screenshots from scripts/shots/*.txt
    ./scripts/screenshots.sh home   # one area only
    SIM="Keaser home" ./scripts/screenshots.sh home   # use your own simulator

Screenshots land in `screenshots/<area>-<name>.png` at 1206x2622, the same
size as the reference recording. Verify UI by looking at them. Do not drive the
simulator GUI; add launch arguments instead.

## Platform

- Deployment target iOS 18.0; built with the iOS 27 SDK. The only local
  simulator runtime is iOS 27.0, so that is what screenshots show. Cold
  launches straight into deep Settings pages or right after a rebuild can
  come out black at the default settle time; use `SETTLE=7` (or up to 12).
- Liquid Glass (iOS 26+) only through `Keaser/Design/Glass.swift`
  (`keaserGlass(in:)`, `keaserGlassButtonStyle()`, `KeaserGlassContainer`),
  which falls back to materials on iOS 18. Never call `glassEffect` directly.
- Swift 6 language mode. `KeaserStore` and views are `@MainActor`.
- Light and dark, following the system appearance. Every colour comes from
  the adaptive tokens in `Keaser/Design/Theme.swift` (`keaserInk` is the
  single accent: black in light mode, white in dark). Never hard-code white
  or black; add a token with `Color(light:dark:)` instead. Screenshot both:
  `APPEARANCE=light OUT=screenshots/light ./scripts/screenshots.sh`.

- Widgets draw from `WidgetPalette` (KeaserWidgets/Shared/SpendingWidgetView.swift),
  not Theme: the home screen surface is white / 20,20,20 and the caption grey
  0.46 / 0.58, measured from the reference widgets. The medium widget is only
  `SpendingSnapshot.spentCaption` ("Spent This Month") over the total, centred.
  The onboarding illustration keeps its own measured charcoal
  (`OnboardingPalette.widgetSurface`).

## Data

One JSON file (`DatabaseFile.shared`) in the app group
`group.com.fulltimestudio.keaser`, read by the widget extension. All writes go
through `KeaserStore` (injected with `@Environment(KeaserStore.self)`, or
`AppEnvironment.store` outside views). Each mutation saves immediately and
notifies observers (`addObserver`) with a `StoreChange`. Money is `Decimal`;
format it with `MoneyFormat.string(_:currencyCode:)` using
`store.preferences.currencyCode`. The shortcut has its own switches:
`shortcutConfirmsDetails`, `shortcutGoBackEnabled` and
`shortcutSmartSuggestionsEnabled` (the last is separate from
`smartSuggestionsEnabled`, which drives New Expense). Week maths must use
`store.preferences.calendar` (it honours Start Week On).

## Launch arguments (DEBUG only)

| Argument | Values | Area |
|---|---|---|
| `-KeaserSeed` | `fresh`, `onboarded`, `account`, `single`, `demo` | foundation |
| `-KeaserSheet` | `settings`, `paywall` (presented by `RootView` over whatever is showing) | foundation |
| `-KeaserOnboardingPage` | `0`...`4`; `widgetGallery` (the Today, This Week and This Month medium widgets first, then small and lock screen), `widgetGalleryLocked` (every widget family); both need seed `fresh` | onboarding |
| `-KeaserGalleryScroll` | `bottom` starts the widget gallery at its end (small and lock screen widgets) | onboarding |
| `-KeaserNotifState` | `granted`, `denied`: page 4 in its end state without the system prompt; with `-KeaserSettingsPage weeklySummary`, `denied` shows the summary on and notifications off | onboarding, settings |
| `-KeaserLetter` | `1` shows the welcome letter over Home | onboarding |
| `-KeaserLetterPage` | `tldr`, `follow` (sample links, DEBUG only) | onboarding |
| `-KeaserSheet` | `accounts`, `addAccount`, `newExpense`, `editExpense`, `search` | home |
| `-KeaserPeriod` | `today`, `thisWeek`, `thisMonth`, `thisYear`, `allTime` | home |
| `-KeaserSearch` | search text, with `-KeaserSheet search` | home |
| `-KeaserExpenseTitle` | text typed into New Expense (shows Smart Suggestions) | home |
| `-KeaserExpenseFocus` | `amount`: then moves on to Amount (shows the guessed category and payment) | home |
| `-KeaserAccountsEditing` | `1` opens the Accounts sheet in edit mode | home |
| `-KeaserChartSelection` | `last` or a bar index: shows the long-press callout | home |
| `-KeaserSettingsPage` | `account`, `categories`, `newCategory`, `editCategory`, `paymentMethods`, `newPaymentMethod`, `editPaymentMethod`, `currency`, `startWeek`, `smartSuggestions`, `weeklySummary`, `shortcut`, `tutorials`, `tutorialShortcut`, `tutorialWallet`, `whatsNew`, `release`, `help`, `followUs`, `privacy`, `terms` | settings |
| `-KeaserSettingsScroll` | `bottom` (also scrolls the label editor to Reset to Default) | settings |
| `-KeaserSnippet` | `confirm`, `confirmPlain`, `result`, `wallet`: the shortcut's expense card (the real `ExpenseCardView`) in a stand-in of the system card over a plain lock screen; `confirm` is the interactive iOS 26+ card, `confirmPlain` the iOS 18 to 25 one | shortcuts |
| `-KeaserSnippetLong` | `1` gives the card a long title and a long account name | shortcuts |
| `-KeaserSettingsAlert` | `rename`: the Rename Account alert, with `-KeaserSettingsPage account` | settings |
| `-KeaserPro` | `purchased`, `expired`, `never` | settings |
| `-KeaserProPrices` | `sample` (fake prices; simctl launches cannot use the StoreKit configuration) | settings |
| `-KeaserPaywallFeature` | a `ProFeature` raw value to highlight | settings |
| `-KeaserPaywallPlans` | `all`: every plan showing (after "Show more plans") | settings |
| `-KeaserSampleLinks` | `1` fills Help and Follow Us with sample links | settings |
| `-KeaserOpenExpense` | `first` (the newest expense in any account) or an index into every expense, newest first: the route `OpenExpenseIntent` and a tapped Spotlight result leave (its account selected, Edit Expense over Home) | intents |
| `-KeaserOpenAccount` | an account index: the route `OpenAccountIntent` leaves (the account selected, Home with nothing over it) | intents |
| `-KeaserOpenSearch` | search text: the route `SearchExpensesIntent` leaves (Search with the results, keyboard down) | intents |
| `-KeaserSelectAccount` | an account index selected at launch, with a seed; `1` with seed `demo` starts on Business, to see an opened Personal expense switch back | intents |
| `-KeaserSpotlight` | `index`: a seeded launch writes its data to Spotlight too (seeded launches normally never index) | intents |

Seeded launches keep the database in memory and never touch the real file.

## Shared names

- App Intents: `AddExpenseIntent` (title "Add Expense") and
  `LogWalletTransactionIntent` (title "Log Wallet Transaction"). Tutorials
  refer to them by these titles.
- `AddExpenseIntent` and its entities are declared in `KeaserWidgets/Shared/`
  and compiled into both targets, because the Add Expense control names the
  intent. The app implements `perform()` in `Keaser/Intents/AddExpenseFlow.swift`;
  the extension's copy only has a fallback `perform()` (in
  `AddExpenseControl.swift`). `supportedModes` (iOS 26), `allowedExecutionTargets`
  `.main` (iOS 27) and an app-only `ForegroundContinuableIntent` conformance
  (earlier systems) keep it in the app's process so it can prompt over the
  lock screen. The flow's rules (step order, skips, Go Back targets) live in
  `ShortcutFlow` (KeaserKit/Platform); the confirmation card's draft lives in
  `AddExpenseDrafts`, keyed by session.
- Deep links: `keaser://new-expense`, `keaser://settings` (see `AppRouter`).
  App Intents and Spotlight results use the routes `AppRouter.Route.expense(UUID)`
  (select its account, Edit Expense), `.account(UUID)` (select it, Home) and
  `.search(String)` (Search with the text); `HomeView.handle(_:)` follows them.
- Siri, Spotlight and Shortcuts entities: `ExpenseEntity` (app only,
  `Keaser/Intents/ExpenseEntity.swift`; an `IndexedEntity` whose
  `ExpenseEntityQuery` resolves IDs in every account, matches titles and
  suggests recent expenses), plus `AccountEntity`, `CategoryEntity` and
  `PaymentMethodEntity` in `KeaserWidgets/Shared` (each with a Name property
  and a string query; the Go Back sentinels are untouched). Only the app's
  copy of `AccountEntity` is indexed (`Keaser/Intents/AccountIndexing.swift`).
  Their lookups live in `EntityCatalog` (KeaserKit/Platform).
- Open and search intents: `OpenExpenseIntent` ("Open Expense"),
  `OpenAccountIntent` ("Open Account"), `SearchExpensesIntent` ("Search
  Expenses") and, on iOS 27, the assistant-only `SearchInKeaserIntent`
  (`.system.searchInApp`). There is no `.system.open` version: the schema is
  iOS 27 only and a second OpenIntent for the same entity fails the build
  ("OpenIntent targets should be unique"). All four require
  `.requiresLocalDeviceAuthentication` (the search schema refuses anything
  less); Add Expense and Log Wallet Transaction keep working while locked.
  App Shortcut phrases may only interpolate AppEntity or AppEnum parameters,
  so the search phrases carry no term.
- Spotlight: `SpotlightIndexer` keeps the named index `SpotlightPlan.indexName`
  in step with every `StoreChange` (on device, all expenses and accounts, no
  setting). It remembers what it wrote in
  `Application Support/Keaser/spotlight-index.json` and writes only the
  difference; a new build or `SpotlightPlan.formatVersion` rebuilds the whole
  index, so bump that whenever what `ExpenseEntity` indexes changes. Seeded
  launches never index. Intents that save call `SpotlightIndexer.shared.flush()`
  (through `IntentSupport.save`).
- On-screen awareness: `.keaserEntity(expense:)` and `.keaserEntity(account:)`
  (`Keaser/Intents/EntityAnnotations.swift`, iOS 18.4+, no visual change) on
  Home and Search rows (`HomeExpenseRows`), Home's top bar and the expense
  editor.
- Pro features (`ProFeature`): Widgets, More Filters (category and payment
  filters), Multiple Accounts (more than one account), Long-term Insights
  (This Year and All Time periods). Gate on `ProStore.isPro` in the app and
  `ProEntitlement.isPro(_:now:)` in the widget. The purchase is cached in
  `Preferences` (`hasProPurchase`, `proExpirationDate`); when the cached end
  passes, the widget confirms with StoreKit before locking
  (`ProEntitlement.needsStoreKitCheck`).

## Where things live

| Area | Files |
|---|---|
| foundation | `project.yml`, `Keaser/App/` (incl. `AppLinks.swift`), `Keaser/Design/Theme.swift`, `Glass.swift`, `Components.swift`, `Packages/KeaserKit/Sources/KeaserKit/{Models,Store}`, `Logic/{Period,MoneyFormat,ProEntitlement}.swift`, `scripts/*.sh` |
| onboarding-platform | `Keaser/Features/{Onboarding,Welcome}/`, `Keaser/Design/KeaserLogo.swift`, `Keaser/Intents/`, `Keaser/Notifications/`, `KeaserWidgets/`, app icon |
| home-expenses | `Keaser/Features/{Home,Accounts,ExpenseEditor}/` |
| shortcuts | `Keaser/Intents/`, `KeaserWidgets/AddExpenseControl.swift`, `KeaserWidgets/Shared/{AddExpenseIntent,ExpenseEntities}.swift`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{QuickLog,ShortcutFlow}.swift`, the Shortcut page in `Keaser/Features/Settings/PreferencePages.swift` |
| settings-pro | `Keaser/Features/{Settings,Paywall}/`, `Keaser/Resources/Keaser.storekit`, `Keaser/Resources/Legal/` |
| intents | `Keaser/Intents/{ExpenseEntity,AccountIndexing,OpenIntents,SearchIntents,SpotlightIndexer,EntityAnnotations,KeaserShortcuts}.swift`, the string queries in `KeaserWidgets/Shared/{AccountEntity,ExpenseEntities}.swift`, the open and search routes in `Keaser/App/AppEnvironment.swift` and `HomeView.handle(_:)`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{EntityCatalog,SpotlightPlan}.swift` |

Logic for each area lives in `Packages/KeaserKit/Sources/KeaserKit/<Area>/`
(`Home`, `Settings`, `Platform`) with tests in
`Packages/KeaserKit/Tests/KeaserKitTests/<Area>*Tests.swift`, and its
screenshot list in `scripts/shots/<area>.txt`.
