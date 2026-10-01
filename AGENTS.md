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
- `KeaserWidgets/` - WidgetKit extension (the Spending widget, home screen
  and lock screen, and the Add Expense and Scan Receipt controls).

The Xcode project is generated. After editing `project.yml`, run
`xcodegen generate`. Never hand-edit `Keaser.xcodeproj` (it is gitignored).

## Commands

    ./scripts/build.sh           # xcodegen + simulator build; prints errors only
    CLOUD=1 ./scripts/build.sh   # the same with iCloud sync switched on (see "iCloud sync")
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
- One visual language (founder rule): every new feature must look like
  everything built before it, even where no reference exists. Build it from
  the existing pieces: `KeaserSheetHeader` with `homeSheetHeader()` and
  `homeSheetHeaderButton`, `KeaserCircleButton`, `KeaserCard(fill:)` (sheets
  use `.homeSheetCard`), `KeaserRowSeparator`, `HighlightRowButtonStyle`,
  `KeaserConfirmButton`, `PrimaryButtonStyle`, `.keaserCapsule`,
  `SymbolTile`, `EmptyStateView`, `keaserSheetChrome()`, `keaserBottomBar`,
  `settingsListStyle` for list pages, `keaserGlass` for glass, and the
  Theme tokens, fonts, corner radii and spacing those already use
  (`HomeSheetMetrics` for sheet margins). Never invent a new card, button,
  header, colour, radius or type size when an existing one fits. If one
  genuinely does not fit, say so and extend the shared component in
  `Keaser/Design/` rather than styling a one-off. Before calling a UI
  change done, screenshot it beside an existing screen of the same kind
  (a sheet beside Edit Expense, a list page beside Settings) and compare
  margins, radii, fonts and colours.
