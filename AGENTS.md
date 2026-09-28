# Keaser

iOS SwiftUI expense tracker: accounts, expenses, categories, payment methods,
charts, filters, a spending widget, Shortcuts, weekly summary notifications, and a
Keaser Pro upgrade with a 7-day pass. Light and dark, monochrome,
Liquid Glass on iOS 26+.

- `Packages/KeaserKit/` - models, persistence, the `KeaserStore`, and all pure
  logic. Foundation only (no SwiftUI, UIKit or WidgetKit). Tested on the Mac with
  `./scripts/test.sh` (Swift Testing), no simulator needed. Anything testable
  belongs here, with `public` access.
- `Keaser/` - the app: SwiftUI views, App Intents, notifications, StoreKit.
- `KeaserWidgets/` - WidgetKit extension (the medium Spending widget, and the
  Add Expense and Scan Receipt controls).

The Xcode project is generated. After editing `project.yml`, run
`xcodegen generate`. Never hand-edit `Keaser.xcodeproj` (it is gitignored).

## Commands

    ./scripts/build.sh           # xcodegen + simulator build; prints errors only
    ./scripts/test.sh            # KeaserKit tests on the Mac
    ./scripts/screenshots.sh     # headless screenshots from scripts/shots/*.txt
    ./scripts/screenshots.sh home   # one area only
    SIM="Keaser home" ./scripts/screenshots.sh home   # use your own simulator
    ./scripts/intents-test.sh    # App Intents through the system (AppIntentsTesting, iOS 27 sim, ~7 min)
    KEASER_MODEL_EVALS=1 ./scripts/eval.sh   # opt-in on-device model evals (Mac with Apple Intelligence)

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

- The Spending widget is the only widget, and medium only (no small, large or
  lock screen families): `SpendingSnapshot.spentCaption` ("Spent This Month")
  over the total, centred, for Today, This Week, This Month or This Year, plus
  its Pro-locked and no-account states. It draws from `WidgetPalette`
  (KeaserWidgets/Shared/SpendingWidgetView.swift), not Theme: the surface is
  white / 20,20,20 and the caption grey 0.46 / 0.58, measured from the
  reference widgets. Onboarding page 2's illustration still animates a small
  "This Month" widget from the recording (`SpendingWidgetView` with
  `.systemSmall`, kept for it alone) on its own measured charcoal
  (`OnboardingPalette.widgetSurface`).

- The app icon is an Icon Composer document, `Keaser/Resources/AppIcon.icon`
  (black fill, the mark as one glass SVG layer), written by
  `swift scripts/make_icon.swift`; never edit it by hand or keep an
  `AppIcon.appiconset` beside it (Xcode ignores the set). Xcode renders the
  flat iOS 18 to 25 icons from it. `--previews DIR` renders the default, dark,
  clear and tinted looks with ictool.

- Screens that sit under an inline navigation bar start 4pt lower on iOS 27
  than on the iOS 26 reference; `settingsListStyle` (SettingsListInset) and the
  paywall take it off on iOS 27 only, so pass margins as iOS 26 lays them out.
- Theme tokens beyond the basics: `keaserCaptionText` (settings section titles
  and footnotes), `keaserListSeparator` (settings list hairlines; sheets and cards
  keep `keaserSeparator`), `keaserSnippetLabel` (the expense card's labels and
  symbols), `keaserSwipeAction` (the Edit swipe action).
- Screenshot timing: the first shot of a fresh install can catch a sheet
  mid-presentation; retake it or use `SETTLE=10`. The system argument
  `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXXL` (or an
  `...Accessibility...` size) sets the text size for one shot.

- The Home chart's long-press callout (`ChartCallout` in HomeSummaryCard.swift)
  is small Liquid Glass tinted with a breath of `keaserInk`, by the founder's
  choice over the recording's larger opaque tag: keep its look when matching
  the reference elsewhere. Its placement (clear of the total) is separate.
- Tapping an expense (Home, Search, Open Expense, a Spotlight result) opens
  its details (`ExpenseDetailSheet`: the Add Expense card, read only, with
  Edit and Delete), not Edit Expense as the recording does: the founder's
  choice. Edit turns the sheet into Edit Expense (`onClose` brings the
  details back); long press and swipe still edit or delete directly.
