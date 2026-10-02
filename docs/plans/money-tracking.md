# Money tracking: plan for review

Status: APPROVED; phases 1 and 2 BUILT on 2026-10-01 (see "Phase 1 as built" and "Phase 2 as built" at the end). The founder decided the direction on 2026-09-29 and, the same day, accepted every recommendation in "Decisions" below ("do what you recommend"). Next: phase 3. Written against main at 6f9a2af (receipts, iCloud sync and every widget size merged).

Every screen here follows the rule in AGENTS.md: it is built from Keaser's existing pieces and looks, flows, moves and talks like what is already there. Each screen below names the existing screen it copies.

## Already decided

- Keaser tracks income as well as spending, and where the money is.
- Payment methods become **wallets**: cash, bank account, mobile money (MoMo), credit card. An expense takes money out of a wallet, income puts money in, and a transfer moves it between two wallets.
- Each wallet has its own currency. Exchange rates are fetched once a day, the rate used is saved on each transaction, and the person can override it.
- A credit card tracks its limit, what is owed and what is still available.
- An income split rule by percentage:
  - **Savings** moves automatically to the wallet marked Savings, and the person can skip it for a single income.
  - **Expenses** and **Free money** are decided by category: each spending category belongs to one or the other.
- A dedicated **Summary** page with an on-device AI summary.
- A native bottom tab bar: **Home, Wallets, Summary, Settings**. Settings moves from the gear sheet into its tab.
- Home stays spending-first, with balances added.

## Decisions

Each question had a recommendation, and the founder accepted all of them on 2026-09-29. Treat every "Recommendation" below as decided.

1. **The word "Wallet".** Keaser already says "Wallet" for Apple Wallet (the Apple Wallet Automation tutorial, Log Wallet Transaction). Recommendation:
   - Call the new things wallets (the Wallets tab, Add Wallet).
   - Always write "Apple Wallet" in full for Apple's.
   - Keep the expense card's "Payment" row label from the reference; it now shows the wallet's name.
   - Keep the Add Expense intent's "Payment Method" parameter title, so existing shortcuts and the Wallet tutorial keep working.
2. **Wallets per account, or shared by all accounts?** Today each account (Personal, Business) has its own payment methods. Recommendation: per account, as today. Accounts stay separate ledgers, and "Multiple Accounts" stays a Pro feature with the same meaning.
3. **The display currency.** The Currency setting becomes the currency totals are shown in. Home, the widget, Siri and Summary convert every wallet into it. Recommendation: yes, and rename nothing: the row stays "Currency".
4. **Existing payment methods.** They become wallets with a guessed type, all set to "Not tracking a balance" until the person enters what is in them today (Set Balance). Their past expenses still count as spending but not against the balance. That avoids every old wallet showing a large negative balance. The guesses:
   - Credit Card becomes a credit card.
   - Debit Card and Bank Transfer become bank.
   - Cash becomes cash.
   - E-Wallet becomes mobile money.
   - Anything the person made becomes "Other".

   Recommendation: yes. The first time the person opens Wallets, a card says "Set up your wallets" and leads through each one: its type, currency and balance, or Hide.
5. **What a new account starts with.** Recommendation: Cash, Bank Account, Mobile Money and Credit Card, all in the display currency and not tracking yet. A Savings wallet is added when the split rule is switched on.
6. **Split rule period.** Recommendation:
   - Expenses and Free money are counted per calendar month: that month's income times each percentage, minus that month's spending in the categories of each.
   - Leftovers are shown, not carried over.
   - With no income logged in a month, the envelopes show spending only.

   The alternative is a running total that never resets, which is harder to read.
7. **Which categories are Expenses and which are Free money.** Recommendation for the built-in ones:
   - Expenses: Food & Drinks, Transportation, Health and Services.
   - Free money: Shopping, Entertainment and Travel.
   - A category the person adds is Expenses until changed.
8. **Pro.** Recommendation:
   - Free: income, wallets with balances, transfers and credit cards (the core of the new app).
   - Pro: wallets in other currencies, the split rule, and the AI summary. These are three new `ProFeature` cases shown on the paywall like the others.
9. **Exchange rates and privacy.** Fetching rates is the first time Keaser uses the internet: the privacy policy says today that nothing leaves the iPhone. The request carries no personal data, only "give me today's rates", but the rate server sees the phone's IP address. Recommendation:
   - Fetch only while some wallet uses another currency.
   - Use `open.er-api.com`, falling back to the jsDelivr currency files. Both are free, need no key, and cover RWF.
   - Say so plainly in the privacy policy.
   - Keep the App Store privacy answer at "no data collected".