- UX and the design language are shared too, not only the UI. A new
  feature flows, behaves, moves and talks like the rest of Keaser:
  - Flows: new things are added the way expenses and accounts are (an Add
    button opens a sheet, typing starts in the first field, Return moves
    to the next, Save closes the sheet and the item appears in place,
    animated). Options live in Settings as a row that pushes a page.
  - Buttons, placement, size and spacing: header controls sit at the
    header's two ends, as 44pt circles (`KeaserCircleButton`,
    `KeaserConfirmButton`) or 44pt glass capsules with 16pt either side of
    the label (`homeSheetHeaderButton`, semibold when it confirms). A
    screen's main action is the full-width ink capsule (`.keaserPrimary`,
    58pt, 18pt semibold) at the bottom (`keaserBottomBar`). An action on a
    sheet's content, such as Delete Expense, is a full-width row at least
    50pt tall in its own card below the content. Margins are 16pt
    (`KeaserMetrics.screenPadding`), cards 16pt apart with radius 26 (rows
    24), sheet content starts at `HomeSheetMetrics.contentTop`, and nothing
    tappable is under 44pt. Reuse these numbers; never eyeball new ones.
  - Gestures: tap opens details, long press opens the Edit and Delete
    menu, and the same gesture never means two things in two places.
  - Feedback: the result shows at once (the list, the totals and the widget
    update); problems appear inline in plain words, never as a dead end.
  - Sheets: the title centred, the confirming action on the right, and on
    the left the xmark `KeaserCircleButton` for a sheet that shows
    things (Accounts, Expense) or Cancel for an edit form (Edit Expense).
    Details before editing, as with expenses.
  - Destructive actions: a confirmation dialog ("Delete Expense?", a
    destructive button with the item's name in quotes, and Cancel). On
    iOS 27, swipe offers Edit and Delete as well.
  - Motion and haptics: `.smooth` animations at about 0.3 s, `.success`
    feedback on saves and deletes, `.selection` on picks.
  - Copy: Title Case for buttons, titles and rows ("Add Account", "Delete
    Expense"), short sentence-case footnotes, plain words, and the same
    name for a thing everywhere (Expense, Account, Category, Payment
    Method).
  - Pro gating follows `ProFeature` and the paywall, empty states use
    `EmptyStateView`, and every control has an accessibility label and
    works at the largest text sizes.

  When a feature needs a pattern Keaser does not have yet, pick the
  closest existing one and say so in the report rather than inventing a
  new one quietly.

- The Spending widget is the only widget, in every iPhone size: small,
  medium, large, extra large portrait (iOS 27 only) and the rectangular,
  circular and inline lock screen families. Every size shows the info the
  same way, and nothing else: `SpendingSnapshot.spentCaption` ("Spent This
  Month") over the total, centred, for Today, This Week, This Month or This
  Year, plus its Pro-locked and no-account states (a locked widget opens
  Settings). The medium's sizes are measured from the reference (footnote
  over a 30pt bold total, 7pt apart); the other home screen sizes are the
  medium sized up or down in the same proportion (`SpendingHeadlineMetrics`:
  small caption 2 over 25pt, large title 3 over 46pt, extra large portrait
  title over 65pt), and a long total (RWF 12,345,678) shrinks to the width
  rather than truncating. The rectangular lock screen widget uses the
  medium's sizes, the circular one `shortCaption` ("Month") over
  `compactTotal()` ("$1.4K"), the inline one `inlineText()` ("Spent This
  Month: $271.37", or `shortInlineText()` where that does not fit), all in
  the system's vibrant style. The small size is kept out of CarPlay. Home
  screen sizes draw from `WidgetPalette`
  (KeaserWidgets/Shared/SpendingWidgetView.swift), not Theme: the surface is
  white / 20,20,20 and the caption grey 0.46 / 0.58, measured from the
  reference widgets. Onboarding page 2's illustration still animates the
  recording's small "This Month" widget (`RecordingSmallWidget` in
  OnboardingIllustrations.swift, not the real small size) on its own
  measured charcoal (`OnboardingPalette.widgetSurface`).

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
- Receipts are Keaser's own addition to the reference, built only from the
  shared pieces (`Keaser/Features/ExpenseEditor/ReceiptAttachment.swift`).
  Under the editor's card (`ReceiptAttachmentSection`): one receipt is a
  row drawn like the suggestion rows (a 30pt thumbnail with the
  `SymbolTile` corner, View Receipt, a chevron), two or more are
  `ReceiptGallery`, then Add Receipt in a card, drawn like Add Account (one
  menu: Scan Receipt, Choose Photos), gone at `ReceiptList.maximum`. The
  details show the same row or gallery under their card
  (`ReceiptDetailSection`) and open at `.large` for two or more (`.medium`
  otherwise); the editor keeps its one `.medium` detent and scrolls. The
  gallery is two columns of equal 3:4 tiles at every text size, with the
  card radius (26) and the cards' 16pt spacing and margins, an odd last
  one in the left column; VoiceOver reads each as "Receipt 2 of 3". A tap
  opens `ReceiptViewer` at that receipt: the sheet header (xmark
  `KeaserCircleButton`, the title "Receipt 2 of 3", Share), swiping
  between the receipts, pinch and double-tap zoom. Removing works as
  deleting an expense does: in the editor a long press on a receipt offers
  View and Remove, and the viewer opened from the editor has Remove
  Receipt under the photo (`KeaserActionCard`, as Delete Expense); both
  ask "Remove Receipt?" and name the receipt in quotes. `.smooth` 0.3 s
  for receipts coming and going, `.success` haptics on removing. The card,
  rows and header above stay as the reference has them; the receipts come
  before the "Filled in from your receipt" note.
- Settings > Tutorials lists Apple Wallet Automation alone. The Add Expense
  Shortcut tutorial (a home-made shortcut on Back Tap or a Run Shortcut
  control) was removed by the founder's choice: Keaser's own Add Expense
  control does the same with nothing to build.

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

Receipt photos are files, never in the JSON: `Expense.receipts` is an ordered
list (oldest first) of `ReceiptPhoto` (just a stable UUID), at most
`ReceiptList.maximum` (10), written only when not empty. Decoding is
tolerant: an entry that does not read loses only that photo, and the single
`receipt` key of earlier builds becomes a list of one. `ReceiptFolder`
(KeaserKit/Store) keeps one JPEG per photo, `receipt-<UUID>.jpg`, in
`Keaser/Receipts/` next to the database (same app group and fallback),
written with `ReceiptFolder.writingOptions` (complete until first user
authentication, as the database; iCloud sync writes its downloads the same
way). The editor holds new photos in memory (`UnsavedReceipt`) and writes
them on Save (`ExpenseEditorView.save()`), so Cancel leaves nothing behind;
a receipt removed in Edit Expense has its file deleted once the edit is
saved (`ReceiptList.released(from:inUse:)`), and Cancel keeps it. Each page
of a document scan and each picked photo is a receipt of its own.
`ReceiptImage` (the app) makes the JPEG: at most 2000 px on the long side,
upright, sRGB, quality 0.8, no metadata. Captures are read only while the
title or the amount is empty (`ReceiptFill.wantsReading`), a scan's pages
together in order as one receipt (`ReceiptReading.read(pages:)`), and fill
only what is still empty: the title, the amount, and the date while the
person has not picked one (`ReceiptFill`). Deleting an expense or an account
leaves its photos, so `KeaserStore.restore(_:)` (Delete Expense's undo) gets
them back whole; `AppEnvironment.removeOrphanedReceipts()` runs once at
launch and removes the photos no expense refers to that are older than
`ReceiptFolder.gracePeriod` (a day), and nothing while the database is
unreadable or has no account (`KeaserStore.receiptPhotosInUse`). Receipts
change only through `KeaserStore.saveExpense`, which stamps `updatedAt` for
sync. Seeded launches use a temporary `SeededReceipts` folder
(`AppEnvironment.receipts`), emptied at each launch.

Money tracking (`docs/plans/money-tracking.md`) has its data and maths in
KeaserKit (phase 1); no screen shows it yet. Payment methods are the wallets:
`PaymentMethod` keeps its name, IDs, intents and sync records and gains
`kind` (`WalletKind`: cash, bank, mobile money, credit card, other; guessed
from the name for older ones and always written, so a rename never changes
it), `currencyCode`, `trackingSince` and `openingBalance` (no
`trackingSince`: Not Tracking), `creditLimit`, `isSavings` and `isHidden`. A
balance is the money in the wallet, so a card that owes 500 is -500 and counts
against the total with no special case. Each `ExpenseCategory` has a `role`
(Expenses or Free Money, guessed and written the same way). An account also
holds `incomeCategories` (Salary, Business, Gifts, Refunds; an account saved
before them gets them when it loads, with IDs derived from the account's, so
two devices never make two sets), `incomes`, `transfers`,
`balanceAdjustments` and its `splitRule`. `WalletKind`, `CategoryRole` and
`TransferKind` are open sets of strings, so a value a later version writes
survives.

A nil `currencyCode` on a wallet means the display currency
(`Preferences.currencyCode`, so the Currency setting still relabels as it
always has); on an expense, income, transfer side or balance adjustment it
means its wallet's. Changing a wallet's currency, or deleting the wallet,
first writes the old currency into what followed it
(`KeaserStore.savePaymentMethod`, `deletePaymentMethod`). Converting goes
through `CurrencyConverter.convert`: the rate saved on the transaction
(`ExchangeRate`), else today's table (`ExchangeRates`, never synced), rounded
to the target currency's places (`CurrencyMath`); what cannot be converted is
left out and counted (`unconverted`), never guessed. A wallet's balance
(`WalletBalances`) starts from the latest balance the person stated (the
opening one, or a `BalanceAdjustment` from Set Balance) and counts only
entries dated after that day, or that day and logged after it, so history is
never edited. Envelopes (`MonthEnvelopes.envelopes`) are per calendar month:
income times each percentage, minus that month's spending by category role
(no category counts as Expenses); Savings progress is the month's `.savings`
transfers. Saving an income makes, keeps or removes its savings transfer in
the same save (`SavingsSplit`): the rule applies to a new income or one no
longer skipped, an income keeps the percentage it was logged with, money that
already moved is never re-rated, and the transfer's ID is derived from the
income's. The label editor saves through `KeaserStore.saveLabel(id:name:symbol:kind:in:)`,
which changes only the name and icon. The store's money methods:
`saveIncome`, `deleteIncome`, `saveTransfer`, `deleteTransfer` (deleting a
savings transfer skips it), `saveIncomeCategory`, `deleteIncomeCategory`,
`moveIncomeCategories`, `setBalance`, `deleteBalanceAdjustment` and
`updateSplitRule`.

`KeaserStore` stamps edit times on what each local edit changes
(`SyncStamps`): `updatedAt` on accounts (name), categories, payment methods,
expenses, income categories, incomes, transfers and balance adjustments,
`categoriesOrderedAt` / `paymentMethodsOrderedAt` /
`incomeCategoriesOrderedAt` on accounts, `SplitRule.updatedAt`,
`Database.accountsOrderedAt`, and `Preferences.settingsUpdatedAt` for the
shared settings. iCloud sync decides between two devices' edits by them, so a
new way of changing data must go through the store (or stamp the same way).
All decode with defaults, so files from before them load unchanged.

## iCloud sync

Built, tested and switched off: the Apple Developer account is a free
personal team, which cannot sign iCloud, CloudKit or push. Every build
compiles the sync code; it runs only when the build has the iCloud
entitlements and the `KeaserCloudSync` Info.plist flag is true
(`CloudSyncSwitch`). Seeded DEBUG launches never sync, nor does an install the
App Intents tests wrote their fixture into.

How it works (KeaserKit `Sync/`, pure and tested; app `Keaser/Cloud/`):

- Records in one custom zone (`SyncSchema.zoneName` "Keaser") of the private
  database of `iCloud.com.fulltimestudio.keaser`. Each has one encrypted
  field, `payload`: a JSON envelope `{body, modifiedAt, parent,
  readerVersion}` where `body` is the model's own JSON. Types and names:
  `Account.<id>` (name, created, updated; what it holds are records of their
  own), `Category.<id>`, `PaymentMethod.<id>` (the wallets), `Expense.<id>`,
  `IncomeCategory.<id>`, `Income.<id>`, `Transfer.<id>`,
  `BalanceAdjustment.<id>` (parent: the account), `SplitRule.<account>` (one
  per account; iCloud's wins on a device's first meeting, as the settings
  do), `Settings` (`SyncedSettings`), `Order.Accounts`,
  `Order.Categories.<account>`, `Order.PaymentMethods.<account>`,
  `Order.IncomeCategories.<account>` (ID lists), and `Receipt.<photo id>` (a
  receipt photo's JPEG as the CKAsset `file`).
  A new kind of data syncs by adding a `SyncKind` to `SyncKinds.all` and a
  `SyncStamps` rule.
- Stays on the device: onboarding and the welcome letter, the weekly
  summary switch, the Pro purchase cache and the selected account. The 7-day
  pass start syncs, earliest wins (one pass per person).
- `SyncPlan` diffs the database against what iCloud holds (`SyncState.known`,
  fingerprints) into saves and tombstoned deletions; `SyncMerge` applies what
  iCloud sent: unchanged here takes iCloud's, both changed takes the later
  edit (ties decided by payload, the same on every device), an edit made
  after a local delete brings the record back, an edit here outlives a delete
  elsewhere, a deleted account takes everything in it along, an item whose
  account has not arrived waits, and same-named labels in an account become
  one. On a device's first sync nothing is sent until iCloud's data has been
  fetched and merged: a never-synced account named like one in iCloud merges
  into it, an empty placeholder account made within the hour gives way, and
  iCloud's settings and orders win.
- Records from later versions are never lost: unknown fields ride along on
  edits, unknown types, a higher `readerVersion` or an unreadable payload are
  parked untouched (`SyncState.parked`).
- `CloudSyncEngine` (an actor, CKSyncEngine) saves fetched changes to the
  state before merging them off the main actor into a copy the store takes
  only if unchanged (`KeaserStore.applyCloudChanges`, one save, one
  `.mergedFromCloud`, so widgets, Spotlight and the weekly summary follow).
  Conflicts and gone records go through the same merge. Signed out or another
  Apple Account: sync stops, local data stays. A lost zone is uploaded again.
  State lives in `Application Support/Keaser/cloud-sync.plist`.
- The status is the account card's footnote in Settings, only while sync is
  on (`CloudSyncFootnote`). The privacy policy's `<!-- if icloud -->`
  sections (`MarkdownConditions`) show only then too; update their "Last
  updated" date when sync ships.
- Receipt photos: `Expense` adopts `ReceiptHolding` (`receiptPhotoIDs`, its
  `receipts` in list order), so the expense's own record carries the list;
  each photo is its own record (`ReceiptSyncKind`), uploaded once, never
  sent from a device without the file, and its deletion removes the file on
  other devices. `FolderAttachmentFiles.receipts` is the app's
  `ReceiptFolder` (`AppEnvironment.receipts`), with its names
  (`ReceiptPhoto.fileName`) and protection (`ReceiptFolder.writingOptions`).

Turning it on (paid Apple Developer Program):

1. In project.yml change the Keaser target's `templates: [FreeTeamSigning]`
   to `templates: [CloudSyncSigning]` (entitlements
   `Keaser/App/KeaserCloud.entitlements`, remote-notification background
   mode, `KEASER_CLOUD`, `KeaserCloudSync`), then `xcodegen generate`.
2. Open the project in Xcode with the paid team selected and build to a
   device once: automatic signing registers the iCloud container
   `iCloud.com.fulltimestudio.keaser` and push for the App ID.
3. Run on two devices signed in to the same Apple Account, then deploy the
   CloudKit schema from the Development to the Production environment in
   the CloudKit Console before any TestFlight or App Store build.
4. Update the privacy policy's "Last updated" date and the App Store privacy
   answers (data is stored in the person's iCloud, not collected).

What to verify on two devices (A and B, same Apple Account):

1. A with data: launch; Settings shows "Synced with iCloud just now".
2. B fresh install: onboard; A's accounts, expenses, labels, currency and
   week start arrive; one Personal account, no duplicate categories. Repeat
   with B offline first creating Personal and an expense: after going online
   both appear once, merged.
3. Edit on A, see it on B within a minute (B in the foreground), and the
   reverse. Delete an expense, a category (its expenses show no category)
   and an account on one; they go on the other.
4. Airplane mode on both, edit the same expense on each, the later edit
   wins after both reconnect; delete on one and edit on the other: the edit
   survives.
5. Reorder categories and accounts on A; B shows the order.
6. Sign out of iCloud on B: the footnote says iCloud is off, data stays.
   Sign in with another Apple Account: "Paused: a different iCloud account
   is signed in", nothing uploads. Sign back in with the first: sync resumes.
7. Widgets, Spotlight and the weekly summary on B update after a change
   from A. Add Expense from Siri on A reaches B.
8. Delete Keaser's data from iCloud storage in the Settings app: the next
   launch uploads the device's data again, and the other device merges it.

## Launch arguments (DEBUG only)

| Argument | Values | Area |
|---|---|---|
| `-KeaserSeed` | `fresh`, `onboarded`, `account`, `single`, `demo` | foundation |
| `-KeaserSheet` | `settings`, `paywall` (presented by `RootView` over whatever is showing); `settingsPaywall` opens Settings with the paywall on a second sheet over it, as Upgrade does | foundation |
| `-KeaserOnboardingPage` | `0`...`4`; `widgetGallery` (every Spending widget size: the Today, This Week and This Month medium widgets first, then small, lock screen, large and extra large portrait, with a long RWF total), `widgetGalleryLocked` (every size once the pass is over, and without an account); both need seed `fresh` | onboarding |
| `-KeaserGalleryScroll` | `small` (then the lock screen widgets), `lockScreen`, `large`, `extraLarge` start either widget gallery at that section; `extraLargeNoAccount` starts the locked gallery at its last widget (the sections before the start are left out, so shots begin at its heading) | onboarding, platform |
| `-KeaserGalleryRendering` | `accented`: the gallery's home screen widgets as a tinted or clear home screen draws them (glass, white content, a stand-in tint on the total) | platform |
| `-KeaserNotifState` | `granted`, `denied`: page 4 in its end state without the system prompt; with `-KeaserSettingsPage weeklySummary`, `denied` shows the summary on and notifications off | onboarding, settings |
| `-KeaserLetter` | `1` shows the welcome letter over Home | onboarding |
| `-KeaserLetterPage` | `tldr`, `follow` (sample links, DEBUG only) | onboarding |
| `-KeaserSheet` | `accounts`, `addAccount`, `newExpense`, `expense` (the newest expense's details), `editExpense`, `search` | home |
| `-KeaserPeriod` | `today`, `thisWeek`, `thisMonth`, `thisYear`, `allTime` | home |
| `-KeaserSearch` | search text, with `-KeaserSheet search` | home |
| `-KeaserExpenseTitle` | text typed into New Expense (shows Smart Suggestions) | home |
| `-KeaserExpenseFocus` | `amount`: then moves on to Amount (shows the guessed category and payment); `none`: the keyboard stays down, to see the receipt card and Delete under the card | home |
| `-KeaserReceiptAttached` | a count from `1` to `10`: that many sample receipts (each a different shop, printed onto paper by `ReceiptImageRenderer`) are kept with the selected account's newest expense (seeded folder), for `-KeaserSheet expense` and `editExpense`; with `newExpense` it starts New Expense with them attached, unsaved | home |
| `-KeaserReceiptViewer` | `n` (from 1): with receipts showing (`-KeaserReceiptAttached`), opens the n-th full screen, in the details or the editor (`3` receipts and `2` shows "Receipt 2 of 3") | home |
| `-KeaserExpenseScroll` | `receipts`: the editor scrolls down to its receipts, to see the gallery under the card (with `-KeaserExpenseFocus none`) | home |
| `-KeaserOpenURL` | a deep link taken through `AppRouter` as if a widget or control opened it; `keaser://scan-receipt` with `-KeaserReceipt <sample> -KeaserReceiptImage 1` shows the Scan Receipt control's route reading and attaching that sample instead of opening the camera | home |
| `-KeaserAccountsEditing` | `1` opens the Accounts sheet in edit mode | home |
| `-KeaserChartSelection` | `last` or a bar index: shows the long-press callout | home |
| `-KeaserCurrency` | an ISO code (`RWF`, `JPY`...): the seed's currency | home |
| `-KeaserAmountScale` | a whole number every seeded amount is multiplied by; with `-KeaserCurrency RWF` and `5000`, seed `single` shows RWF 100,000 | home |
| `-KeaserSettingsPage` | `account`, `categories`, `newCategory`, `editCategory`, `paymentMethods`, `newPaymentMethod`, `editPaymentMethod`, `currency`, `startWeek`, `smartSuggestions`, `weeklySummary`, `shortcut`, `tutorials`, `tutorialWallet`, `whatsNew`, `release`, `help`, `followUs`, `privacy`, `terms` | settings |
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
| `-KeaserCloudStatus` | `synced`, `syncing`, `offline`, `off`, `restricted`, `otherAccount`, `full`, `unavailable`, `failed`: the iCloud sync footnote in that state, in any build, with the privacy policy's iCloud wording | sync |
| `-KeaserCloudSync` | `off`: no iCloud sync this launch, in a build that has it | sync |

Seeded launches keep the database in memory and never touch the real file.

## Shared names

- App Intents: `AddExpenseIntent` (title "Add Expense") and
  `LogWalletTransactionIntent` (title "Log Wallet Transaction"). The one
  tutorial, Apple Wallet Automation, teaches Add Expense by that title
  (never Log Wallet Transaction) and refers to Add Expense's fields by its
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
  fills what is still empty, each page is attached as a receipt, and the
  person saves. Closing the camera leaves New Expense ready to type. The flow's rules (step order, skips, Go Back targets) live in
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
| platform | `Keaser/Design/ReadableWidth.swift` (the readable column for wide windows on iPad and in iPhone Mirroring, and clearing iPad window controls), `Keaser/Design/SwipeActions.swift` (iOS 27 swipe to edit or delete on Home and search rows), the widget families, `SpendingHeadlineMetrics` (each home screen size's caption and total) and `WidgetInks` (full colour vs accented and vibrant styles) in `KeaserWidgets/Shared/SpendingWidgetView.swift`, the lock screen texts in `Packages/KeaserKit/Sources/KeaserKit/Platform/SpendingSnapshot.swift`, `scripts/shots/platform.txt` |
| home-expenses | `Keaser/Features/{Home,Accounts,ExpenseEditor}/`; receipts kept with expenses: `ReceiptAttachment.swift` (the editor's receipt section, the single row, `ReceiptGallery`, thumbnails), `ReceiptViewer.swift` (full screen, paging, zoom, share, Remove Receipt), `ReceiptImage.swift` (JPEG making, DEBUG samples) in `Keaser/Features/ExpenseEditor/`, `KeaserActionCard` in `Keaser/Design/SheetChrome.swift`, `Packages/KeaserKit/Sources/KeaserKit/Models/ReceiptPhoto.swift` (`ReceiptPhoto`, `ReceiptList`), `Store/ReceiptFolder.swift` (files, orphans), `Intelligence/ReceiptFill.swift` |
| shortcuts | `Keaser/Intents/`, `KeaserWidgets/AddExpenseControl.swift`, `KeaserWidgets/ScanReceiptControl.swift`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{QuickLog,ShortcutFlow,ShortcutCardList,WalletAmount}.swift` (`WalletAmount` reads Log Wallet Transaction's text amount in any number style), the Shortcut page in `Keaser/Features/Settings/PreferencePages.swift` |
| settings-pro | `Keaser/Features/{Settings,Paywall}/`, `Keaser/Resources/Keaser.storekit`, `Keaser/Resources/Legal/` |
| intelligence | `Keaser/Intelligence/` (`CategoryModels`: the model the app uses, DEBUG stand-in; `ReceiptScanner`: reads a scan for New Expense, DEBUG samples), `Keaser/Features/ExpenseEditor/ReceiptScanButton.swift` (the title row's scanner glyph; `ReceiptCaptureRequest` and `receiptCapture`, the document camera and photo picker the editor presents for scanning and attaching), `Packages/KeaserKit/Sources/KeaserIntelligence/` (Vision and Foundation Models on device, linked by the app only: `AppleIntelligence` availability, `OnDeviceCategoryModel`, `ReceiptTextRecognizer`, `OnDeviceReceiptModel`, DEBUG `ReceiptImageRenderer`), `Packages/KeaserKit/Sources/KeaserKit/Intelligence/` (`CategoryPrompt`, `CategoryModel`, `SmartLabels`, `Deadline`, the async `ShortcutFlow` steps; receipts: `ReceiptText`, `ReceiptParser`, `ReceiptReading`, `ReceiptDraft`, DEBUG `ReceiptSamples`), opt-in model evaluation `scripts/eval.sh` (`Tests/KeaserIntelligenceEvals`, Mac with Apple Intelligence) |
| sync | `Keaser/Cloud/` (`CloudSyncSwitch`, `CloudSync`, `CloudSyncEngine`, `CloudRecords` and `CloudAttachmentFiles`), `Keaser/Features/Settings/CloudSyncFootnote.swift`, `Keaser/App/KeaserCloud.entitlements` and the signing templates in `project.yml`, `Packages/KeaserKit/Sources/KeaserKit/Sync/`, the conditional sections of `Keaser/Resources/Legal/privacy.md`, `scripts/shots/sync.txt` |
| intents | `Keaser/Intents/{ExpenseEntity,AccountIndexing,OpenIntents,SearchIntents,SpotlightIndexer,EntityAnnotations,KeaserShortcuts,GetSpendingIntent,DeleteExpenseIntent,IntentRefusal,IntentDonations,TestDataIntent}.swift`, the string queries in `KeaserWidgets/Shared/AccountEntity.swift` and `Keaser/Intents/ExpenseEntities.swift`, the open and search routes in `Keaser/App/AppEnvironment.swift` and `HomeView.handle(_:)`, `Packages/KeaserKit/Sources/KeaserKit/Platform/{EntityCatalog,SpotlightPlan,SpendingAnswer,ExpenseDeletion,IntentTestFixture}.swift`, `KeaserIntentTests/`, `scripts/intents-test.sh` |

Logic for each area lives in `Packages/KeaserKit/Sources/KeaserKit/<Area>/`
(`Home`, `Settings`, `Platform`, `Sync`) with tests in
`Packages/KeaserKit/Tests/KeaserKitTests/<Area>*Tests.swift`, and its
screenshot list in `scripts/shots/<area>.txt`.