- Receipts are Keaser's own addition to the reference: one card under the
  editor's card (`ReceiptAttachmentSection`: "Attach Receipt" with a
  paperclip, one menu for Scan Receipt and Choose Photo; once attached, the
  thumbnail with View Receipt and a red Remove) and, when there is a photo,
  one under the details' card (`ReceiptDetailRow`). The card, rows and
  header above them stay as the reference has them. Both open
  `ReceiptViewer` full screen (zoom, Close, Share). A scan from the title
  row's glyph fills the card as before and attaches its photo; the receipt
  card comes before the "Filled in from your receipt" note.

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
`smartSuggestionsEnabled`, which drives New Expense); Add Expense and Log Wallet
Transaction both follow the shortcut switch. Smart Suggestions rank a category
as history > word rule on a built-in category > on-device model > word rule on
a custom category (measured on the Mac with `scripts/eval.sh`). A payment
method never comes from the model, but in an account with no payment history
any recognised category, the model's included, brings the Cash fallback
(`SmartSuggester.guessLabels`). Week maths must use
`store.preferences.calendar` (it honours Start Week On).

Receipt photos are files, never in the JSON: `Expense.receipt` is an optional
`ReceiptPhoto` (just an ID, decoded tolerantly), and `ReceiptFolder`
(KeaserKit/Store) keeps one JPEG per photo, `receipt-<UUID>.jpg`, in
`Keaser/Receipts/` next to the database (same app group and fallback), with
complete file protection. A photo is written once, on Save
(`ExpenseEditorView.save()`); until then an attached one is only in memory
(`UnsavedReceipt`), so Cancel leaves nothing behind, and replacing or removing
one never touches the old file. `ReceiptImage` (the app) makes the JPEG: pages
stacked, each at most 2000 px on its long side, upright, sRGB, quality 0.8,
no metadata. Deleting an expense or an account leaves its photos, so
`KeaserStore.restore(_:)` (Delete Expense's undo) gets them back whole;
`AppEnvironment.removeOrphanedReceipts()` runs once at launch and removes the
photos no expense refers to that are older than `ReceiptFolder.gracePeriod`
(a day), and nothing while the database is unreadable or has no account
(`KeaserStore.receiptPhotosInUse`). Seeded launches use a temporary
`SeededReceipts` folder (`AppEnvironment.receipts`), emptied at each launch.

## Launch arguments (DEBUG only)

| Argument | Values | Area |
|---|---|---|
| `-KeaserSeed` | `fresh`, `onboarded`, `account`, `single`, `demo` | foundation |
| `-KeaserSheet` | `settings`, `paywall` (presented by `RootView` over whatever is showing); `settingsPaywall` opens Settings with the paywall on a second sheet over it, as Upgrade does | foundation |
| `-KeaserOnboardingPage` | `0`...`4`; `widgetGallery` (the Spending widget for Today, This Week and This Month), `widgetGalleryLocked` (the widget once the pass is over, and without an account); both need seed `fresh` | onboarding |
| `-KeaserGalleryRendering` | `accented`: the gallery's widgets as a tinted or clear home screen draws them (glass, white content, a stand-in tint on the total) | platform |
| `-KeaserNotifState` | `granted`, `denied`: page 4 in its end state without the system prompt; with `-KeaserSettingsPage weeklySummary`, `denied` shows the summary on and notifications off | onboarding, settings |
| `-KeaserLetter` | `1` shows the welcome letter over Home | onboarding |
| `-KeaserLetterPage` | `tldr`, `follow` (sample links, DEBUG only) | onboarding |
| `-KeaserSheet` | `accounts`, `addAccount`, `newExpense`, `expense` (the newest expense's details), `editExpense`, `search` | home |
| `-KeaserPeriod` | `today`, `thisWeek`, `thisMonth`, `thisYear`, `allTime` | home |
| `-KeaserSearch` | search text, with `-KeaserSheet search` | home |
| `-KeaserExpenseTitle` | text typed into New Expense (shows Smart Suggestions) | home |
| `-KeaserExpenseFocus` | `amount`: then moves on to Amount (shows the guessed category and payment); `none`: the keyboard stays down, to see the receipt card and Delete under the card | home |
| `-KeaserReceiptAttached` | `1` (the grocery sample) or a `ReceiptSamples` name: that sample, printed onto paper by `ReceiptImageRenderer`, is kept with the selected account's newest expense (seeded folder), for `-KeaserSheet expense` and `editExpense`; with `newExpense` it starts New Expense with the sample attached, unsaved | home |
| `-KeaserReceiptViewer` | `1`: with a receipt showing (`-KeaserReceiptAttached`), opens it full screen in the details or the editor | home |
| `-KeaserOpenURL` | a deep link taken through `AppRouter` as if a widget or control opened it; `keaser://scan-receipt` with `-KeaserReceipt <sample> -KeaserReceiptImage 1` shows the Scan Receipt control's route reading and attaching that sample instead of opening the camera | home |
| `-KeaserAccountsEditing` | `1` opens the Accounts sheet in edit mode | home |
| `-KeaserChartSelection` | `last` or a bar index: shows the long-press callout | home |
| `-KeaserCurrency` | an ISO code (`RWF`, `JPY`...): the seed's currency | home |
| `-KeaserAmountScale` | a whole number every seeded amount is multiplied by; with `-KeaserCurrency RWF` and `5000`, seed `single` shows RWF 100,000 | home |
| `-KeaserSettingsPage` | `account`, `categories`, `newCategory`, `editCategory`, `paymentMethods`, `newPaymentMethod`, `editPaymentMethod`, `currency`, `startWeek`, `smartSuggestions`, `weeklySummary`, `shortcut`, `tutorials`, `tutorialShortcut`, `tutorialWallet`, `whatsNew`, `release`, `help`, `followUs`, `privacy`, `terms` | settings |
| `-KeaserSettingsScroll` | `bottom` (also scrolls the label editor to Reset to Default); or a word: with `-KeaserSettingsPage privacy` or `terms`, starts at the first heading containing it | settings, intelligence |
| `-KeaserSnippet` | `confirm`, `confirmPlain`, `result`, `wallet`: the shortcut's expense card (the real `ExpenseCardView`) in a stand-in of the system card over a plain lock screen; `confirm` is the interactive iOS 26+ card, `confirmPlain` the iOS 18 to 25 one; `confirmAccount`, `confirmCategory`, `confirmPayment`: the interactive card with that detail tapped, its options listed inside the card | shortcuts |
| `-KeaserSnippet` | `spending`: the answer of "How Much Did I Spend" (`SpendingSnippetView`) for the selected account, This Week unless `-KeaserPeriod` says otherwise | intents |
| `-KeaserSnippetLong` | `1` gives the card a long title and a long account name | shortcuts |
| `-KeaserSnippetOptions` | `many` gives the account twelve more categories, so an open category list pages | shortcuts |
| `-KeaserSnippetPage` | `n` (from 1): the page of the open list shown; without it, the page with the chosen option | shortcuts |
| `-KeaserSettingsAlert` | `rename`: the Rename Account alert, with `-KeaserSettingsPage account` | settings |
| `-KeaserPro` | `purchased`, `expired`, `never` | settings |
| `-KeaserProPrices` | `sample` (fake prices; simctl launches cannot use the StoreKit configuration) | settings |
| `-KeaserPaywallFeature` | a `ProFeature` raw value to highlight | settings |
| `-KeaserPaywallPlans` | `all`: every plan showing (after "Show more plans") | settings |
| `-KeaserSampleLinks` | `1` fills Help and Follow Us with sample links | settings |
| `-KeaserCategoryModel` | a category name: a stand-in for the on-device model that picks it about a second after being asked; `none` picks nothing; `off` is a device without Apple Intelligence (no model, no footer sentence, receipts read by the heuristics alone) | intelligence |
| `-KeaserReceipt` | a `ReceiptSamples` name (`coffee`, `grocery`, `cafe-paris`, `not-a-receipt`, `tip-suggestions`, `cash-change`, `gross-net`, `cable`, ...): New Expense reads that sample receipt as if it had just been scanned | intelligence |
| `-KeaserReceiptImage` | `1`: with `-KeaserReceipt`, prints the sample onto an image first and reads it with Vision, the whole way a photo goes | intelligence |
| `-KeaserReceiptHold` | `1`: with `-KeaserReceipt`, keeps the receipt reading (the spinner in the title row) | intelligence |
| `-KeaserOpenExpense` | `first` (the newest expense in any account) or an index into every expense, newest first: the route `OpenExpenseIntent` and a tapped Spotlight result leave (its account selected, the expense's details over Home) | intents |
| `-KeaserOpenAccount` | an account index: the route `OpenAccountIntent` leaves (the account selected, Home with nothing over it) | intents |
| `-KeaserOpenSearch` | search text: the route `SearchExpensesIntent` leaves (Search with the results, keyboard down) | intents |
| `-KeaserSelectAccount` | an account index selected at launch, with a seed; `1` with seed `demo` starts on Business, to see an opened Personal expense switch back | intents |
| `-KeaserSpotlight` | `index`: a seeded launch writes its data to Spotlight too (seeded launches normally never index) | intents |

Seeded launches keep the database in memory and never touch the real file.

## Shared names

- App Intents: `AddExpenseIntent` (title "Add Expense") and
  `LogWalletTransactionIntent` (title "Log Wallet Transaction"). Tutorials
  refer to them by these titles, and to Add Expense's fields by its
  parameter titles: Title, Amount, Category, Payment Method, Account and
  Date (never asked for; empty means the moment it is added, and a Wallet
  automation sets it to Current Date). In the app Add Expense returns the
  `ExpenseEntity` it saved.
  With nothing on screen (`IntentSystemContext.isVoiceOnly`, iOS 27) it asks
  the confirmation out loud (`QuickLog.confirmationQuestion`) and ends on a
  spoken sentence (`QuickLog.confirmation`) instead of the card.
- The confirmation card (iOS 26+): tapping Account, Category or Payment
  opens that detail's options inside the card (`ShortcutCardList`: names
  only, the chosen one checked, two columns (standard text sizes only) or
  pages with More when long, Go Back when it is on); picking one sets it and
  closes the list. The taps are the non-discoverable
  `ShowExpenseCardOptionsIntent`, `PickExpenseCardOptionIntent`,
  `PageExpenseCardOptionsIntent` and
  `CloseExpenseCardOptionsIntent`, which only change the draft in
  `AddExpenseDrafts`; `ExpenseCardSnippetIntent` then draws the card again.
  The closed card must stay as the reference has it.
- "How Much Did I Spend" (`GetSpendingIntent`): period (`SpendingPeriod`,
  This Week by default), account (the selected one when empty), category
  and payment method. Answered by `SpendingQuestion` exactly as Home totals
  (week start, Pro): This Year, All Time and the filters need Pro, and
  without it the intent says so (`SpendingOutcome.refusal`, thrown as an
  `IntentRefusal`) rather than answering. Returns the total as a currency
  amount; the card is the medium widget's caption over the total
  (`SpendingSnippetView`). Needs an unlocked iPhone.
- "Delete Expense" (`DeleteExpenseIntent`, a `DeleteIntent` over
  `ExpenseEntity`): asks by name first, deletes through
  `KeaserStore.delete(_:)` (which puts everything back if the save fails),
  then refreshes widgets, the weekly summary and Spotlight
  (`IntentSupport.delete`). On iOS 26+ it is an `UndoableIntent`: undo in
  Keaser calls `KeaserStore.restore(_:)`. Needs an unlocked iPhone.
- App Shortcuts: 7 of the 10 allowed (Add Expense, Log Transaction,
  Spending, Search, Open Account, Open Expense, Delete Expense).
- `AddExpenseIntent` and its Category and Payment Method entities are app-only
  (`Keaser/Intents/`); the app implements `perform()` in
  `Keaser/Intents/AddExpenseFlow.swift`. The Add Expense control
  (`KeaserWidgets/AddExpenseControl.swift`) does NOT run it: iOS gives a
  control's action no way to ask questions, so a control running Add Expense
  silently did nothing on the device. It opens `keaser://new-expense`
  (`OpenURLIntent`) instead. The Scan Receipt control
  (`KeaserWidgets/ScanReceiptControl.swift`, "Photograph a receipt to add an
  expense.") opens `keaser://scan-receipt` the same way: New Expense
  (`HomeSheet.scanReceipt`, `ExpenseEditorView(scansReceipt:)`) with the
  document camera up at once, or the photo picker without a camera; the scan
  fills the card and attaches its photo, and the person saves. Closing the
  camera leaves New Expense ready to type. The flow's rules (step order, skips, Go Back targets) live in
  `ShortcutFlow` (KeaserKit/Platform); the confirmation card's draft lives in
  `AddExpenseDrafts`, keyed by session.
- Writing intents (Add Expense, Log Wallet Transaction, Delete Expense) wait at
  most 3 s for the Spotlight flush and 3 s for the weekly summary
  (`WeeklySummaryScheduler.intentWait`); the summary is handed to a private
  serial queue because the notification calls can block. Every Spotlight write,
  including iOS 27 re-index requests, goes through one `SerialWork` queue
  (KeaserKit/Platform); the index manifest lives in `Library/Caches/Keaser/`
  so a restored backup rebuilds the index.
- Add Expense: a supplied amount in another currency always gets the
  confirmation (with `ShortcutCard.otherCurrencyNote`); nothing is converted.
  `ShortcutFlow` keeps a category or payment method the person picked when
  moving forward again, until the title or account changes. The in-card option
  list is fitted to the text size (`ShortcutCardList.Source.list(forLineHeight:)`):
  `lines(forLineHeight:)` gives 7 lines up to Large, down to 3, to stay under
  the 340pt snippet limit, and `allowsTwoColumns(forLineHeight:)` keeps every
  list in one column at the accessibility sizes. Two columns share rows
  (`ShortcutCardList.rows`) so their names sit on one baseline. The open
  detail's header stays one line: when its label and value do not both fit,
  the value takes the label's place.
- App Intents tests (`KeaserIntentTests`, 31 tests): every test resets data with
  the DEBUG `ResetTestDataIntent` (`IntentTestFixture`, fixed IDs). AppIntentsTesting
  accepts confirmations on its own, so confirmation paths are device-only checks.
  Spotlight searches go through `IntentTestCase.spotlight(_:_:)`, bounded at 40 s.
- Deep links: `keaser://new-expense`, `keaser://scan-receipt`, `keaser://settings`
  (see `AppRouter.route(for:)`).
  App Intents and Spotlight results use the routes `AppRouter.Route.expense(UUID)`
  (select its account, the expense's details), `.account(UUID)` (select it, Home) and
  `.search(String)` (Search with the text); `HomeView.handle(_:)` follows them.
- Siri, Spotlight and Shortcuts entities: `ExpenseEntity` (app only,
  `Keaser/Intents/ExpenseEntity.swift`; an `IndexedEntity` whose
  `ExpenseEntityQuery` resolves IDs in every account, matches titles and
  suggests recent expenses), plus `AccountEntity` (`KeaserWidgets/Shared`,
  also used by the widget's configuration), `CategoryEntity` and
  `PaymentMethodEntity` (`Keaser/Intents/ExpenseEntities.swift`) (each with a Name property
  and a string query; the Go Back sentinels are untouched). Only the app's
  copy of `AccountEntity` is indexed (`Keaser/Intents/AccountIndexing.swift`).
  Their lookups live in `EntityCatalog` (KeaserKit/Platform).
- Open and search intents: `OpenExpenseIntent` ("Open Expense"),
  `OpenAccountIntent` ("Open Account"), `SearchExpensesIntent` ("Search
  Expenses"). There is deliberately no `.system.searchInApp` intent: on
  iOS 27 Siri routed questions such as "how much did I spend this week in
  Keaser" to it and opened the app instead of answering. There is no
  `.system.open` version either: a second OpenIntent for the same entity
  fails the build ("OpenIntent targets should be unique"). All three
  require `.requiresLocalDeviceAuthentication`; Add Expense and Log Wallet
  Transaction keep working while locked.
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
- App Intents tests: `KeaserIntentTests` (a UI-test bundle, iOS 27 only,
  run by `./scripts/intents-test.sh` on the simulator "Keaser intents
  test") performs every intent and entity query through the system with
  AppIntentsTesting, including Spotlight searches and the entities views
  say are on screen. It never imports the app: intents, entities, enum
  cases and parameters are named as declared (`definitions.intents["AddExpenseIntent"]`,
  `makeIntent(expenseTitle:)`, `"thisWeek"`), so renaming any of them must
  be done in the tests too. Every test launches Keaser, then starts from
  `IntentTestFixture` (Personal full of demo expenses and selected, Business
  empty), written to the real file by `ResetTestDataIntent` (Debug builds
  only, not discoverable). Tests read the screen through accessibility and
  never tap.
- Errors on iOS 27: `KeaserIntentError` and `IntentRefusal` adopt
  `CustomAppIntentErrorConvertible`. No account yet is
  `AppIntentError.UserActionRequired.accountSetup`; a deleted expense or
  account, or a label the account lacks, is `Unrecoverable.entityNotFound`;
  everything else (Pro, amounts, locked data) keeps its sentence only.
- Donations: saving a new expense in New Expense donates Add Expense with
  its title, amount, category, payment method and account, never its date
  (`IntentDonations.addedInApp`, one call in `ExpenseEditorView.save()`).
  Edits donate nothing.
- The weekly summary notification names the account it reports
  (`WeeklySummaryPlan.accountID`, `appEntityIdentifiers` on iOS 27).
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
| onboarding-platform | `Keaser/Features/{Onboarding,Welcome}/`, `Keaser/Design/KeaserLogo.swift`, `Keaser/Intents/`, `Keaser/Notifications/`, `KeaserWidgets/`, `Keaser/Resources/AppIcon.icon` and `scripts/make_icon.swift` (app icon) |
| platform | `Keaser/Design/ReadableWidth.swift` (the readable column for wide windows on iPad and in iPhone Mirroring, and clearing iPad window controls), `Keaser/Design/SwipeActions.swift` (iOS 27 swipe to edit or delete on Home and search rows), `WidgetInks` (full colour vs accented and vibrant styles) in `KeaserWidgets/Shared/SpendingWidgetView.swift`, `scripts/shots/platform.txt` |
| home-expenses | `Keaser/Features/{Home,Accounts,ExpenseEditor}/`; receipts kept with expenses: `ReceiptAttachment.swift` (the editor's receipt card, the details' row, thumbnails), `ReceiptViewer.swift` (full screen, zoom, share), `ReceiptImage.swift` (JPEG making, DEBUG samples) in `Keaser/Features/ExpenseEditor/`, `Packages/KeaserKit/Sources/KeaserKit/Models/ReceiptPhoto.swift`, `Store/ReceiptFolder.swift` (files, orphans) |
| shortcuts | `Keaser/Intents/`, `KeaserWidgets/AddExpenseControl.swift`, `KeaserWidgets/ScanReceiptControl.swift`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{QuickLog,ShortcutFlow,ShortcutCardList,WalletAmount}.swift` (`WalletAmount` reads Log Wallet Transaction's text amount in any number style), the Shortcut page in `Keaser/Features/Settings/PreferencePages.swift` |
| settings-pro | `Keaser/Features/{Settings,Paywall}/`, `Keaser/Resources/Keaser.storekit`, `Keaser/Resources/Legal/` |
| intelligence | `Keaser/Intelligence/` (`CategoryModels`: the model the app uses, DEBUG stand-in; `ReceiptScanner`: reads a scan for New Expense, DEBUG samples), `Keaser/Features/ExpenseEditor/ReceiptScanButton.swift` (the title row's scanner glyph; `ReceiptCaptureRequest` and `receiptCapture`, the document camera and photo picker the editor presents for scanning and attaching), `Packages/KeaserKit/Sources/KeaserIntelligence/` (Vision and Foundation Models on device, linked by the app only: `AppleIntelligence` availability, `OnDeviceCategoryModel`, `ReceiptTextRecognizer`, `OnDeviceReceiptModel`, DEBUG `ReceiptImageRenderer`), `Packages/KeaserKit/Sources/KeaserKit/Intelligence/` (`CategoryPrompt`, `CategoryModel`, `SmartLabels`, `Deadline`, the async `ShortcutFlow` steps; receipts: `ReceiptText`, `ReceiptParser`, `ReceiptReading`, `ReceiptDraft`, DEBUG `ReceiptSamples`), opt-in model evaluation `scripts/eval.sh` (`Tests/KeaserIntelligenceEvals`, Mac with Apple Intelligence) |
| intents | `Keaser/Intents/{ExpenseEntity,AccountIndexing,OpenIntents,SearchIntents,SpotlightIndexer,EntityAnnotations,KeaserShortcuts,GetSpendingIntent,DeleteExpenseIntent,IntentRefusal,IntentDonations,TestDataIntent}.swift`, the string queries in `KeaserWidgets/Shared/AccountEntity.swift` and `Keaser/Intents/ExpenseEntities.swift`, the open and search routes in `Keaser/App/AppEnvironment.swift` and `HomeView.handle(_:)`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{EntityCatalog,SpotlightPlan,SpendingAnswer,ExpenseDeletion,IntentTestFixture}.swift`, `KeaserIntentTests/`, `scripts/intents-test.sh` |

Logic for each area lives in `Packages/KeaserKit/Sources/KeaserKit/<Area>/`
(`Home`, `Settings`, `Platform`) with tests in
`Packages/KeaserKit/Tests/KeaserKitTests/<Area>*Tests.swift`, and its
screenshot list in `scripts/shots/<area>.txt`.