10. **Home's balances.** Recommendation:
    - One new card under the spending card: "Balance" over the total of all tracked wallets in the display currency. It uses the spending card's caption-over-total style, and tapping it opens the Wallets tab.
    - The expense list stays expenses only. Income and transfers show in Wallets and Summary.
11. **Siri, Shortcuts and the widget in the first release.** Recommendation:
    - Add Expense picks a wallet through its existing Payment Method parameter.
    - Add "Add Income" and "What's My Balance" intents.
    - Leave the Spending widget as it is (a balance widget can come later).

## Screens

Each screen is copied from the existing one named in brackets.

- **Tab bar** (system `TabView`, Liquid Glass on iOS 26+, the standard bar before). Home `house`, Wallets `wallet.bifold`, Summary `chart.bar.xaxis`, Settings `gearshape`.
  - Home loses its gear button.
  - Settings shows the same pages as today, in a navigation stack instead of a sheet.
  - The paywall stays a sheet. `keaser://settings` selects the Settings tab.
- **Home** (unchanged): the Balance card goes under the spending card, as a `KeaserCard` with the same margins.
- **Wallets tab** (Settings list pages and Home's summary card):
  - The total balance at the top, then wallets grouped by type (Cash, Bank, Mobile Money, Credit Cards, Savings).
  - Each wallet is a row: `SymbolTile`, then name, then its balance in its own currency, with the display-currency value in the caption grey when they differ.
  - Credit card rows show "Owed" and "Available".
  - The top bar's "+" opens one menu: Add Income, Transfer, Add Wallet.
- **Wallet details** (the expense details sheet):
  - Balance, type, currency, and for a card: limit, owed and available.
  - Then its recent transactions.
  - Edit in the header, Set Balance, and Delete Wallet as a `KeaserActionCard`.
- **Add or Edit Wallet** (New Account and the label editor): name, symbol, type, currency, balance today (or Not Tracking), credit limit for a card, and a Savings switch.
- **Add Income** (New Expense, field for field):
  - Title, Amount, Category (income categories), Wallet and Date.
  - With the split rule on, one more card: "Savings 20%: RWF 40,000 to Savings", with a Skip This Time switch.
- **Transfer** (New Expense):
  - From, To, Amount and Date.
  - Between currencies, Amount Received is filled from the day's rate and can be changed.
  - Paying a credit card is a transfer into it.
- **Summary tab** (Home's layout):
  - The same period menu as Home (This Week, This Month...).
  - At the top, the AI summary card: a few sentences made on the iPhone with Apple Intelligence (iOS 26+). Without it, the same numbers appear in a fixed sentence form.
  - Then cards for Income, Spent and Saved; the Expenses and Free money envelopes with what is left; and the wallets' total.
- **Settings additions** (existing preference pages):
  - "Split Rule": the three percentages, which must add up to 100; the Savings wallet; and a link to category roles.
  - The Categories page gains an Income section, and each spending category gets an "Expenses" or "Free Money" choice.
  - "Exchange Rates": when rates were last updated, each currency in use, and an override.

## Data (KeaserKit, all tolerant decoding, all through `KeaserStore`)

- `PaymentMethod` gains the wallet fields, so its IDs, intents, entities and sync stay:
  - `kind` (cash, bank, mobileMoney, creditCard, other)
  - `currencyCode`
  - `trackingSince: Date?` and `openingBalance: Decimal` (nil means not tracking)
  - `creditLimit: Decimal?`
  - `isSavings`
  - `isHidden`
- `Expense` gains `currencyCode` (its wallet's, at the time) and a `rate: ExchangeRate?`: the rate to the display currency, its date, and whether fetched or typed.
- New `Income`: id, title, amount, currency, rate, date, wallet, income category, `createdAt`/`updatedAt`, and `savingsTransferID` or `savingsSkipped`.
- New `Transfer`: id, from, to, amount out, amount in, date, note, kind (manual, savings, card payment).
- `ExpenseCategory` gains `role` (expenses, freeMoney). `Account` gains `incomeCategories`, `incomes`, `transfers` and `splitRule` (three percentages, enabled, savings wallet).
- `ExchangeRates`: the daily table, kept in the app group for the widget and never synced. What syncs is the rate saved on each transaction.
- `SyncKinds` gains Income, Transfer and SplitRule, with `SyncStamps` rules. Wallet fields ride on the existing PaymentMethod records.

## Maths (pure, tested on the Mac)

- A tracked wallet's balance: `openingBalance`, plus income into it, minus expenses from it, plus transfers in, minus transfers out. Only entries on or after `trackingSince` count.
- A credit card counts the other way:
  - Owed is opening owed, plus its expenses, minus payments into it.
  - Available is the limit minus owed.
  - It counts against the total balance as a negative.
- Conversion always uses the rate saved on the transaction, so old totals never move when rates change. Today's rate is only used for today's balances in the display currency and for new entries.
- Envelopes, per month:
  - `income × percent`
  - minus spending in that envelope's categories
  - minus nothing for Savings, whose progress is the transfers made.

## Build phases

Each phase ends with a build on Serein and screenshots checked against the screens they copy.

| # | Phase | Effort | Shows on screen |
|---|---|---|---|
| 1 | Data model, migration, balance and envelope maths, sync kinds, tests (built) | about 16 h | Nothing (existing data loads unchanged) |
| 2 | Tab bar; Settings moves into its tab; Home without the gear (built) | about 8 h | The four tabs, Wallets and Summary still empty |
| 3 | Wallets: list, details, add and edit, Set Balance, transfers, credit cards, first-time setup card | about 24 h | The Wallets tab and Home's Balance card |
| 4 | Currencies: the daily rates service, wallet currencies, converted totals, rate override, privacy policy | about 20 h | Wallets and expenses in other currencies |
| 5 | Income: Add Income, income categories, Siri "Add Income" | about 16 h | Income in Wallets and wallet details |
| 6 | Split rule: its Settings page, category roles, the savings transfer on income, envelopes | about 16 h | The split card in Add Income |
| 7 | Summary tab: numbers, envelopes, the on-device AI summary and its fallback | about 20 h | The Summary tab |
| 8 | Siri "What's My Balance", Add Expense wallets, weekly summary wording, What's New, docs | about 12 h | Siri answers and release notes |

About 130 hours in all. Every decision is made, so build in this order, starting with phase 1.

## Risks

- **Balances are only as right as what is logged.** Set Balance records an adjustment, so a wallet can always be put right without editing history.
- **Rates can be missing** (offline, or the service is down). The last saved table is used, the rate is shown with its date, and entries can always be typed by hand.
- **The tab bar changes every screenshot of Home and Settings,** and the reference recordings have none. That is the founder's choice, recorded in AGENTS.md when built.
- **Decimal places differ by currency** (RWF and JPY have none, USD has two). Formatting already goes through `MoneyFormat`, and conversions round to the target currency's places.
- **iCloud sync** needs its two-device test repeated once wallets, income and transfers sync.

## Phase 1 as built

Built on 2026-10-01 in KeaserKit only: the data model, its tolerant decoding, the balance, envelope and savings maths, the store's money methods and the sync kinds, with 139 new tests (629 in 81 suites). Nothing on screen changed. AGENTS.md ("Data", "iCloud sync" and the `money` row) describes it; this section keeps what the plan above did not say.

Decisions made while building, on the founder's lead:

- A nil currency on a wallet means the display currency, so the Currency setting relabels it as it always has. On an expense, income, transfer side or balance adjustment it means its wallet's. Changing a wallet's currency, or deleting the wallet, first writes the old currency into what followed it, so nothing changes currency after the fact.
- A balance is the money in the wallet, so a credit card that owes 500 has a balance of -500 and counts against the total with no special case. Owed and Available (phase 3) are read from it.
- Set Balance states a dated checkpoint (`BalanceAdjustment`) rather than editing history: a wallet's balance starts from the latest stated one and counts only entries dated after that day, or that day and logged after it.
- The split rule applies only to a new income or one no longer skipped. An income keeps the percentage it was logged with, and money that already moved is never re-rated. The savings transfer's ID is derived from the income's, so two devices never make two.
- The built-in income categories (Salary, Business, Gifts, Refunds) are added to an account saved before them when it loads, with IDs derived from the account's, so two devices make the same set.
- What cannot be converted (no rate saved, none in today's table) is left out of a total and counted, never guessed.

Left for later phases, because they show on screen:

- Phase 3: new accounts start with Cash, Bank Account, Mobile Money and Credit Card (today they still get the old payment methods).
- Phases 4, 6 and 7: the three new `ProFeature` cases (other currencies, the split rule, the AI summary).
- Phase 4: the exchange rates file in the app group and fetching it. `ExchangeRates` and `CurrencyConverter` are ready for it.

Notes for the next phases:

- Phase 5: Add Income must work with an empty income category list (the person can delete them all); an income with no category is valid.
- Phase 6, optional hardening: on a device's first meeting iCloud's split rule wins, as the settings do. A rule in iCloud that nobody ever edited should not beat one edited on this device before its first sync.
- Repeat the two-device test (AGENTS.md, item 9) once wallets, income and transfers have screens.

## Phase 2 as built

Built on 2026-10-01 on `feat/tab-bar`: the tab bar, Settings in its tab, Home without the gear, and the empty Wallets and Summary tabs. AGENTS.md (the tab bar under "Platform", the deep links, the launch arguments and the foundation and money rows) describes it; this section keeps what the plan above did not say.

Decisions made while building:

- The selected tab is never remembered: every launch starts on Home, which routes and the App Intents tests expect. The bar has no extras (no style, no minimizing on scroll, no bottom accessory, no search in the bar (the `.search` role only gives Add Expense its detached place on iOS 26)).
- Add Expense is part of the tab bar, set apart at its trailing end and coloured (an ink disc with the +, as Home's floating button was, inside the glass circle), by the founder's choice (2026-10-01): the prominent tab on iOS 27, the search tab's place on iOS 26 (the only detached place there) and a plain last tab before. It is never selected; it opens New Expense on Home from any tab, as `keaser://new-expense` does. Home's floating + is gone, and its list ends 16pt above the bar. Search hides the tab bar while Home shows, so it keeps the whole screen with its field at the bottom, as in the reference.
- Scrolled sheet content (the receipt gallery in New Expense, Edit Expense and the details, and the Accounts list) stays 32pt below the header's buttons, fading out over the lower 16pt, instead of running into them (`keaserSheetScrollEdge()`); the founder asked for more room than the first 16pt. Nothing moves before scrolling.
- Settings keeps its inline title, with no xmark. Its cards sit exactly as far under the title as they did in the sheet (measured on the screenshots), so the iOS 27 4pt correction still holds.
- In dark mode Settings takes Home's page look (a black canvas with 28,28,30 cards) instead of the sheet's charcoal; light mode is unchanged. The row symbol tile keeps its faint veil, 3 levels above the card as before. Sheets presented from Settings keep the sheet look.
- Every route goes through `AppRouter.open`. `keaser://settings` lands on the Settings root, where Upgrade is, and closes a Home sheet; every other route selects Home. Each route closes what Settings presents. A route that changes tabs waits (up to 2 s) until nothing is presented: in testing, a sheet whose tab left the screen while it was up stayed stuck, and a sheet cannot come up while another is leaving.
- An account deleted from Home's Accounts sheet (or on another device) takes its Settings pages off the stack.
- The Pro banner's starfield holds still while Settings is off screen (another tab, or a page pushed over it), and it has the cards' hairline so its near-black sky keeps an edge on the black dark mode canvas.
- Wallets and Summary are an inline title over Home's `.large` empty state, centred, until phases 3 and 7.
- What scrolls under the tab bar (Home, every settings page, the tutorials and legal pages) fades into it on iOS 26+ (`keaserSoftBottomEdge()`), as under any system bar; before, a row's amount showed sharp in the gap beside Add Expense.
- The legal pages pushed in Settings stay white in light mode, as the reference draws them (`settingsDocumentCanvas`), and are black in dark mode.
- `paywall-over-settings` is now one sheet over the Settings tab; the reference's sheet over a sheet no longer applies.

- Checked on the iOS 18.6 simulator too (a runtime on this Mac, though AGENTS.md says only iOS 27 is local): the standard bar shows five items with Add Expense last as a small ink disc, Search hides it, and Home, Settings and Wallets read as on iOS 27, light and dark.

Left to check on a device:

- Tapping the selected Settings tab again pops it to its root, and tapping Home again scrolls it to the top. Both are the system's, and the simulator is not driven by hand.
- A route that arrives while the welcome letter is up changes the tab under the letter after 2 s, and a Home sheet cannot show over it (as before the tab bar).
- Tapping Add Expense opens New Expense without the bar flashing to a fifth tab: on iOS 27 (prominent tab), on iOS 26 (the search tab's place, which must not turn into a search field) and on iOS 18 to 25 (a plain last tab). Tap it on Home, then Cancel: Home must still be selected and showing (from Home the route changes no tab, so nothing would put the bar back if the system had moved it). No local iOS 26 simulator exists, and taps cannot be screenshotted.

Noticed while checking phase 2, not caused by it (left as they are; the chart callout that covered "100K" under a wide total has been fixed since):

- In New Expense at `.medium`, a receipt's "Filled in from your receipt" note (and the other-currency warning) sits below the fold under Add Receipt, so it needs a scroll.
- At accessibility text sizes the details card truncates long values ("Enterta...", "Credit...").
- A DEBUG `-KeaserSheet newExpense` launch now and then draws Home without the sheet, on main as well (1 or 2 launches in 10); retake such a shot.
