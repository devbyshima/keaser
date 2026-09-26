# Keaser

iOS SwiftUI expense tracker: accounts, expenses, categories, payment methods,
charts, filters, widgets, Shortcuts, weekly summary notifications, optional
Notion sync, and a Keaser Pro upgrade with a 7-day pass. Dark only, monochrome,
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
  simulator runtime is iOS 18.6, so that is what screenshots show.
- Liquid Glass (iOS 26+) only through `Keaser/Design/Glass.swift`
  (`keaserGlass(in:)`, `keaserGlassButtonStyle()`, `KeaserGlassContainer`),
  which falls back to materials on iOS 18. Never call `glassEffect` directly.
- Swift 6 language mode. `KeaserStore` and views are `@MainActor`.
- Dark only: `RootView` is forced to `.dark`; the palette is in
  `Keaser/Design/Theme.swift`. Do not introduce other accent colours.

## Data

One JSON file (`DatabaseFile.shared`) in the app group
`group.com.fulltimestudio.keaser`, read by the widget extension. All writes go
through `KeaserStore` (injected with `@Environment(KeaserStore.self)`, or
`AppEnvironment.store` outside views). Each mutation saves immediately and
notifies observers (`addObserver`) with a `StoreChange`. Money is `Decimal`;
format it with `MoneyFormat.string(_:currencyCode:)` using
`store.preferences.currencyCode`. Week maths must use
`store.preferences.calendar` (it honours Start Week On).

## Launch arguments (DEBUG only)

| Argument | Values | Owner |
|---|---|---|
| `-KeaserSeed` | `fresh`, `onboarded`, `account`, `single`, `demo` | foundation |
| `-KeaserOnboardingPage` | `0`...`5` | onboarding |
| `-KeaserLetter` | `1` shows the welcome letter over Home | onboarding |
| `-KeaserSheet` | `accounts`, `addAccount`, `newAccount`, `newExpense`, `editExpense`, `search` | home |
| `-KeaserSheet` | `settings`, `paywall`, `notion` (presented by `RootView` over whatever is showing) | foundation |
| `-KeaserSettingsPage` | `account`, `categories`, `newCategory`, `paymentMethods`, `currency`, `startWeek`, `smartSuggestions`, `shortcut`, `tutorials`, `whatsNew`, `help`, `followUs`, `privacy`, `terms` | settings |
| `-KeaserPeriod` | `today`, `thisWeek`, `thisMonth`, `thisYear`, `allTime` | home |

Seeded launches keep the database in memory and never touch the real file.

## Shared names

- App Intents: `AddExpenseIntent` (title "Add Expense") and
  `LogWalletTransactionIntent` (title "Log Wallet Transaction"). Tutorials and
  the Shortcut settings page refer to them by these titles.
- Deep links: `keaser://new-expense`, `keaser://settings` (see `AppRouter`).
- Pro features (`ProFeature`): Widgets, More Filters (category and payment
  filters), Multiple Accounts (more than one account), Long-term Insights
  (This Year and All Time periods). Gate on `ProStore.isPro` in the app and
  `ProEntitlement.isPro(_:now:)` in the widget.

## Ownership (while the parallel build is running)

| Area | Owns |
|---|---|
| foundation | `project.yml`, `Keaser/App/` (incl. `AppLinks.swift`), `Keaser/Design/Theme.swift`, `Glass.swift`, `Components.swift`, `Packages/KeaserKit/Sources/KeaserKit/{Models,Store}` (except `NotionConnection.swift`), `Logic/{Period,MoneyFormat,ProEntitlement}.swift`, `scripts/*.sh` |
| onboarding-platform | `Keaser/Features/{Onboarding,Welcome}/`, `Keaser/Design/KeaserLogo.swift`, `Keaser/Intents/`, `Keaser/Notifications/`, `KeaserWidgets/`, app icon |
| home-expenses | `Keaser/Features/{Home,Accounts,ExpenseEditor}/` |
| settings-pro | `Keaser/Features/{Settings,Paywall}/`, `Keaser/Resources/Keaser.storekit`, `Keaser/Resources/Legal/` |
| notion | `Keaser/Features/Notion/`, `KeaserKit/Models/NotionConnection.swift`, `KeaserKit/Notion/` |

Each area also owns `Packages/KeaserKit/Sources/KeaserKit/<Area>/`,
`Packages/KeaserKit/Tests/KeaserKitTests/<Area>*Tests.swift` and
`scripts/shots/<area>.txt`. Files marked `STUB (owner: ...)` keep their type
name and public signature; replace the body.
