# Planned after the device test

The founder approved these four extras on 2026-09-28, to be built after testing the current build on an iPhone. Each plan below was written against the iOS 27 SDK and the code at 356637f; re-check both before starting. Build them in this order.

| # | Feature | Effort | Value |
|---|---|---|---|
| 1 | Wallet currency warning | about 8 h | Moderate value, low cost; also fixes today's misread of amounts like "4,50 €" (logged as 450 on an English (US) phone) |
| 2 | Quick Expense control ("log my usual coffee") | about 14 h | High for daily habits: one press logs a saved expense, once the test shows control intents run in the app |
| 3 | Edit Expense Siri action | about 20 h | Moderate: fixes the thing just logged without opening the app |
| 4 | Visual Intelligence search | about 11 h | Low: search only, since iOS 27 still gives apps no way to take a receipt photo from Visual Intelligence |

## Answer these while testing

The device test decides details in every plan. Record the answers here before building.

### Wallet currency warning

- 1. With the tutorial's automation (Wallet trigger, Run Immediately, Add Expense with Merchant and Amount, Confirm Expense Details on): does the confirmation card appear after a real tap, over the Apple Pay sheet and on the lock screen, and can Continue be tapped? If NO, forced confirmation cannot work: use the fallback (step 7). The tutorial default is then broken for everyone, which should be fixed first.
- 2. If the card is ignored or the phone is locked right after paying, what happens? Does the automation time out and save nothing, is there any notice, and after how long? If payments are often lost this way, choose save and warn over forced confirmation.
- 3. What exactly is Shortcut Input > Amount for a domestic tap? Check with a Show Notification of the Amount variable, and with the Get Type action or the variable inspector to see whether it is Text, Number or Currency. Is it '$4.50', 'US$4.50', 'RWF 5,000', 'Frw 5,000', 'RF 5.000' or '4.50'? This confirms that Keaser's own currency is recognised (no domestic false warnings) and whether Wallet formats amounts with the phone's locale, which would allow the stricter shared-symbol rule.
- 4. Tutorial path coercion. Build a shortcut: a Text action with '€12.40', then Add Expense with Amount = that Text. Does the current build show 'The shortcut passed €12.40, but Keaser records amounts in ...' (branch A: Add Expense is already covered), a silent card in Keaser's currency (branch B: step 10 needs a founder decision), a 'What is the amount?' prompt (coercion failed), or 1,240? Repeat with '4,50 €' and 'CA$4.50'.
- 5. Does the Amount arrive at all with the founder's cards and bank, and how long after the tap does the automation run? The trigger waits for the issuer's transaction notification and can time out (forum 765516). If the amount is often missing, this feature is worth less and the missing-amount path (Add Expense asks; Log Wallet refuses) matters more.
- 6. Current bug check: a shortcut with Text '4,50 €' feeding Log Wallet Transaction. Does the current build save 450 in Keaser's currency on the founder's phone? The Mac probe says it does on en_US. This confirms the parser change is a bug fix as well as a feature.
- 7. The phone's Region and Language compared with Keaser's currency (for example English (US) with RWF). This decides which forms of Keaser's currency Wallet produces and whether the device-locale symbol table is enough.
- 8. With Confirm Expense Details off: does the 'Successfully added expense' card show after a Run Immediately tap, and for how long? That decides whether a result-card warning is a usable fallback. Also: is a three-line dialog above the card shown in full or truncated? That decides the optional in-card 'Paid €12.40' line.
- 9. Traveller check, if the founder or a tester travels: for a tap abroad, does Wallet pass the merchant's currency ('€12.40') or the card's billing currency? If it is the billing currency, the Wallet case mostly disappears, and the value of this feature falls to the parser fix plus Siri or typed input.

### Quick Expense control ("log my usual coffee")

- Which iOS version is the test iPhone on (18.x, 26.x or 27), and does it have an Action button? This decides which pinning path is exercised: ForegroundContinuableIntent before 26, supportedModes on 26, allowedExecutionTargets on 27.
- When you tap the existing Add Expense control in Control Center, do its questions (amount, title, lists) actually appear, and does the 'Successfully added expense' card show at the end? Yes proves that control intents reach the app process with UI, so the Quick Expense dialog could also be feedback. Nothing happening means pinning or prompts fail, and that must be fixed (or plan B used) before building this.
- Same Add Expense control from the Lock Screen (phone locked, after first unlock) and from the Action button: does it run without unlocking, does it ask for Face ID, and does the expense get saved? This decides whether .alwaysAllowed is right and whether a Lock Screen Quick Expense is worth offering.
- With Keaser force-quit from the app switcher, does the Add Expense control still work? This checks that the system launches the app in the background for control intents.
- After adding through the control, is the expense in Home immediately when you open Keaser, and did the Spending widget update? This validates the cross-process write and reload that Quick Expense reuses.
- Roughly how long between the tap and the result, and did anything ever get added twice or not at all? This decides the double-tap guard and whether to stop awaiting Spotlight and the weekly summary in this intent.
- Which expenses do you actually log repeatedly, and is their amount fixed (coffee, bus fare) or variable (groceries)? This confirms that 'pick your usual from history with a fixed amount' fits. Mostly variable amounts would make this feature weaker than the Add Expense control.
- Where would you put it: Control Center (title and amount visible at the larger sizes), the Lock Screen (symbol only, 2 slots) or the Action button? This decides whether a per-control symbol choice is needed.
- Has a Run Shortcut control with a fully prefilled Add Expense action (and Confirm Expense Details off) already felt good enough? If yes, the value of a native control is mainly in not building a shortcut per preset and not flipping the global confirm switch.

### Edit Expense Siri action

- Which iOS version is the test iPhone on, and is Apple Intelligence Siri on? Say "Add a 5 dollar coffee in Keaser": does Siri fill both the amount and the title in one go, or ask one by one? One go means "Change my last expense to 15 dollars" can be one shot on iOS 27 and the choice question becomes a fallback. One by one means the requestChoice path is the main Siri experience and its wording matters most.
- Say "Open Business in Keaser" (today's only entity-parameter phrase) several times. Is the account name recognised reliably? This predicts "Move my last expense to Transportation in Keaser" and decides whether the category phrases are worth their slot.
- With the iPhone locked, say "Delete an expense in Keaser". Does it ask to unlock first, and after Face ID does it continue straight into the question, or start over? Edit uses the same authentication policy.
- With Keaser open, delete an expense by Siri, then shake or three-finger swipe. Does "Undo Delete Expense" appear and bring it back? If not, UndoableIntent is not worth shipping for Edit and the confirmation carries all the safety.
- Open an expense in Keaser's Edit Expense sheet, delete that expense with Siri, then return and tap Save. Does the deleted expense come back? This confirms the stale-editor bug that an Edit that moves accounts would turn into a duplicate.
- Voice-only (AirPods with the phone in a pocket, or CarPlay): does Siri read the whole Delete question and the Add Expense confirmation question, and accept "Yes" / "Cancel"? Is a long sentence cut off? This sizes the multi-change edit sentence.
- With an expense visible in Keaser, say "Delete this expense". Does Siri pick the on-screen expense (the view annotations)? If yes, "change this to 15 dollars" can be advertised.
- In the real system card, how tall does the Add Expense confirmation card come out, and is it shown at all by iOS 27 Siri? This decides whether the struck-through 'was' values go in the card or only in the sentence.
- After deleting by Siri, how soon do Spotlight and the home screen widget update? Edit uses the same catch-up path.
- Say "Add an expense of 5 euros in Keaser". Does the "The shortcut passed €5.00, but Keaser records amounts in ..." note appear? This confirms Siri passes a currency code, which Edit's currency note relies on.
- Product answers to collect with the test: does "my last expense" mean the one just added (recommended) or the newest-dated one? Should moving between accounts be in v1? Is an always-on confirmation for Siri edits acceptable?

### Visual Intelligence search

- Which iPhone model and iOS version (26.x or 27.x) is the founder on, and are Apple Intelligence and Visual Intelligence turned on? Visual Intelligence needs iPhone 15 Pro or later (the 16e through the Action button). If it is not available, the feature cannot be verified and should wait.
- Does the founder actually use Visual Intelligence (Camera Control hold, the iOS 27 Camera Siri Mode, or screenshot Image Search), and do other apps' results (Etsy, Amazon, Google) show there? Note how they look (grid, thumbnails, how many shown before scrolling) and how many taps it takes to reach an app's results.
- What do the founder's real expense titles look like after using the current build: merchant names ('Blue Bottle Coffee', 'Trader Joe's') or generic words ('Coffee', 'Groceries')? Merchant names make the text matching worth building. Generic words mean only weak label matching, and the plan should be cut or dropped.
- If the Wallet automation (Log Wallet Transaction) is set up: what merchant strings does Wallet actually pass ('BLUE BOTTLE COFFEE 66 MINT', 'SQ *CAFE', store numbers)? The normalisation and stop-word rules depend on it.
- Does tapping a Keaser expense in Spotlight open it in Edit Expense in the right account, including from the lock screen after Face ID? The Visual Intelligence results use this exact OpenExpenseIntent path, so any bug there must be fixed first.
- How does an expense result look in the system lists of the current build (Spotlight, Siri): is the category SF Symbol with '$5.20 · Sep 26, 2026' readable? That is the closest preview of the Visual Intelligence cards.
- How long does New Expense's receipt scan take on the device with a real receipt, and does it read crumpled or angled receipts and the shop name correctly? That sets the 1.2 s deadline and predicts how well a camera frame will read.
- Under Settings > Apps > Keaser (Siri, Apple Intelligence & Siri, Search), which per-app switches exist? If the system already lets people hide Keaser's content from Visual Intelligence or search, no in-app switch is needed.
- On iOS 27, in the Camera app's Siri Mode, pointing at a receipt and saying 'Add this to Keaser': does Siri run Add Expense with the title and amount filled from what it sees? If it does, the receipt hand-off already works without any code and should be described in Tutorials instead of built.
- Does the founder use a passcode, and are they comfortable with past expense titles and amounts appearing in Visual Intelligence results at all (after unlock)? This confirms the lock rule, and whether the feature should ship on by default.
- What are the device's language and region? Labels are en_US only, and Visual Intelligence app search availability varies by region.

## 1. Wallet currency warning

When Apple Wallet hands Keaser a payment in a currency other than Keaser's, Keaser stops saving it quietly as if it were in Keaser's currency. It shows the expense card first, with one sentence saying what will be recorded, and the person taps Continue or Cancel. The same change fixes a bug that exists today: when a Wallet amount is written with different number separators than the phone's locale, the number is misread (on an English (US) phone, "4,50 €" is currently logged as 450).

**Behaviour**

DECISION: force the confirmation card, the same rule Add Expense already follows (Keaser/Intents/AddExpenseFlow.swift:15-18 and :33). Two alternatives were rejected. (a) Warning on the result card after saving: the wrong number would already be in the totals, widgets, weekly summary and Spotlight, and a result from a Run Immediately automation may never be read. (b) Refusing: the payment is lost, and a trip means dozens of expenses to add by hand later. Asking for the converted amount was also rejected, because nobody knows the exchange rate at the till.

1. Log Wallet Transaction, amount written in Keaser's currency or as a bare number ("$4.50" for a USD user, "4.50", "RWF 5,000" for an RWF user): nothing changes. It is saved at once, with the "Successfully added expense" dialog and the card.

2. Log Wallet Transaction, amount written in another currency ("€12.40" for a USD user): the expense is built exactly as today. The merchant becomes the title, the category comes from the last visit or from the Smart Suggestions guess, and the payment method is matched to the card. The card is then shown whether or not Settings > Shortcut > Confirm Expense Details is on.
   Dialog: "The payment was €12.40, but Keaser records amounts in USD, so it will be added as $12.40. Confirm expense details:"
   Card: the existing ExpenseCardView with no chevrons, on every iOS version. It shows the amount as it will be saved ($12.40), then Title, Account, Category, Payment and Date. The system buttons are Cancel and Continue.
   Continue saves the expense and ends quietly, with no second card, as Add Expense does after a confirmation (AddExpenseFlow.swift:62-67). Cancel saves nothing and the automation ends.
   Rounding follows Keaser's currency: a JPY user who pays "$4.99" sees "...so it will be added as ¥5."
   "The payment was" (not "Wallet passed") stays true when the same action is run by Siri or typed into Shortcuts. It sits alongside Add Expense's existing "The shortcut passed ¥1,500, but Keaser records amounts in USD, so it will be added as $1,500.00." (ShortcutFlow.swift:338-352).

3. Siri by voice alone (iOS 27 systemContext.isVoiceOnly; the App Shortcut is "Log a wallet transaction in Keaser"): Siri says "The payment was €12.40, but Keaser records amounts in USD, so it will be added as $12.40. Add $12.40 for Café de Flore to Personal, under Food & Drinks, paid with Credit Card?" with an Add button. The question is built by QuickLog.confirmationQuestion, as the Add Expense voice path does.

4. Add Expense, which is the action the Wallet tutorial teaches (Title = Shortcut Input > Merchant, Amount = Shortcut Input > Amount): no change is planned. It already forces confirmation with its sentence whenever IntentCurrencyAmount.currencyCode differs from Keaser's currency. Whether that fires for Wallet depends on how Shortcuts turns Wallet's Amount into a currency amount (device question 4).

5. What counts as Keaser's currency. A mark counts when it is one of the usual ways Keaser's currency is written:
   - the ISO code
   - its symbol in the phone's locale (NumberFormatter.currencySymbol)
   - its en_US symbol
   - its narrow symbol, compared by equality (not by `contains`, so a BRL user's "R$" does not count "$" as theirs)
   - ReceiptParser's aliases and prefixed symbols (Frw, KSh, US$...)
   So "$" for a USD, CAD or MXN user, "¥" for JPY or CNY, "kr" for SEK and "RF" for RWF all count as the user's own currency, and domestic payments never trigger the card.
   Any other mark ("€", "CA$", "CN¥", "RWF" for a USD user, unknown letters) means another currency.
   Known limit: a foreign dollar written with a bare "$" is treated as the user's own dollar and is not caught.
   Every locale checked on this Mac (17 locales) maps each symbol to exactly one currency. If the device test shows that Wallet formats amounts with the phone's locale, a stricter rule can be added later: "the phone's own currency owns its bare symbol".

6. Numbers are read with ReceiptParser.number (ReceiptParser.swift:299), biased toward the phone's decimal separator. For a currency with no minor unit (RWF, JPY, KRW), a separator followed by three digits groups thousands. Whitespace, U+00A0 and U+202F count as grouping only before a group of three digits, and ’ is read as '.
   A Mac probe ran a copy of today's MoneyFormat.parse and confirmed the bug: en_US "4,50 €" gives 450, de_DE "$4.50" gives 450, en_US "1.234,56 €" gives 1.23456, and de_DE "RWF 5,000" gives 5.
   A probe of the proposed reader returned 4.5, 4.5, 1234.56 and 5000 (the RWF case after the rule above), and returned nil for "$0.00", "-$4.50" and "free".
   A negative or zero amount is still refused with "Enter an amount greater than zero."
   DONE ahead of the device test: `WalletAmount.read(_:currencyCode:locale:)` (Platform/WalletAmount.swift) now does this reading, with `text`, `value` and `marks`, and `QuickLog.amount(from text:)` uses it. It widens the rule above: three digits after a lone separator group thousands for any currency with at most two decimals (so "¥1,500" and "€1.234" read the same on every phone), and only a three-decimal currency (KWD) is left to the phone's separator. A bare number takes Keaser's currency. Step 2 below therefore only adds `isWritten` and `otherCurrencyNote`.

7. Fallback, used only if device questions 1 and 2 show that a Wallet automation cannot show or answer a prompt: save the expense, and replace "Successfully added expense" with "Added as $12.40. The payment was €12.40, and Keaser records amounts in USD, so change the amount in Keaser if needed."

There is no new setting and no Pro gate. DataDetection is not used (see apis). There is no conversion: Continue still records the foreign number in Keaser's currency, and the person corrects the amount later in Edit Expense.

**APIs** (verify again before use)

- Shortcuts Wallet 'Transaction' trigger: Shortcut Input with the properties Merchant, Amount, Card or Pass and Name (iOS 17+ Shortcuts. It has no SDK surface. The type of Amount is UNVERIFIED: third-party guides say it arrives as text such as '€12.34' and strip the non-digits. The amount comes from the card issuer's transaction notification, and the trigger can time out waiting for it (forum threads 765516 and 758053, FB14035016 and FB16379100).; https://splitsies.dev/articles/2026-06-27-capture-payments-shortcut ; https://grahamhaley.co.uk/2024/11/19/apple-pay-automation/ ; https://developer.apple.com/forums/thread/765516)
- AppIntent.requestConfirmation(conditions: ConfirmationConditions = [], actionName: ConfirmationActionName = .continue, dialog: IntentDialog? = nil, showDialogAsPrompt: Bool = true, @ViewBuilder content: () -> Content) async throws (iOS 18.0+, not deprecated in the iOS 27 SDK. This is the plain card for Log Wallet Transaction on every supported iOS version. It is already used at AddExpenseFlow.swift:166 with a @Sendable closure.; _AppIntents_SwiftUI.framework/Modules/_AppIntents_SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface:63-65)
- AppIntent.requestConfirmation(conditions:actionName:dialog: IntentDialog) async throws (iOS 18.0+. Used for the voice-only question.; AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface:3217-3219)
- AppIntent.requestConfirmation(conditions:actionName:dialog:showDialogAsPrompt:snippetIntent:) async throws (interactive card) (anyAppleOS 26.0+. OPTIONAL: only if the Wallet card should get Add Expense's chevrons, which needs a ShortcutFlow built from the Wallet expense.; AppIntents.swiftinterface:3221-3225)
- ConfirmationActionName.continue / .add (iOS 16.0+. Use .continue for the card, as the reference card does, and .add for the voice question, as AddExpenseFlow.swift:153 does.; AppIntents.swiftinterface:3390-3412)
- AppIntent.systemContext: IntentSystemContext; IntentSystemContext.isVoiceOnly: Bool; IntentSystemContext.locale: Locale (systemContext is iOS 16+. isVoiceOnly and locale are anyAppleOS 27.0+, so gate them with #available(iOS 27.0, *) as AddExpenseFlow.swift:76-79 does. Use locale only if the device test shows that Shortcuts formats amounts in a locale other than Locale.current.; AppIntents.swiftinterface:5042-5054)
- IntentDialog: ExpressibleByStringInterpolation; init(_ string: LocalizedStringResource) (iOS 16.0+; AppIntents.swiftinterface:4447-4448)
- IntentCurrencyAmount { let amount: Decimal; let currencyCode: String; init(amount:currencyCode:) } (iOS 16.0+. Add Expense path only, unchanged. In ShortcutCard.otherCurrencyNote, currencyCode is compared with Keaser's currency after trimming and uppercasing.; AppIntents.swiftinterface:9449-9453)
- DataDetection: StringProtocol.dataDetectorMatches(_ types: DataDetector.MatchType = .all, options: DataDetector.Options = DataDetector.Options()) -> some AsyncSequence<DataDetector.Match, Never>; MatchType.moneyAmount; Match.SemanticDetails.moneyAmount(MoneyAmount { currency: Locale.Currency; amount: Decimal }); Options.documentRegion: Locale.Region? (iOS 26.0+ (Codable and Hashable conformances from iOS 27). NOT USED. The earlier platform research proposed it; a probe on this Mac (macOS 27.2, same framework) rules it out. It found no match for 'RWF 5,000', '5,000 RWF', 'CN¥1,500' or '4.50'. It returned 1234.5599999999997952 for '1.234,56 €', a Double artefact inside a Decimal. It read '45,00 kr' as NOK and '-$4.50' as +4.5. It resolved a bare '$' to USD and '¥' to JPY even with documentRegion DE. It is also async and iOS 26+ only, while the KeaserKit parser covers iOS 18+ and runs in ./scripts/test.sh.; DataDetection.framework/Modules/DataDetection.swiftmodule/arm64e-apple-ios.swiftinterface:11-26, :34-40, :82-86, :119-121)
- Foundation: Locale.commonISOCurrencyCodes, NumberFormatter.currencySymbol (numberStyle .currency, currencyCode, locale), Decimal.FormatStyle.Currency.presentation(.narrow) (iOS 15+ (all are already used in KeaserKit); Packages/KeaserKit/Sources/KeaserKit/Intelligence/ReceiptDraft.swift:54-57 (narrow form), ReceiptParser.swift:514 (isoCurrencyCodes), Logic/MoneyFormat.swift:12-18 (symbol))
- AppIntentsTesting AnyAppIntent.run() async throws -> ResolvedIntentResult (iOS 27.0+ test-only. It has no API to answer a confirmation or a requestValue, so a forced-confirmation run can only be observed from outside, as 'did not save'.; /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/AppIntentsTesting.framework/Modules/AppIntentsTesting.swiftmodule/arm64e-apple-ios.swiftinterface:256-272)

**Files**

- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Platform/WalletAmount.swift (NEW)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Platform/QuickLog.swift (amount(from text:) at :30-35 delegates to WalletAmount)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Tests/KeaserKitTests/PlatformWalletAmountTests.swift (NEW)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Tests/KeaserKitTests/PlatformTests.swift (keep :125-129; add the cross-locale regressions)
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/LogWalletTransactionIntent.swift
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/IntentSupport.swift (optional: shared isVoiceOnly helper)
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/AddExpenseFlow.swift (only if isVoiceOnly moves to IntentSupport)
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/SnippetPreview.swift (new kind walletOther)
- /Users/FullTimeStudio/Dev/apps/keaser/scripts/shots/shortcuts.txt
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserIntentTests/AddExpenseTests.swift
- /Users/FullTimeStudio/Dev/apps/keaser/AGENTS.md (-KeaserSnippet row, line 108)
- /Users/FullTimeStudio/Dev/apps/keaser/README.md (test badge, line 12)
- Read-only reuse: /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Intelligence/ReceiptParser.swift (number :299, currency(forMark:) :459, symbolCodes :489, prefixedSymbols :498, currencyAliases :504)
- Read-only reuse: /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Platform/ShortcutFlow.swift (ShortcutCard, otherCurrencyNote :338-352)
- OPTIONAL: /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/ExpenseCard.swift + ShortcutFlow.swift (ShortcutCard.paidAs line under the amount)
- OPTIONAL: /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Settings/Tutorials.swift (Wallet tutorial 'done' section, :263 onward)

**Steps**

1. 0. Wait for the device test answers (see deviceTestQuestions). Answers to questions 1, 2 and 4 decide between the main design, the fallback (step 7) and branch B (step 10). Start with a branch from main (356637f or later).
2. 1. KeaserKit, new file Platform/WalletAmount.swift (Foundation only, public). Contents:
   - public struct WalletAmount: Equatable, Sendable { public let text: String /* trimmed, as passed */; public let value: Decimal; public let marks: [String] /* "€", "RWF", "CA$"; empty for a bare number */ }
   - public static func read(_ text: String, locale: Locale = .current) -> WalletAmount?
     a. Return nil for any '-' or U+2212, or when there is not exactly one number run.
     b. The number run is ASCII digits plus . , ' and ’ between digits. A space, U+00A0 or U+202F counts only when a group of three digits follows it.
     c. Marks are the non-space chunks around the run, with any trailing '.' dropped when comparing.
     d. value = ReceiptParser.number(run, decimalSeparator: locale.decimalSeparator?.first). When the marks name a currency with no minor unit (NumberFormatter.maximumFractionDigits == 0), parse with decimalSeparator nil, so '5,000' groups thousands.
     e. Return nil unless value > 0.
   - public func isWritten(in currencyCode: String, locale: Locale = .current) -> Bool. True when marks is empty, or when every mark (compared case-insensitively) is in the forms of currencyCode: the ISO code, NumberFormatter.currencySymbol in `locale` and in en_US, the narrow symbol extracted from Decimal(0).formatted(.currency(code:).presentation(.narrow).locale(en_US)) by dropping digits, separators and spaces, and every key of ReceiptParser.symbolCodes, prefixedSymbols and currencyAliases that maps to currencyCode.
   - public func otherCurrencyNote(recordedAs recorded: Decimal, appCurrencyCode: String, locale: Locale = .current) -> String?. Returns nil when isWritten. Otherwise: "The payment was \(text), but Keaser records amounts in \(code), so it will be added as \(MoneyFormat.string(recorded, currencyCode: code, locale: locale))."
   - Doc comments in the house style. No em dashes.
3. 2. QuickLog.swift:30-35: amount(from text:currencyCode:locale:) becomes WalletAmount.read(text, locale:).flatMap { amount(fromDecimal: $0.value, currencyCode:) }. Update the doc comment. MoneyFormat.parse stays unchanged for New Expense (AmountInput).
4. 3. LogWalletTransactionIntent.swift perform(), with the changes marked:
   let store = try IntentSupport.freshStore(); let target = try IntentSupport.account(nil, in: store); let code = store.preferences.currencyCode
   CHANGED: guard let paid = WalletAmount.read(amount), let value = QuickLog.amount(fromDecimal: paid.value, currencyCode: code) else { throw KeaserIntentError.invalidAmount }
   var expense = await QuickLog.walletExpense(... as today ...)
   NEW: if let note = paid.otherCurrencyNote(recordedAs: value, appCurrencyCode: code) {
     if isVoiceOnly { try await requestConfirmation(actionName: .add, dialog: "\(note) \(QuickLog.confirmationQuestion(for: expense, in: target, currencyCode: code))") }
     else { let card = ExpenseCardView(card: IntentSupport.card(for: expense, in: target, store: store)); try await requestConfirmation(actionName: .continue, dialog: "\(note) Confirm expense details:") { @Sendable in card } }
     Re-read with IntentSupport.freshStore(), re-resolve the account and labels as AddExpenseFlow.swift:46-52 does, then save.
     Return the quiet result exactly as AddExpenseFlow.swift:62-67 does (dialog nil, EmptyView).
   }
   Otherwise save and return as today.
   Also: add a private isVoiceOnly (a copy of AddExpenseFlow.swift:74-79), or move it into IntentSupport as a static helper taking `some AppIntent`. Update the type doc comment at :6-10 ('no confirmation, except for a payment in another currency') and the Amount parameter description at :20 to: "The amount as Wallet passes it, such as \"$4.50\" or \"4,50 €\"." Optionally add to IntentDescription: " A payment in another currency is shown to you first."
5. 4. SnippetPreview.swift: add Kind.walletOther. Its dialog is the real WalletAmount note plus " Confirm expense details:", built from WalletAmount.read("€1.60") (or "$1.60" when the seeded currency is EUR) with sample Watsons 1.60. Buttons: Cancel and Continue. Not interactive. Update the doc comment at :5-20.
6. 5. scripts/shots/shortcuts.txt: add 'wallet-other | -KeaserSeed demo -KeaserSnippet walletOther' and 'wallet-other-xxxl | -KeaserSeed demo -KeaserSnippet walletOther -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXXL'. Take screenshots in dark and light: ./scripts/screenshots.sh shortcuts, then APPEARANCE=light OUT=screenshots/light ./scripts/screenshots.sh shortcuts. Check that the three-line dialog wraps without truncation above the card at both sizes. AGENTS.md: add walletOther to the -KeaserSnippet row (line 108).
7. 6. Tests: the KeaserKit suite (Swift Testing) and KeaserIntentTests (see tests). Run ./scripts/test.sh and ./scripts/build.sh, then update the README badge (line 12) to the new count.
8. 7. FALLBACK, only if device question 1 or 2 says prompts cannot be shown or answered from a Run Immediately Wallet automation: skip the requestConfirmation branch. Save, then return IntentDialog "Added as \(recorded). The payment was \(text), and Keaser records amounts in \(code), so change the amount in Keaser if needed." with the normal card. Add a KeaserKit function for that sentence, with tests. Separately, tell the founder that the tutorial's default (Confirm Expense Details on) then fails for every Wallet payment, which is a bigger issue than this feature.
9. 8. OPTIONAL, +1.5 h: an in-card line. Add `paidAs: String?` to ShortcutCard and draw it under the 38 pt amount in ExpenseCardView as 'Paid €12.40' (callout, Color.keaserSnippetLabel, monochrome, centred, 6 pt below the amount, taking that space from the 20.5 pt bottom padding). Do it only if device question 8 shows the dialog sentence is truncated on the lock screen. It would also let Add Expense's card show 'Paid ¥1,500'.
10. 9. OPTIONAL, +1.5 h: an interactive Wallet card on iOS 26+. Add a KeaserKit ShortcutFlow init that confirms a finished Expense (sets the private(set) fields directly, so nothing is asked), then reuse AddExpenseFlow's confirm(_:currencyCode:voiceOnly:note:) after moving it to a shared AppIntent extension. Worth it only if the founder wants Account, Category and Payment to be changeable on the Wallet card.
11. 10. BRANCH B, if device question 4 shows that Shortcuts drops the currency when Wallet's text Amount feeds Add Expense's IntentCurrencyAmount (a silent $12.40): Add Expense cannot see the currency, so nothing inside Add Expense can warn. This is a product decision for the founder: reverse the tested rule that the Wallet tutorial teaches Add Expense (SettingsTutorialsTests.swift:39-42, commit dc0b570) and teach Log Wallet Transaction, which reads the text and gets this feature, or accept the gap. Estimate +4 to 6 h for the tutorial copy, illustrations (TutorialIllustrations.swift walletVariables) and tests. It is not included in effortHours.

**Tests**

- PlatformWalletAmountTests (Swift Testing, Mac, parameterised over (locale, text) -> (value, marks)):
- en_US: '€12.40' -> 12.40 ['€']; '$4.50' -> 4.50; 'CA$4.50' -> 4.50 ['CA$']; 'RWF 5,000' -> 5000; '¥1,500' -> 1500; '4,50 €' -> 4.50 (today 450); '1.234,56 €' -> 1234.56 (today 1.23); 'CHF 1’234.50' -> 1234.50; 'KWD 1.500' -> 1.500
- de_DE: '$4.50' -> 4.50 (today 450); '12,40 $' -> 12.40; 'RWF 5,000' -> 5000 (no minor unit)
- fr_FR: '1\u{202F}234,56 €' -> 1234.56; '4,50 $US' -> 4.50 ['$US']
- rw_RW: 'RF 5.000' -> 5000
- Refusals: '', 'free', '$0.00', '-$4.50', '−4,50 €', '1 2', '1.2.3', '12 34 56' -> nil.
- isWritten policy, for app currency USD:
- '$4.50', 'US$4.50', 'USD 4.50' and '4.50' are same
- '€12.40', 'CA$4.50', 'MX$250.00', 'CN¥1,500', 'RWF 5,000' and 'Rs 250' are other
- isWritten policy, other app currencies:
- app CAD with '$4.50' on en_US: same (documented shared-symbol limit)
- app EUR with '$4.50': other
- app BRL with '$4.50': other (narrow form 'R$' is compared by equality)
- app RWF: 'Frw 5,000', 'RF 5.000' and 'RWF 5,000' are same
- app SEK with 'kr 45.00': same
- app JPY with '¥1,500': same; app JPY with 'CN¥1,500': other
- Note copy, exact:
- ('€12.40', 12.40, USD, en_US) -> 'The payment was €12.40, but Keaser records amounts in USD, so it will be added as $12.40.'
- ('$4.99', 5, JPY, en_US) -> 'The payment was $4.99, but Keaser records amounts in JPY, so it will be added as ¥5.'
- nil for same-currency and bare-number input.
- QuickLog regression: keep PlatformTests.swift:125-129 as they are, and add QuickLog.amount(from: '4,50 €', currencyCode: 'USD', locale: en_US) == 4.5 plus de_DE '$4.50' == 4.5.
- ReceiptParser suites stay green (number() is shared; do not change its behaviour, add a wrapper instead).
- KeaserIntentTests (AppIntentsTesting, iOS 27 simulator; fixture currency is Locale.current's, USD, see Database.swift:125-127):
- testWalletAmountInKeasersCurrencyIsAddedAtOnce: Log Wallet Transaction with 'USD 4.50' and with '4,50 $' saves 4.50 each time. The second case fails on today's build.
- testWalletAmountInAnotherCurrencyIsNeverSavedUnconfirmed: run '€12.40' at 'Café de Flore' inside within(.seconds(20)). Expect a thrown error or TimedOut, then expenses.entities(matching: 'Café de Flore') is empty.
  Caveat: AppIntentsTesting cannot answer a confirmation (AppIntentsTesting.swiftinterface:256-272). First check that an unanswered requestConfirmation does not wedge the app for later tests; if it does, drop this test and rely on the KeaserKit tests plus the device test.
- Existing AddExpenseTests (testWalletTransactionIsFiledLikeTheLastOneThere, testWalletFollowsTheShortcutSmartSuggestionsSwitch) and ErrorTests.testWalletAsksForAnAccountFirst pass unchanged.
- Screenshots: shortcuts area wallet, wallet-other and wallet-other-xxxl, in dark and light.

**Risks**

- An unanswered forced card can lose the payment. If the person pays and pockets the phone, the Run Immediately automation may time out and log nothing, where today it logs a wrong number. Device question 2 decides whether the fallback (save and warn) is better.
- False warnings on domestic payments would be the worst outcome: a card on every tap. They happen if Wallet writes Keaser's own currency in a form outside the forms set. Mitigations: include the device-locale symbol, the en_US symbol, the narrow form, the ISO code and the aliases; test per locale; confirm the domestic text in device question 3.
- Shared symbols: a foreign dollar written with a bare '$' (or yen and yuan with '¥', or 'kr') counts as Keaser's currency when Keaser's currency is written the same way, so that payment is not caught. This is accepted and documented. The stricter 'the phone's currency owns its bare symbol' rule waits for proof that Wallet formats with the phone's locale.
- Branch B: if Shortcuts coerces Wallet's text Amount into Add Expense's IntentCurrencyAmount with the phone's currency, the tutorial path (the one most users follow) stays silent, and fixing it means reversing a tested product rule (SettingsTutorialsTests.swift:39-42).
- Coupling: WalletAmount reuses internal ReceiptParser.number, currency tables and forms. A later receipt tweak could change Wallet parsing. Tests on both sides guard this; do not edit number(), wrap it.
- AppIntentsTesting cannot answer confirmations, so the mismatch path is only partly covered by automated tests. It must be checked on a device.
- Only an iOS 27 simulator runtime exists locally. The iOS 18 to 25 card and the real system chrome are only approximated by SnippetPreview.
- No conversion: Continue still records €12.40 as $12.40 in totals, widgets and the weekly summary until the person edits it. Real multi-currency support is out of scope. Changing Settings > Currency during a trip relabels history without converting it, as it does today.
- Amounts above 999,999,999 (VND, IDR) are refused by ReceiptParser.number's 9-digit cap. This is rare, but it is a new refusal that today's parser does not have.
- Wording in the dialog is English-only and interpolated, like the existing notes. This is consistent with the app.

**Value**

The value is moderate and the cost is low (about 8 h, plus 1.5 h for each optional item and 4 to 6 h if branch B is chosen).

The currency warning itself only matters to travellers and to people whose phone locale differs from Keaser's currency. For them, silently turning €12.40 into $12.40, or "4,50 €" into 450, corrupts totals, widgets and the weekly summary, which is worse than an extra tap. The parser part fixes a real, confirmed misreading (a Mac probe of the same code gives en_US "4,50 €" -> 450, de_DE "$4.50" -> 450, en_US "1.234,56 €" -> 1.23), and it reuses Keaser's tested receipt heuristics instead of DataDetection, which the probe shows is unreliable for RWF, CN¥, kr and decimals.

The biggest uncertainty is what most users actually run: the tutorial teaches Add Expense, not Log Wallet Transaction. If Shortcuts keeps the currency when it turns Wallet's Amount into a currency amount (branch A), those users are already protected, and this work mainly hardens Log Wallet Transaction and fixes its parsing. If it drops the currency (branch B), the real fix is a founder decision about the tutorial.

Recommendation: build it after the device test, but only in the form that questions 1, 2 and 4 support. Keep conversion and multi-currency out of scope.

## 2. Quick Expense control ("log my usual coffee")

A configurable "Quick Expense" control for Control Center, the Lock Screen and the Action button. You pick an expense you have logged before (for example Coffee, $4.50, Food & Drinks, Credit Card, Personal), and each tap logs it again straight away: no questions, no confirmation, no Smart Suggestions, dated when you tap. You can add several controls, each with its own expense, so your usual coffee, bus fare and lunch are each one press away.

**Behaviour**

NAMING AND COPY (all English, like the rest of Keaser; no reference exists, so it follows the Add Expense control and the expense card wording)
- Controls gallery: displayName "Quick Expense"; description "Add an expense you make often, like your morning coffee, in one tap." It sits right after "Add Expense" in KeaserWidgetsBundle.
- Configuration card: iOS shows it automatically when the control is added to Control Center, the Lock Screen or the Action button (.promptsForUserConfiguration()), and again when the person touches and holds the control in edit mode. It has one row: "Expense". The parameter description reads: "Pick one you have added before. Each tap adds it again with the same amount, category, payment method and account, dated when you tap." ControlConfigurationIntent title is "Quick Expense"; its description is "Choose the expense this control adds."
- Expense picker (the query's suggestedEntities): one row per distinct title, showing the person's usual version. Row title is the expense title ("Coffee"). Row subtitle is "$4.50 · Food & Drinks · Credit Card", with " · Personal" appended only when there is more than one account; it uses the middle dot, like ExpenseSummary.subtitle. Row image is the category's SF Symbol, or "creditcard" (ExpenseCategory.fallbackSymbol) when there is no category. The "usual" amount is the one used most often for that title in the last 90 days (a tie goes to the most recent). Labels come from the latest expense with that title and amount. Rows are sorted by how often they were used, then by how recently, with at most 15 per account. With two or more accounts that have expenses, the list is split into sections named after the accounts, with the selected account first (IntentItemCollection sections). promptLabel is "Choose an Expense". Typing in the search field (entities(matching:)) searches every account, ignoring case and accents (QuickLog.normalized). It lists each amount variant separately ("Coffee", "$5.20 · Food & Drinks · Cash"), at most 50. There are no expenses at all on a fresh install, so the list is empty and the parameter description tells the person to add the expense in Keaser once first. Typed presets like "Coffee 4.50" are left for v1.1 (see risks).
- Control face, when ready: symbol is the category's SF Symbol; title is "Coffee"; value text is "$4.50" (MoneyFormat.string with store.preferences.currencyCode, so it follows the current currency and never converts). Control Center shows the title and value only at the larger sizes. The Lock Screen shows only the symbol. Action button hint: .controlWidgetActionHint("Add Coffee"), which the system shows as "Hold to Add Coffee".
- While the tap is being performed (ControlWidgetButton actionLabel isActive == true), the value reads "Adding…".
- After perform returns, the system reloads the control (Apple: "The system queries for the state of a control when perform() returns"). The value goes back to "$4.50". Control Center also shows the momentary status "Added to Personal" (.controlWidgetStatus). The status appears only if the value provider finds an expense in the resolved account with the same title and amount and a createdAt in the last 15 seconds. It is derived from the database, so there is no new persistence.
- Not configured yet (shown briefly before the prompt, or if the prompt is dismissed): symbol "creditcard", title "Quick Expense", value "Choose an Expense", .disabled(true).
- No account at all (every account deleted, or a fresh install): the title stays the preset's, value "No Account", .disabled(true).
- Gallery preview (previewValue with no configuration): "Coffee", "$4.50" in the person's currency (Preferences.defaultCurrencyCode when there is no database yet), symbol "cup.and.saucer.fill".

WHAT A TAP DOES (LogQuickExpenseIntent.perform, in the app process)
1. IntentSupport.freshStore(). Before the first unlock this throws dataUnavailable; while an earlier save error is pending it throws saveFailed.
2. The preset is resolved against the current data. Account: the preset's own if it still exists, otherwise the account selected in Keaser (the rule IntentSupport.account(_:in:) already applies); no account throws KeaserIntentError.noAccount. Category and payment method: QuickLog.category(id:name:in:) and paymentMethod(id:name:in:), which try the same ID first and then the same name in that account (so a category deleted and recreated, or a preset whose account fell back, still files correctly). If neither is found, the expense is saved with no category or no payment method; a deleted label never comes back.
3. Expense(title, amount, categoryID, paymentMethodID, date: now, createdAt: now), saved with IntentSupport.save. That reloads the widgets, the weekly summary and Spotlight, exactly like Add Expense and Log Wallet Transaction.
4. It returns .result(dialog: QuickLog.confirmation(...)), for example "Added $4.50 for Coffee to Personal." Controls do not show dialogs today (an Apple frameworks engineer says there is no supported way), so this only matters if the device test shows otherwise. No snippet card is returned, so a one-tap action never waits on a Done button.
5. Unconfigured (expense == nil): throws IntentRefusal("Choose an expense for this control first."). The control is disabled in that state anyway.

INTERACTION WITH EXISTING FEATURES AND SWITCHES
- Confirm Expense Details (shortcutConfirmsDetails): ignored. The preset was confirmed when it was chosen, and a confirmation would defeat the purpose of one tap. The Settings footnote talks about "the shortcut", so its copy stays true.
- Smart Suggestions (both smartSuggestionsEnabled and shortcutSmartSuggestionsEnabled) and the on-device CategoryModels: never consulted at tap time. The labels are exactly the preset's. Go Back: not applicable.
- Currency: the stored number is kept and shown in the current currency (Keaser never converts). The app reloads the control on preferencesChanged.
- Labels renamed, recoloured or deleted, or the account renamed or deleted: the app's existing store observer in KeaserApp.init also calls ControlCenter.shared.reloadControls(ofKind: QuickExpense.controlKind) on accountUpdated, accountDeleted, accountCreated, preferencesChanged and reloaded, so symbol and value stay current.
- Pro: recommended free, like the Add Expense control. Only creating a second account is Pro-gated today, and presets in existing accounts keep working after Pro ends. (Founder decision, see risks.)
- No donation (IntentDonations) and no App Shortcut phrase in v1. The control is the shortcut. A "Add \(\.$expense) in Keaser" App Shortcut is a cheap follow-up once the entity exists (7 of 10 App Shortcut slots are used).
- Several instances: each control carries its own configuration (AppIntentControlConfiguration), so Coffee, Bus and Lunch can each have a control, and the same preset can live on both the Lock Screen and Control Center.
- The expense's identity is self-contained: the entity ID encodes the preset (see steps), so editing or deleting the expense the preset was taken from never changes or breaks the control. To change the amount, the person reconfigures the control.
- In-app surfaces (kept minimal to protect the 1:1 clone): a new note in the Add Expense Shortcut tutorial, after "Quickest of All: Keaser's Control". Symbol "cup.and.saucer.fill", title "One Tap for Your Usuals", text: "For something you buy again and again, add Keaser's **Quick Expense** control and pick the expense once. Each tap adds it again, with the same amount, category and payment method, and asks nothing." Plus one highlight in the next ReleaseHistory entry: "Quick Expense control: log your usual coffee in one tap." No new Settings row or switch.

PROCESS AND AVAILABILITY
- Everything is iOS 18.0 (controls exist from iOS 18.0), so there is no extra gating beyond the pinning below. The intent is pinned to the app process exactly as AddExpenseIntent is: iOS 26 supportedModes [.background, .foreground(.dynamic)] (continueInForeground is never called); iOS 27 allowedExecutionTargets .main; before iOS 26 an app-only ForegroundContinuableIntent conformance. The widget extension compiles its own fallback perform, which writes nothing. authenticationPolicy stays the default .alwaysAllowed, like AddExpenseIntent, so it works on a locked phone after first unlock. The database is written with completeFileProtectionUntilFirstUserAuthentication.

**APIs** (verify again before use)

- AppIntentControlConfiguration.init<Provider>(kind: String, provider: Provider, @ControlWidgetTemplateBuilder content: @escaping (Provider.Value) -> Content) where Configuration == Provider.Configuration, Provider: AppIntentControlValueProvider (iOS 18.0; iPhoneOS27.0.sdk WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface:494-508; Apple doc 'Adding refinements and configuration to controls' (developer.apple.com/documentation/widgetkit/adding-refinements-and-configuration-to-controls))
- protocol AppIntentControlValueProvider { associatedtype Value; associatedtype Configuration: ControlConfigurationIntent; func previewValue(configuration:) -> Value; func currentValue(configuration:) async throws -> Value } (iOS 18.0; WidgetKit.swiftinterface:485-490)
- protocol ControlConfigurationIntent: AppIntent (no perform needed; a parameter without a default must be optional so the system can preview an unconfigured control) (iOS 18.0; AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface:56-61; developer.apple.com/documentation/appintents/controlconfigurationintent)
- ControlWidgetConfiguration.displayName(_:), .description(_:), .promptsForUserConfiguration() (iOS 18.0; WidgetKit.swiftinterface:1265, 1267, 1269)
- ControlWidgetButton.init(_ title: some StringProtocol, action: Action, @ViewBuilder actionLabel: @escaping (Bool) -> ActionLabel) where Action: AppIntent (Bool is true while the action is performed; Apple's example shows subtitle text only while active) (iOS 18.0; WidgetKit.swiftinterface:1309 (LocalizedStringKey variant 1301); developer.apple.com/documentation/widgetkit/controlwidgetbutton/init(_:action:actionlabel:))
- ControlWidgetTemplate.disabled(_:), .privacySensitive(_:), .tint(_:) (iOS 18.0; WidgetKit.swiftinterface:472-479)
- View.controlWidgetStatus(_: some StringProtocol) and View.controlWidgetActionHint(_: some StringProtocol) (status is momentary Control Center text shown when the action is performed; a button hint is prefixed with 'Hold to') (iOS 18.0; WidgetKit.swiftinterface:520-545; Apple doc 'Adding refinements and configuration to controls', sections 'Refine Action button hint text' and 'Add Control Center status text')
- ControlWidgetTemplateBuilder: only buildExpression and buildBlock (no buildEither/buildOptional), so one closure must return a single ControlWidgetButton with a single Action type; hence LogQuickExpenseIntent takes an optional expense (iOS 18.0; SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface:21547-21596)
- ControlCenter.shared.reloadControls(ofKind: String) / reloadAllControls() / currentControls() async throws -> [ControlInfo] (iOS 18.0; WidgetKit.swiftinterface:195-200)
- AppIntent.supportedModes: IntentModes ([.background, .foreground(.dynamic)] = run in either, prefer background) (iOS 26.0 (witness marked @available(iOS 26.0, *)); AppIntents.swiftinterface:3107, 3239, 3250-3275; developer.apple.com/documentation/appintents/appintent/supportedmodes)
- AppIntent.allowedExecutionTargets: IntentExecutionTargets { .main } (iOS 27.0 (witness marked @available(iOS 27.0, *)); AppIntents.swiftinterface:3112, 3152, 3571-3585; developer.apple.com/documentation/appintents/intentexecutiontargets)
- protocol ForegroundContinuableIntent (deprecated in iOS 26, unavailable in app extensions): app-only conformance pins the intent to the app process before iOS 26 (iOS 16.4 to 25.x use; conformance in the app target only; AppIntents.swiftinterface:3505-3514; existing pattern KeaserWidgets/Shared/AddExpenseIntent.swift:59-63)
- AppIntent.isDiscoverable (false keeps LogQuickExpenseIntent out of Shortcuts and Siri) (iOS 17.0; AppIntents.swiftinterface:3110, 3148)
- AppIntent.authenticationPolicy: IntentAuthenticationPolicy (.alwaysAllowed default, .requiresAuthentication, .requiresLocalDeviceAuthentication) (iOS 16.0; AppIntents.swiftinterface:3108, 3135, 3167-3170)
- EntityStringQuery { entities(for: [String]), suggestedEntities() -> Result, entities(matching:) -> Result } with Result = IntentItemCollection<QuickExpenseEntity> (iOS 16.0; AppIntents.swiftinterface:4200-4231)
- IntentItemCollection(promptLabel:usesIndexedCollation:sections:) and IntentItemSection(_ title: LocalizedStringResource, items: [Result]) (iOS 16.0 (titled section init iOS 16.4); AppIntents.swiftinterface:4970-4976, 4988-4999)
- AppEntity with a String ID (the self-contained preset identifier) (iOS 16.0; AppIntents.swiftinterface:413 (ID: EntityIdentifierConvertible & Sendable))
- Controls cannot show dialogs or errors ('There's no supported way for you to show errors from Controls with the APIs currently available', Apple Frameworks Engineer) (iOS 18 statement; iOS 26/27 unconfirmed; developer.apple.com/forums/thread/759853; contrast: developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets lists Control Center and the Action button among surfaces where an intent 'can return a static snippet')
- AppIntentsTesting IntentDefinitions.intents[...].makeIntent(...).run(), AppEntityDefinition.suggestedEntities() / entities(matching:) (iOS 27 test target only (KeaserIntentTests); Xcode Platforms/iPhoneOS.platform/Developer/Library/Frameworks/AppIntentsTesting.framework/Modules/AppIntentsTesting.swiftmodule/arm64e-apple-ios.swiftinterface:111-223, 257-271)
- UNMutableNotificationContent.interruptionLevel (.passive/.active), threadIdentifier; UNNotificationAction (only for the optional phase 2 lock screen feedback) (iOS 15.0 (interruptionLevel); UserNotifications.framework/Headers/UNNotificationContent.h:20-32, 122, 143; UNNotificationAction.h:46)

**Files**

- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Platform/QuickExpense.swift (new: QuickExpense preset, identifier coding, resolve, QuickExpenseCatalog usual/sections/matching, QuickExpenseControlState, controlKind)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Tests/KeaserKitTests/PlatformQuickExpenseTests.swift (new)
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserWidgets/Shared/QuickExpenseEntity.swift (new, compiled into app and extension: QuickExpenseEntity + QuickExpenseQuery)
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserWidgets/Shared/LogQuickExpenseIntent.swift (new, both targets: declaration, supportedModes, allowedExecutionTargets, app-only ForegroundContinuableIntent)
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserWidgets/QuickExpenseControl.swift (new, extension only: ControlWidget, QuickExpenseConfiguration, value provider, extension fallback perform)
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserWidgets/KeaserWidgetsBundle.swift (add QuickExpenseControl() after AddExpenseControl())
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/LogQuickExpenseFlow.swift (new, app perform)
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/App/KeaserApp.swift (store observer also reloads the Quick Expense controls on account, label, currency and reload changes)
- /Users/FullTimeStudio/Dev/apps/keaser/KeaserIntentTests/QuickExpenseTests.swift (new)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Settings/Tutorials.swift (one note in addExpenseShortcut closing section)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Tests/KeaserKitTests/SettingsTutorialsTests.swift (adjust if it counts notes)
- /Users/FullTimeStudio/Dev/apps/keaser/Packages/KeaserKit/Sources/KeaserKit/Settings/ReleaseHistory.swift (highlight in the next entry)
- /Users/FullTimeStudio/Dev/apps/keaser/AGENTS.md (Shared names: LogQuickExpenseIntent 'Add Quick Expense', QuickExpenseControl kind; Where things live: shortcuts row)
- /Users/FullTimeStudio/Dev/apps/keaser/README.md (test badge count)
- /Users/FullTimeStudio/Dev/apps/keaser/scripts/shots/shortcuts.txt (tutorial note shot; optional control stand-in shots)
- /Users/FullTimeStudio/Dev/apps/keaser/Keaser/Intents/SnippetPreview.swift or a new Keaser/Intents/ControlPreview.swift (optional DEBUG -KeaserControl stand-in)
- No project.yml change: KeaserWidgets/Shared is already a source of both targets (project.yml app sources list KeaserWidgets/Shared; the extension compiles all of KeaserWidgets)

**Steps**

1. 0. Gate: do not start until the founder's device test answers the questions below. In particular, it must show that the current Add Expense control runs in the app process on their iOS version. The new intent uses the same pinning, so if that fails, fix the pinning (or switch to plan B in step 9) first.
2. 1. KeaserKit, Platform/QuickExpense.swift. `public struct QuickExpense: Hashable, Sendable, Codable` with accountID, title, amount (Decimal, encoded as a POSIX string so it survives JSON exactly), categoryID/categoryName, paymentMethodID/paymentMethodName. `public init(_ expense: Expense, in account: Account)` copies the names at pick time. `public var identifier: String` is "q1." + base64url(JSON), with a sorted-keys encoder so the same preset always gives the same ID. `public init?(identifier:)` accepts only the q1 prefix and valid JSON, and keeps decoding q1 forever. `public static let controlKind = "com.fulltimestudio.keaser.quick-expense"`.
3. 2. KeaserKit resolution: `public func resolve(in database: Database) -> QuickExpense.Resolved?`. Account: the same ID, otherwise database.selectedAccount, otherwise nil. Labels: QuickLog.category(id:name:in:) / paymentMethod(id:name:in:) when an ID is present (the name fallback handles a changed account or a recreated label), otherwise nil. `Resolved.expense(now: Date) -> Expense` sets date and createdAt to now, trims the title (falling back to QuickLog.defaultTitle when empty), and never calls SmartSuggester.
4. 3. KeaserKit catalog: `QuickExpenseCatalog.usual(in account: Account, now: Date, calendar: Calendar) -> [QuickExpense]` gives one per normalized title. Amount is the most frequent over 90 days (a tie goes to the latest; if nothing falls in the window, the latest overall). Labels come from the latest expense with that title and amount. Sorted by count, then recency, limit 15. `sections(in: Database, now:) -> [(Account, [QuickExpense])]` puts the selected account first and skips accounts with no expenses. `matching(_ text: String, in: Database, limit: 50)` returns title-contains matches across accounts, one per (title, amount) variant. `display(in: Database, currencyCode:, locale:) -> (title, subtitle, symbol)` gives "$4.50 · Food & Drinks · Credit Card" plus " · Personal" only with 2+ accounts.
5. 4. KeaserKit control state: `public struct QuickExpenseControlState: Equatable, Sendable { title, value, symbol, actionHint: String?, status: String?, isEnabled }`. `static func make(preset: QuickExpense?, database: Database, now: Date, locale: Locale) -> Self` covers unconfigured ("Quick Expense" / "Choose an Expense" / creditcard / disabled), no account ("No Account", disabled), and ready (MoneyFormat value, actionHint "Add <title>"). status is "Added to <account>" when the resolved account has an expense with the same normalized title and amount created within `statusWindow` (15 s) of now. `static func preview(currencyCode:locale:)` gives Coffee / 4.50 / cup.and.saucer.fill.
6. 5. KeaserKit tests: PlatformQuickExpenseTests.swift (Swift Testing, see tests). Run ./scripts/test.sh.
7. 6. Shared entity, KeaserWidgets/Shared/QuickExpenseEntity.swift: `struct QuickExpenseEntity: AppEntity, Identifiable { let id: String; let preset: QuickExpense; let subtitle: String; let symbol: String; @Property(title: "Title") var title: String }`. typeDisplayRepresentation is "Quick Expense" (synonyms "Usual Expense", "Favorite Expense"). displayRepresentation is title + subtitle + systemName symbol. `QuickExpenseQuery: EntityStringQuery`: entities(for:) decodes each ID with QuickExpense(identifier:) and refreshes the display from DatabaseFile.shared.load(), keeping undecodable IDs out. suggestedEntities() returns IntentItemCollection(promptLabel: "Choose an Expense", sections: one IntentItemSection per account when 2+ accounts have expenses, otherwise one untitled section). entities(matching:) is also an IntentItemCollection. Nothing in it depends on the app process.
8. 7. Shared intent, KeaserWidgets/Shared/LogQuickExpenseIntent.swift: `struct LogQuickExpenseIntent: AppIntent { static let title: LocalizedStringResource = "Add Quick Expense"; static let isDiscoverable = false; @available(iOS 26.0, *) static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }; @available(iOS 27.0, *) static var allowedExecutionTargets: IntentExecutionTargets { .main }; @Parameter(title: "Expense") var expense: QuickExpenseEntity?; init() {}; init(expense: QuickExpenseEntity?) }`, plus `@available(iOSApplicationExtension, unavailable) @available(iOS, deprecated: 26.0, message: "supportedModes does this from iOS 26") extension LogQuickExpenseIntent: ForegroundContinuableIntent {}`. Copy the comments from AddExpenseIntent.swift.
9. 8. App perform, Keaser/Intents/LogQuickExpenseFlow.swift: `@MainActor func perform() async throws -> some IntentResult & ProvidesDialog`. Unconfigured throws IntentRefusal("Choose an expense for this control first."). Then freshStore(), resolve (nil throws KeaserIntentError.noAccount), save with IntentSupport.save, and return .result(dialog: "\(QuickLog.confirmation(amount:currencyCode:accountName:title:))"). No confirmation, no ShortcutFlow, no CategoryModels, no donation.
10. 9. Extension side, KeaserWidgets/QuickExpenseControl.swift. `struct QuickExpenseConfiguration: ControlConfigurationIntent { title "Quick Expense"; description "Choose the expense this control adds."; @Parameter(title: "Expense", description: "Pick one you have added before. Each tap adds it again with the same amount, category, payment method and account, dated when you tap.") var expense: QuickExpenseEntity? }`. Provider: AppIntentControlValueProvider with Value { expense: QuickExpenseEntity?; state: QuickExpenseControlState }. currentValue reads DatabaseFile.shared.load() and calls QuickExpenseControlState.make. previewValue uses the configured preset if any, else .preview. The control is AppIntentControlConfiguration(kind: QuickExpense.controlKind, provider:) { value in ControlWidgetButton(value.state.title, action: LogQuickExpenseIntent(expense: value.expense)) { isActive in the label, i.e. Label(isActive ? "Adding…" : value.state.value, systemImage: value.state.symbol).controlWidgetActionHint(...), with .controlWidgetStatus(status) applied only in an if-branch when status != nil and !isActive } .disabled(!value.state.isEnabled) }, then .displayName("Quick Expense").description("Add an expense you make often, like your morning coffee, in one tap.").promptsForUserConfiguration(). Extension fallback: `extension LogQuickExpenseIntent { func perform() async throws -> some IntentResult & ProvidesDialog { .result(dialog: "Open Keaser to add this expense.") } }`. PLAN B, only if the device test shows control intents never reach the app: the fallback writes instead, through `KeaserStore(file: .shared)`. The save is atomic (DatabaseFile.save uses .atomic), the app already reloads from disk when it becomes active, and Spotlight and the weekly summary catch up there. Then call WidgetCenter.shared.reloadAllTimelines().
11. 10. Register: add QuickExpenseControl() to KeaserWidgetsBundle after AddExpenseControl(). In KeaserApp.init, extend the existing observer: on .accountCreated/.accountUpdated/.accountDeleted/.preferencesChanged/.reloaded, call ControlCenter.shared.reloadControls(ofKind: QuickExpense.controlKind). Expense saves need no control reload, because the system reloads the tapped control itself.
12. 11. AppIntentsTesting: KeaserIntentTests/QuickExpenseTests.swift (see tests). Run ./scripts/intents-test.sh on the iOS 27 simulator.
13. 12. Copy and docs: the tutorial note, the ReleaseHistory highlight, AGENTS.md (Shared names + shortcuts area row), README badge. Screenshot the tutorial page: `tutorial-shortcut-bottom | -KeaserSeed single -KeaserSheet settings -KeaserSettingsPage tutorialShortcut -KeaserSettingsScroll bottom` in scripts/shots/shortcuts.txt, light and dark.
14. 13. Optional (2 h): DEBUG `-KeaserControl quickExpense|quickExpenseUnset|quickExpenseNoAccount|quickExpenseAdded` (+ `-KeaserSnippetLong 1`). It is a stand-in, like SnippetPreview, that draws QuickExpenseControlState at the 1x1, 2x1 and 2x2 Control Center sizes, a Lock Screen corner and the Action button hint pill, so copy and truncation can be checked headlessly. The real control is drawn by the system and cannot be screenshotted.
15. 14. Device verification (founder's iPhone, 2 h): add two controls (Coffee, Bus) to Control Center, one to the Lock Screen, one to the Action button. Tap each unlocked, locked after first unlock, and with Keaser force-quit. Check that the expense appears in Home and the Spending widget, that the status and hint copy show, that the control is disabled when unconfigured, and what happens after the preset's category or account is deleted.

**Tests**

- KeaserKit PlatformQuickExpenseTests: identifier round-trips title with accents, emoji, quotes and '|' plus amount 4.50 exactly (Decimal, not 4.4999), with and without labels; the same preset always gives the same identifier.
- KeaserKit: QuickExpense(identifier:) returns nil for a missing prefix, a future prefix ('q2.'), bad base64 and bad JSON.
- KeaserKit catalog: one row per title; usual amount is the most frequent over 90 days, a tie goes to the latest, and with nothing in the window the latest overall; labels come from the latest expense with that amount; sorted by count then recency; limit 15; sections put the selected account first and skip empty accounts; account names appear in the subtitle only with 2+ accounts.
- KeaserKit matching: case- and accent-insensitive ('cafe' finds 'Café'), searches every account, returns one row per amount variant, limit 50, empty text returns nothing.
- KeaserKit resolve: same account and labels; a renamed category keeps its ID and shows the new name; a deleted category that was recreated with the same name is matched by name; a deleted category with nothing matching gives nil; a deleted account falls back to the selected account with labels matched by name; no accounts gives nil.
- KeaserKit expense(now:): date and createdAt == now, amount unchanged, labels exactly the preset's even when SmartSuggester would guess otherwise (a regression test that suggestions never apply).
- KeaserKit control state: unconfigured, no account, ready (value formatted in the current currency, e.g. EUR after a currency change, same number); actionHint 'Add Coffee'; status 'Added to Personal' only when a matching expense (title and amount) was created within 15 s in the resolved account, not for an older one, not for another title or amount, not in another account; preview state.
- AppIntentsTesting QuickExpenseTests: after ResetTestDataIntent, definitions.entities["QuickExpenseEntity"].suggestedEntities() lists 'Coffee' from Personal, and entities(matching: "cof") returns its amount variants.
- AppIntentsTesting: reset with confirmsDetails: true and shortcut suggestions on, add 'Coffee 4.50' to Business with AddExpenseIntent, fetch its QuickExpenseEntity via entities(matching:), then run definitions.intents["LogQuickExpenseIntent"].makeIntent(expense: entity).run(). It must return without asking anything; spent("today", account: "Business") goes up by exactly 4.50 each run (run twice and expect 9.00); the new ExpenseEntity has the preset's category and payment method.
- AppIntentsTesting: fetch a preset entity, reset with accounts: false, run the intent, and expect the 'Create an account in Keaser first.' error; running with no expense expects 'Choose an expense for this control first.'
- Build check: ./scripts/build.sh must compile both targets with no deprecation errors (the ForegroundContinuableIntent warning is already accepted for AddExpenseIntent) and no ControlWidgetTemplateBuilder conditionals.
- Device only (cannot be automated): the control face, 'Adding…', the Control Center status, the Action button hint, the Lock Screen, the locked phone, force-quit, and the reload after label changes.

**Risks**

- Feedback is the weakest part. An Apple frameworks engineer says there is 'no supported way' to show errors (or dialogs) from controls (forums thread 759853), while Apple's snippet doc lists Control Center and the Action button among the surfaces where an intent can return a snippet. The design relies only on documented control feedback: the 'Adding…' action label and the momentary Control Center status. The Lock Screen shows only a symbol and gets no status, so a failed tap there is silent. Phase 2, only if the device test says so: a passive notification ('Added Coffee', '$4.50 to Personal', threadIdentifier quick-expense), sent only when notifications are already authorised.
- App-process pinning is unproven on device. If a control's intent runs in the extension anyway, the fallback writes nothing and the tap silently does nothing. The Add Expense control has the same exposure, and the device test tells us. Plan B (extension writes through KeaserStore(file: .shared)) is feasible but changes the rule that only the app writes the file. It carries a small last-writer-wins race with an app-process intent writing at the same moment.
- The Lock Screen shows only symbols. Two presets in the same category (Coffee and Lunch, both fork.knife) look identical there. A per-control symbol parameter (an AppEnum of about 12 curated symbols) is a v1.1 option if the founder uses the Lock Screen.
- Picking from history needs the expense to be logged once. A fresh install shows an empty picker, and there is no way to type 'Coffee 4.50'. A v1.1 option: entities(matching:) parses a trailing amount into a new preset. But its labels would have to be guessed with no way to correct them, so it is deliberately left out of v1.
- Accidental double logging in Control Center (a plain tap, unlike the long press on the Lock Screen and Action button). The mitigation in v1 is the visible 'Adding…' and status. A 5-second same-preset guard is cheap to add if the device test shows double taps.
- Tap latency: IntentSupport.save awaits the weekly summary and Spotlight refresh (a few seconds each at most), so 'Adding…' may show for a few seconds. If that feels slow, skip awaiting them in this intent, since they catch up on the next launch.
- Unconfigured controls: the template builder has no conditionals, so the button always carries LogQuickExpenseIntent with an optional expense. The control relies on .disabled(true) and promptsForUserConfiguration to keep it from being tapped unconfigured.
- The identifier format is a forever contract: controls store the q1 ID string. Never change the q1 encoding. Add q2 alongside it if ever needed.
- Undocumented rendering: how the control configuration card renders IntentItemCollection sections, promptLabel and search, and whether controlWidgetStatus shows for buttons as it does for toggles, must be checked on device.
- Product decisions for the founder: free (recommended, like the Add Expense control) or part of Pro 'Widgets'. Gating adds about 1 h (a locked state in QuickExpenseControlState plus a ProEntitlement check in the provider and in perform). Also: the name 'Quick Expense'.
- 1:1 clone drift: the control has no reference, so the in-app footprint is limited to one tutorial note and a What's New line. No Settings switch.

**Value**

Worth building, at about 14 hours (16 with the optional screenshot stand-in), once the device test confirms that control intents run in the app process. People who log the same things every day (coffee, transit, lunch) get the biggest gain: logging drops to one press, and that daily habit is what makes an expense tracker stick. It also fixes a real gap. Today the only prompt-free route is a hand-built shortcut per item, plus turning off Confirm Expense Details for every shortcut. Most of the cost is plumbing Keaser already has (the pinned intent pattern, shared entities, IntentSupport.save, QuickLog label matching), and the new logic is pure and unit-testable in KeaserKit. The honest limits are weak feedback on the Lock Screen and the Action button (Apple offers no dialogs from controls), and that each preset has a fixed amount, so people whose purchases vary will get little from it. If the device test shows the existing Add Expense control failing silently, fix that first: the two features share the same execution risk.

## 3. Edit Expense Siri action

An "Edit Expense" action for Siri and Shortcuts. It changes the amount, title, category, payment method, date or account of an expense without opening Keaser, for example "Change my last expense in Keaser" or "Move my last expense to Transportation in Keaser". It always shows what will change before saving and brings the widgets, weekly summary and Spotlight up to date. When it runs with Keaser open on iOS 26 or later, the system's Undo puts the old values back.

**Behaviour**

ENTRY POINTS
- Shortcuts action "Edit Expense" (square.and.pencil in the gallery, shortTitle "Edit Expense", systemImageName "pencil"). Description: "Changes an expense in Keaser after you confirm. When no expense is chosen, it changes the last one you added."
- Parameter summary: Summary("Edit \(\.$expense)") { \.$amount; \.$expenseTitle; \.$category; \.$paymentMethod; \.$date; \.$account; \.$confirmsChanges }. Every parameter the intent may ask for is in the summary. Apple forum thread 762188 reports that requestValue fails on iOS 18 for a parameter left out of the summary, so there are no hidden parameters.
- Parameters (the titles and descriptions are the exact copy):
  - expense: ExpenseEntity?, "Expense", "When empty, the last expense you added."
  - amount: IntentCurrencyAmount?, "Amount", "The new amount."
  - expenseTitle: String?, "Title", "The new title."
  - category: CategoryEntity? (optionsProvider: the selected account's categories plus "None"), "Category", "The new category. None removes it."
  - paymentMethod: PaymentMethodEntity? (options: the selected account's methods plus "None"), "Payment Method", "The new payment method. None removes it."
  - date: Date? (kind .date), "Date", "The new day."
  - account: AccountEntity?, "Account", "Moves the expense to this account."
  - confirmsChanges: Bool (default true), "Confirm Changes", "Shows the changes before saving them."
- App Shortcut: this is the 8th of 10. Phrases (at most one parameter each, and only AppEntity or AppEnum types are allowed):
  - "Edit my last expense in \(.applicationName)"
  - "Change my last expense in \(.applicationName)"
  - "Fix my last expense in \(.applicationName)"
  - "Move my last expense to \(\.$category) in \(.applicationName)"
  - "File my last expense under \(\.$category) in \(.applicationName)"
  An amount can never be part of a phrase. On iOS 18 to 26, "to 15 dollars" is therefore asked for as a follow-up question. Whether iOS 27 Siri fills the amount by itself is device question 1.

WHICH EXPENSE
- When `expense` is set, that expense is edited. Siri resolves "the Uber expense" through ExpenseEntityQuery.entities(matching:), which returns the newest match first.
- When `expense` is unset, the intent edits the last expense added: the latest createdAt across every account. This is not the newest date, so a backdated expense that was just logged still counts as "last". The card and the question always name it.
- When there are no expenses at all, the intent refuses with "There are no expenses in Keaser to edit yet."
- When the expense has been deleted in the meantime, it reuses Delete's refusal: "That expense is no longer in Keaser." (kind AppIntentError.Unrecoverable.entityNotFound).

WHAT CHANGES (explicit vs unset)
- On iOS 18.2 and later each optional parameter is read through `$param.valueState`. `.unset` keeps the value, `.set(value)` changes it, and `.set(nil)` clears it. WWDC26 session 344 defines these meanings. Clearing only applies to category and payment method; for amount, title, date and account, `.set(nil)` keeps the value. On iOS 18.0 and 18.1, nil means keep.
- The "None" sentinels (CategoryEntity.noCategory, PaymentMethodEntity.noPaymentMethod, fixed ID ExpenseEdit.noneID) also clear. They are the reliable way to clear from the Shortcuts editor and from voice lists.
- Amount: rounded to the currency's digits (QuickLog.amount(fromDecimal:)). Zero or less is refused with "Enter an amount greater than zero." An amount passed in another currency is recorded as the same number in Keaser's currency, never converted, and always confirmed with this lead sentence: "The shortcut passed €15.00, but Keaser records amounts in USD, so it will be saved as $15.00."
- Title: trimmed. An empty title keeps the old one.
- Category and payment method: matched by ID in the expense's (target) account, otherwise by name (QuickLog.category(id:name:in:)). When the target account has no label of that name, the intent asks: "Business has no “Travel” category. Which category?" (the list is that account's categories plus None).
- Date: the supplied day at the original time of day. It counts as a change only when the calendar day differs in preferences.calendar.
- Account: the expense moves to the chosen account, keeping its ID and createdAt. Its category and payment method are remapped by name. Any label with no match is cleared, and the question ends with "Business has no “Groceries” category, so it will have none." (and likewise "... no “Amex” payment method, so it will have none."). There is no Pro gate, the same as Add Expense's account parameter. Pro only limits creating a second account.
- Smart Suggestions never change a label in an edit. shortcutSmartSuggestionsEnabled, shortcutGoBackEnabled and shortcutConfirmsDetails (the reference's Add Expense switches) are not read.
- Nothing actually differs (for example, it is already $15.00): refuses with "“Coffee” already has those details, so nothing was changed."

NOTHING TO CHANGE WAS GIVEN (typical for Siri)
- iOS 26 and later: requestChoice(between:dialog:) with dialog "What would you like to change about “Coffee”?". Options, in order: "Amount", "Title", "Category", "Payment Method", "Date", "Account" (only when there is more than one account), "Another Expense" (only when the expense was defaulted), and .cancel. Then one follow-up:
  - "What should the amount be?" (loops on an invalid amount with the invalidAmount sentence, like Add)
  - "What should it be called?"
  - "Which category?" / "Which payment method?" (names only, then None)
  - "What day was it?"
  - "Which account should it move to?"
  - "Which expense?" (then asks what to change again)
- iOS 18 to 25: requestToContinueInForeground("Open “Coffee” in Keaser to edit it?") { AppIntentRoutes.open(.expense(id)) }, which is the same route Open Expense takes into Edit Expense. This needs the app-only, deprecated ForegroundContinuableIntent conformance used the same way AddExpenseIntent uses it.

CONFIRMATION (the default; always when there is a currency note)
- requestConfirmation(actionName: .custom(acceptLabel: "Save", acceptAlternatives: ["Change", "Yes"], denyLabel: "Cancel", denyAlternatives: ["Keep", "No"], destructive: false), dialog:, content: { ExpenseCardView(card: after, previous: was) }) on iOS 18 and later. It is not the interactive session card: v1 has no in-card lists.
- Dialog sentences, from ExpenseEdit.question (the same text on screen and spoken):
  - amount: "Change “Coffee” from $12.00 to $15.00?"
  - title: "Rename “Cofee” to “Coffee”?"
  - category: "Move “Uber” from Travel to Transportation?"; from none: "File “Uber” under Transportation?"; clear: "Remove the category Travel from “Uber”?"
  - payment method: "Change the payment for “Uber” from Cash to Credit Card?"; from none: "Mark “Uber” as paid with Credit Card?"; clear: "Remove the payment method Cash from “Uber”?"
  - date: "Change the date of “Coffee” from Sep 26, 2026 to Sep 25, 2026?"
  - account: "Move “Coffee” from Personal to Business?"
  - several: "Change “Uber”: amount from $23.40 to $25.00 and category from Travel to Transportation?", with ListFormatter "and" and a serial comma for three or more; a clear reads "category from Travel to none".
- The card is the existing ExpenseCardView with the new values. A changed row shows the old value struck through in keaserSnippetLabel grey before the new value, on one line. The old value gives way first and is dropped at accessibility sizes (ViewThatFits). A changed amount adds one centred footnote line under the big amount with the old amount struck through (+~18 pt at most). VoiceOver reads "Category, Transportation, was Travel". Monochrome only, no new colours.
- Cancel ends the intent with nothing saved (requestConfirmation throws).

RESULT
- After a confirmation: dialog only, as Delete does. ExpenseEdit.doneSentence gives:
  - "Changed “Coffee” to $15.00."
  - "Renamed “Cofee” to “Coffee”."
  - "Moved “Uber” to Transportation."
  - "Removed the category from “Uber”."
  - "“Uber” is now paid with Credit Card."
  - "Removed the payment method from “Uber”."
  - "Moved “Coffee” to Sep 25, 2026."
  - "Moved “Coffee” to Business."
  - "Saved 3 changes to “Uber”."
- With Confirm Changes off: dialog "Successfully updated expense" (the reference's "Successfully added expense" voice) over ExpenseCardView of the result. When voice-only (iOS 27 systemContext.isVoiceOnly), it says doneSentence and shows no card.
- It always returns the updated ExpenseEntity (ReturnsValue), so shortcuts can chain it, for example into Open Expense.

SAFETY, UNDO, SIDE EFFECTS
- authenticationPolicy = .requiresLocalDeviceAuthentication, the same as Delete, Open, Search and Get Spending (founder rule: spending data and destructive changes need an unlocked iPhone). The app does not come to the front.
- It reloads the store before asking and again before saving (IntentSupport.freshStore), and edits whatever is there then. If the expense was changed in between, the plan is recomputed from the latest data.
- iOS 26 and later: UndoableIntent. Undo action name "Edit Expense" reverts to the old values and the old account, only while the expense is still exactly as this edit left it (updatedAt equals the edit's stamp). Per Apple's docs this works from the app's interface, so in practice only when it ran with Keaser open. Running Edit Expense again is the undo everywhere else.
- After saving, the shared catch-up runs: WidgetCenter.reloadAllTimelines, WeeklySummaryScheduler.refreshNow, SpotlightIndexer.flush. The SpotlightPlan fingerprint already covers title, amount, date, labels and account, so an edit re-indexes that one item, and a move re-indexes it under the new account name.
- No donation (edits are not predictable).
- If Keaser's Edit Expense sheet is open on the same expense, it closes when its expense leaves its account or is deleted underneath it (new guard). Otherwise its Save would bring the old values back, or put a moved expense into two accounts.

**APIs** (verify again before use)

- IntentParameter.valueState -> IntentParameter<Value>.ValueState { case unset; case set(Value) } (Equatable when Value is Equatable). For an optional parameter, .set(nil) means explicitly cleared, per the WWDC26-344 transcript: ".set with a nil value means it's explicitly cleared. .unset means the parameter isn't part of the request." (iOS 18.2+. Wrap reads in if #available(iOS 18.2, *); on 18.0 and 18.1, nil means keep; AppIntents.swiftinterface:4351-4363; developer.apple.com/videos/play/wwdc2026/344/)
- protocol UndoableIntent: SystemIntent {} with extension `@MainActor var undoManager: UndoManager?`. SystemIntent has no requirements, so a plain AppIntent can adopt it (DeleteExpenseIntent already does, through DeleteIntent) (iOS 26+ (anyAppleOS 26.0). Conform in an @available(iOS 26.0, *) extension; AppIntents.swiftinterface:3707-3715, 302-304; Apple doc: register undoable actions 'from your app's interface')
- static var authenticationPolicy: IntentAuthenticationPolicy (requirement) = .requiresLocalDeviceAuthentication (iOS 16+; AppIntents.swiftinterface:3108, 3167-3170)
- requestConfirmation(conditions:actionName:dialog:showDialogAsPrompt:content:) with a SwiftUI card; the dialog-only form requestConfirmation(conditions:actionName:dialog:) for voice (iOS 18+; _AppIntents_SwiftUI.swiftinterface:63-66; AppIntents.swiftinterface:3217-3220)
- ConfirmationActionName.custom(acceptLabel:acceptAlternatives:denyLabel:denyAlternatives:destructive:). There is no built-in .save or .update name; .set exists but reads wrong (iOS 16+; AppIntents.swiftinterface:3391-3491)
- requestChoice(between: [IntentChoiceOption], dialog:) -> IntentChoiceOption; IntentChoiceOption(title:style:), .cancel (Equatable, so the chosen option maps back by index) (iOS 26+ (anyAppleOS 26.0); AppIntents.swiftinterface:3177-3190)
- $param.requestValue(_:) and $param.requestDisambiguation(among:dialog:) for the follow-up question and label lists (all such parameters stay in parameterSummary) (iOS 16+; AppIntents.swiftinterface:4365-4370; developer.apple.com/forums/thread/762188 (requestValue on a parameter outside the summary fails on iOS 18))
- ForegroundContinuableIntent.requestToContinueInForeground(_:continuation:), for the iOS 18 to 25 fallback when nothing to change was given. App-only; deprecated in 26 in favour of supportedModes (iOS 16.4 to 25 (iOSApplicationExtension unavailable); AppIntents.swiftinterface:3505-3530)
- DynamicOptionsProvider { results(); defaultResult() } plus @Parameter(title:description:default:requestValueDialog:requestDisambiguationDialog:inputConnectionBehavior:optionsProvider:) for AppEntity parameters (the category and payment lists with None) (iOS 16+ protocol; the entity init shown is iOS 18+; AppIntents.swiftinterface:3905-3915, 575-581)
- ParameterSummary When(\.$expense, .hasNoValue) { ... } otherwise: { ... }, if the summary should read "Edit the last expense added" when Expense is empty (optional polish) (iOS 16+; AppIntents.swiftinterface:4700-4702, 4725-4728)
- IntentResult.result(value:dialog:view:), which erases the view into _SnippetViewContainer (EmptyView and ExpenseCardView returns share one type, as Add Expense already relies on) (iOS 16+; _AppIntents_SwiftUI.swiftinterface:112)
- IntentSystemContext.isVoiceOnly via systemContext (already wrapped as AddExpenseIntent.isVoiceOnly) (iOS 27+ (earlier returns false); AppIntents.swiftinterface:5042-5051)
- AppShortcutPhrase interpolation of \(\.$category). Build-time rule: phrase parameters must be AppEntity or AppEnum, one per phrase. AppShortcutsProvider.updateAppShortcutParameters() must run when the category names change. 10 App Shortcuts per app (iOS 16+; AppIntents.swiftinterface:203-211, 10733-10737; developer.apple.com/forums/thread/770037; developer.apple.com/forums/thread/710816)
- AppIntentsTesting: IntentDefinitions(bundleIdentifier:), intents["EditExpenseIntent"].makeIntent(...) (dynamicallyCall with optional values, so explicit nil can be probed), AnyAppIntent.run(), AppEntityDefinition.makeReference(identifier:) for the None sentinel, entities(identifiers:), spotlightQuery(_:) (iOS 27 test runner only; Developer/Library/Frameworks/AppIntentsTesting.framework/.../arm64e-apple-ios.swiftinterface:114, 155, 182, 219, 271, 284)
- No finance, expense or update schema exists; the only system schemas are .system.search, .searchInApp and .open. So EditExpenseIntent is a plain AppIntent, not @AppIntent(schema:) (n/a; AppIntents.swiftinterface:13754-13796 (schema list), earlier research journal)

**Files**

- NEW Packages/KeaserKit/Sources/KeaserKit/Platform/ExpenseEdit.swift: ExpenseChanges (title/amount/day/accountID as optional replacements; category and payment as .keep/.clear/.set(id:name:)), ExpenseEdit.Plan (.gone, .needsLabel(field, name, accountName), .unchanged(title), .edit(ExpenseEdit)), ExpenseEdit (before: ExpenseDeletion.Item, after: Expense, target account id and name, changed: [Detail] in card order, notes, question(currencyCode:locale:timeZone:), doneSentence(...), card(...) -> ShortcutCard, previousValues(...) -> [Detail: String]), static noneID; extension KeaserStore { apply(_:now:) -> Bool; revert(_:appliedAt:) -> Bool }
- NEW Packages/KeaserKit/Tests/KeaserKitTests/PlatformEditTests.swift
- Packages/KeaserKit/Sources/KeaserKit/Store/KeaserStore.swift: moveExpense(_:from:to:now:) (one persist, announces .expenseDeleted then .expenseSaved); saveExpense refuses an ID that already lives in another account (no duplicates)
- Packages/KeaserKit/Tests/KeaserKitTests/StoreSafetyTests.swift: move and duplicate-guard cases, including a failing save
- Packages/KeaserKit/Sources/KeaserKit/Platform/EntityCatalog.swift: lastAdded(in:) -> ExpenseSummary? (max createdAt across accounts)
- Packages/KeaserKit/Sources/KeaserKit/Platform/ShortcutFlow.swift: ShortcutCard.otherCurrencyNote gains `verb: String = "added"` (Edit passes "saved"), existing tests unchanged
- NEW (or in SpotlightPlan.swift) Packages/KeaserKit/Sources/KeaserKit/Platform/ShortcutPhrases.swift: fingerprint(database) of account names + the selected account's category names, so App Shortcut parameters are refreshed when they change
- NEW Keaser/Intents/EditExpenseIntent.swift: EditExpenseIntent, EditCategoryOptions/EditPaymentMethodOptions (DynamicOptionsProvider), the valueState reader, the choice flow, confirmation, the iOS 26 UndoableIntent extension, IntentSupport.edit/revert, and the iOS 18 to 25 ForegroundContinuableIntent conformance (@available(iOSApplicationExtension, unavailable), deprecated 26)
- Keaser/Intents/IntentSupport.swift: shared `catchUp(after:)` (moved from DeleteExpenseIntent.swift) used by save, delete and edit
- Keaser/Intents/DeleteExpenseIntent.swift: use the shared catch-up; move `gone(count:)` into IntentSupport for reuse
- KeaserWidgets/Shared/ExpenseEntities.swift: CategoryEntity.noCategory and PaymentMethodEntity.noPaymentMethod ("None", ExpenseEdit.noneID), resolved by entities(for:) as goBack is; not in suggestedEntities, so Add Expense's picker is unchanged
- Keaser/Intents/AddExpenseFlow.swift: makeFlow treats a noneID label as unset (defensive)
- Keaser/Intents/ExpenseCard.swift: ExpenseCardView gains `previous: [ExpenseEdit.Detail: String] = [:]` (struck-through old values, the amount footnote line, VoiceOver "was")
- Keaser/Intents/KeaserShortcuts.swift: 8th AppShortcut (Edit Expense, pencil) with the five phrases
- Keaser/Intents/SpotlightIndexer.swift (or a small observer in Keaser/Intents/): call KeaserShortcuts.updateAppShortcutParameters() when the ShortcutPhrases fingerprint changes, not only when accounts do
- Keaser/Features/ExpenseEditor/ExpenseEditorView.swift: dismiss when `original` is no longer in `accountID` (moved or deleted by an intent)
- Keaser/Intents/SnippetPreview.swift: kinds editConfirm (Uber, $23.40 to $25.00, Travel to Transportation) and editResult
- scripts/shots/shortcuts.txt: edit-confirm, edit-confirm-long, edit-confirm-ax, edit-result
- NEW KeaserIntentTests/EditExpenseTests.swift
- AGENTS.md: Shared names (EditExpenseIntent, title "Edit Expense"), the -KeaserSnippet row (editConfirm, editResult), the shortcuts area file list
- README.md: Siri and Spotlight bullet ("...search, edit and delete expenses..."); test badge count
- Packages/KeaserKit/Sources/KeaserKit/Settings/ReleaseHistory.swift: a highlight in the next release (optional)

**Steps**

1. 0. Wait for the founder's device test and answer the device questions. Decide: 'last' means last added (recommended), and whether the account move ships in v1 (droppable, saves ~3 h).
2. 1. KeaserKit: add EntityCatalog.lastAdded(in:) and ExpenseEdit.swift (ExpenseChanges, Plan, ExpenseEdit with sentences, card, previous values, notes and noneID). Build the plan against a Database plus preferences.calendar so it stays pure. Label matching goes through QuickLog.category(id:name:in:) and QuickLog.paymentMethod(id:name:in:); dates reuse ExpenseDeletion.dayText.
3. 2. KeaserStore: moveExpense(_:from:to:now:) that mutates both accounts and persists once, announcing .expenseDeleted then .expenseSaved (Spotlight, widgets and the summary observers stay correct). Add the saveExpense guard against an ID living in another account. Add apply/revert in ExpenseEdit.swift, following ExpenseDeletion's put-back-on-failure pattern: on a failed write, memory returns to the original and the call returns false.
4. 3. Tests: write PlatformEditTests and the StoreSafetyTests additions, then run ./scripts/test.sh.
5. 4. ShortcutCard.otherCurrencyNote(verb:) with the default "added". The existing ShortcutFlowTests must stay green.
6. 5. IntentSupport: move catchUpAfterChange into IntentSupport.catchUp(after:) and use it from save, delete and edit. Move Delete's gone(count:) refusal into IntentSupport.
7. 6. ExpenseEntities.swift: add the None sentinels, resolvable by ID; AddExpense's makeFlow ignores them.
8. 7. EditExpenseIntent.swift: parameters, summary and .requiresLocalDeviceAuthentication. Then perform():
   a. freshStore.
   b. Resolve the expense: the given one, or lastAdded. Refuse when there is none or it is gone.
   c. Read the changes via valueState (18.2+) or nil (older).
   d. If no change was given: requestChoice on 26+ and ask the one follow-up; on 18 to 25, requestToContinueInForeground into AppIntentRoutes.open(.expense).
   e. Plan: on .needsLabel, ask the disambiguation and re-plan; on .unchanged, refuse.
   f. Confirm when confirmsChanges is on or there is a currency note (voice-only uses the dialog-only form).
   g. Re-read the store and re-plan from the latest data.
   h. apply; if it fails, throw saveFailed.
   i. catchUp, then registerUndo on 26+.
   j. Return ExpenseEntity with the doneSentence dialog, or "Successfully updated expense" with the card.
9. 8. ExpenseCard.swift: render `previous` (struck-through old value leading, new value trailing, ViewThatFits drops the old value at accessibility sizes; the amount footnote line) and the VoiceOver value "<new>, was <old>".
10. 9. KeaserShortcuts: add the Edit Expense App Shortcut (8 of 10). Add the ShortcutPhrases fingerprint and call updateAppShortcutParameters() when it changes (category renames, adds and deletes in the selected account, and selecting another account).
11. 10. ExpenseEditorView: when the store no longer holds `original` in `accountID` (after an intent moved or deleted it), dismiss without saving. Consider the same check on scenePhase .active.
12. 11. SnippetPreview editConfirm/editResult; shots in scripts/shots/shortcuts.txt; ./scripts/screenshots.sh shortcuts in light and dark (APPEARANCE=light OUT=screenshots/light); check the long and AX variants.
13. 12. KeaserIntentTests/EditExpenseTests.swift on the local iOS 27 simulator runtime; ./scripts/build.sh for the gating (valueState 18.2, UndoableIntent 26, requestChoice 26, ForegroundContinuableIntent deprecation).
14. 13. Docs: AGENTS.md (Shared names, launch args, the shortcuts area), README bullet and test badge.
15. 14. Device pass on the founder's iPhone (see the device questions):
   - Siri phrases, locked and unlocked
   - voice-only
   - Undo with Keaser open
   - the Spotlight result after a rename
   - the widget total after an amount change
   - the stale editor sheet closing

**Tests**

- KeaserKit (Swift Testing, ./scripts/test.sh), PlatformEditTests: lastAdded picks the latest createdAt across accounts, not the newest date (a backdated expense logged just now wins); nil for an empty database.
- Amount change is rounded to the currency digits (JPY 0 digits, USD 2); the same amount after rounding gives .unchanged; zero or less is rejected before planning.
- Title change trims; an empty or whitespace title keeps the old one; renaming only changes letter case still counts as a change.
- Category by ID in the same account; by name when the ID belongs to another account; an unknown name in the target account gives .needsLabel(.category, "Travel", "Business"); noneID and .clear remove it; clearing an already empty category gives .unchanged.
- Payment method: the same four cases as category.
- Date: the supplied day keeps the original time of day; the same calendar day (New York time zone) gives .unchanged.
- Account move: keeps the ID and createdAt, remaps labels by name, clears unmatched ones with the exact note sentences; moving to the same account gives .unchanged.
- question(): the exact sentence for each single-field case including from-none and clear variants, the two-change and three-change sentences (en_US, curly quotes), and the currency note prefix; doneSentence for each case and "Saved 3 changes to ...".
- previousValues/card: only changed rows carry an old value; the card shows the new values in ShortcutCard formatting.
- Store apply: one write, updatedAt = now, no duplicate after a move, observers receive expenseDeleted then expenseSaved; with a failing DatabaseFile (the StoreSafetyTests fixture) it returns false and memory equals the original.
- Store revert: restores the old values and account exactly (updatedAt back to the original); skipped when the expense changed since (a different updatedAt), was deleted, or its original account was deleted.
- saveExpense guard: saving an expense whose ID lives in another account leaves one copy only.
- ShortcutCard.otherCurrencyNote(verb: "saved") sentence; the existing "added" tests unchanged.
- ShortcutPhrases.fingerprint changes on a category rename in the selected account and on selecting another account, but not on expense changes or on renaming another account's categories.
- AppIntentsTesting (KeaserIntentTests/EditExpenseTests, iOS 27 simulator; confirmations are accepted by the harness, as DeleteExpenseTests already relies on): testChangesTheAmount (add "Coffee" 12 to Business, edit amount 15 USD, spent("today") goes from 12 to 15, and the returned entity's amount is 15).
- testUnsetExpenseEditsTheLastAdded (add an older-dated expense last; editing with no expense changes that one).
- testMovesToAnotherCategoryByName (category "Transportation" string-resolved; categoryName on the fetched entity).
- testMovesToAnotherAccount (Business to Personal; spent per account; labels kept by name).
- testNoneClearsTheCategory (categories.makeReference(identifier: noneID)).
- Probe: makeIntent(expense:, category: nil) explicitly vs omitted. Record whether the harness sends .set(nil); expect a clear if it does.
- testNothingChangedIsRefused (the same amount; the message contains "already has those details").
- testGoneExpenseIsRefused (delete, then edit; "no longer in Keaser" and the EntityNotFound kind).
- testZeroAmountIsRefused.
- testSpotlightFindsTheNewTitle (searchesSpotlight: the renamed title is found and the old one is gone within spotlightChangeLimit).
- testTheReturnedExpenseCanBePassedOn (chained into OpenExpenseIntent).
- Screenshots (./scripts/screenshots.sh shortcuts): edit-confirm, edit-confirm-long (-KeaserSnippetLong 1), edit-confirm-ax (AccessibilityL: old values dropped, one line per row), edit-result, all in light and dark.

**Risks**

- Siri cannot hear an amount in an App Shortcut phrase: phrase parameters must be AppEntity or AppEnum, one per phrase. On iOS 18 to 26, "Change my last expense to 15 dollars" is really "Change my last expense in Keaser", then "Amount", then "15 dollars", then Save (4 turns). Whether iOS 27 Siri fills non-schema parameters by itself is unverified; only third-party articles claim it does.
- valueState .set(nil) is documented for Siri schema intents (WWDC26-344). Whether Shortcuts or the new Siri ever sends .set(nil) to a plain AppIntent is unverified, so the None sentinels are the dependable way to clear. The sentinels have to be kept out of Add Expense's suggestions and treated as unset there.
- Parameters outside parameterSummary cannot be asked for on iOS 18 (forum thread 762188), so the 'what to change' question uses requestChoice (26+). On iOS 18 to 25 it falls back to opening the expense in Keaser, which needs the deprecated, app-only ForegroundContinuableIntent conformance. That brings a deprecation warning on the 27 SDK (the same as AddExpenseIntent today).
- Stale in-app editor: Keaser's Edit Expense sheet ignores outside changes today, so Save after a Siri edit restores the old values. After a Siri account move it would put the expense into two accounts. This already affects Delete (a deleted expense comes back). The store guard plus the editor dismissal must ship with this feature.
- Undo only helps when the intent ran with Keaser open (Apple: undo 'from your app's interface'). From Siri over another app there is no undo, so the confirmation is the safety net. That is why Confirm Changes defaults to on and the App Shortcut never turns it off.
- 'Last expense' ambiguity: last added (createdAt) vs newest date vs selected account only. A voice-only run hears only the title in the question, and two expenses with the same title in different accounts could be confused. Consider naming the account in voice-only questions when there is more than one account.
- Account move complexity: labels are per account, so a move can silently drop a category or payment method (only the note says so). It also changes both accounts' totals and widgets. This is droppable from v1 (about 3 h) if the founder does not need it.
- The App Shortcut budget becomes 8 of 10. The approved 'log my usual coffee' feature may want one more, leaving 1.
- The category-parameterized phrase depends on updateAppShortcutParameters(). Today it only runs when account names change, so the new fingerprint trigger is required or Siri keeps stale category names.
- iOS 27 Siri may drop dialogs and snippets. The question sentence must stand alone without the card, which is why every change is spelled out in the sentence.
- AppIntentsTesting cannot drive requestChoice, disambiguation or undo. Those paths are verified on device only, and the iOS 18.0 to 18.1 and 18 to 25 fallbacks can only be compile-checked (the only local simulator runtime is iOS 27.0).
- Stricter than Add Expense: .requiresLocalDeviceAuthentication means CarPlay and locked-screen Siri edits ask to unlock first. This is intended by the founder rule but may feel slower than adding.

**Value**

Moderate value for a moderate cost (about 20 h, or about 17 h without the account move). Most edits in an expense tracker fix the thing just logged: a Siri mishearing, a Wallet automation filing a transaction under the wrong category, or the tip added later. "Change my last expense" and "Move my last expense to Transportation" cover that without opening the app, and the Shortcuts action lets power users recategorise in automations. It matters less than Add Expense: users edit far less often than they log. On iOS 18 to 26 the voice flow is a multi-turn conversation because phrases cannot carry an amount, so the feature only feels great if iOS 27 Siri fills parameters by itself (device question 1). The bundled stale-editor fix is worth doing regardless, because it already affects Delete. Recommendation: build it after the device test, keep v1 to a static confirmation card (no interactive in-card lists), and drop the account move if the founder does not ask for it.

## 4. Visual Intelligence search

Someone uses Visual Intelligence on a shop sign, a receipt or a screenshot (an order email, say). Keaser then shows their past expenses at that place, newest first, and tapping one opens it in Edit Expense. The system's "More results" button opens Keaser's Search with the place's name already typed in. This is search only, because iOS 27 still gives third-party apps no way to take the image and log it. The picture is read on the iPhone and never kept, and Keaser shows nothing while the phone is locked.

**Behaviour**

WHERE IT APPEARS
- iOS 26: the Visual Intelligence camera (hold Camera Control, the Action button or the Control Center control, then tap Search) and screenshot Image Search.
- iOS 27: Visual Intelligence moved into the Camera app as "Siri Mode" (per MacRumors' iOS 27 guide). It still searches third-party apps from there and from screenshots.
- Keaser is listed among the app results only when it returns at least one match. If nothing matches it returns [] and does not appear. That is the only way Keaser avoids adding noise.
- Nothing on iOS 18 to 25: every new type is @available(iOS 26.0, *).
- The app is iPhone only (TARGETED_DEVICE_FAMILY "1"), so the iPad and Mac Visual Intelligence support that iOS 27 adds does not apply.

WHAT IT MATCHES (pure logic in KeaserKit VisualSearch)
Apple's documentation says labels are "general, high-level terms in the en_US locale", for example "tower" or "building", and "won't provide the building's actual name". Merchant names therefore come only from reading the text in pixelBuffer on device with Vision, through the reader the receipt scanner already uses. Each text line is compared with the titles of expenses in every account. Before comparing, titles and lines are folded with ExpenseQuery.normalized, and punctuation and repeated spaces are collapsed.
1. A line equal to a title is the strongest match.
2. A title found as whole words inside a line: "BLUE BOTTLE COFFEE #12" finds "Blue Bottle Coffee", and also "Coffee".
3. A line of 5 or more letters found as whole words inside a title: a sign reading "BLUE BOTTLE" finds "Blue Bottle Coffee".
4. When the text reads as a receipt, the merchant that ReceiptParser.draft picks from the top lines counts double.
5. One-word titles ("Lunch", "Gas", "Uber") only match a line of 3 words or fewer (a sign or a heading). They never match a word in the middle of a sentence in a screenshot.
6. Never matched:
   - titles shorter than 3 letters;
   - lines that are prices, dates, phone numbers or addresses;
   - receipt boilerplate: Total, Subtotal, Tax, Change, Cash, Visa, Mastercard, Amex, Apple Pay, Thank you, Receipt, Order.
7. Labels are used only when the text found nothing. A label equal to a word of a one- or two-word title matches it: label "coffee" finds "Coffee". Labels "tower" and "building" find nothing.

RESULTS
- Up to 10 ExpenseEntity values: first the newest expense of each matched name (best name first), then more of the best name, newest first.
- Each result uses ExpenseEntity's existing display representation, so there is nothing new to design:
  - title: the expense title, e.g. Blue Bottle Coffee;
  - subtitle: "$5.20 · Sep 26, 2026" (Home's row format, in preferences.currencyCode);
  - image: the category's SF Symbol, monochrome in keeping with Keaser;
  - type name: "Expense" / "N expenses".
- Results are computed live from DatabaseFile.shared.load(), so a deleted expense never appears.

TAP A RESULT
The existing OpenExpenseIntent runs. It asks for Face ID or the passcode if needed (requiresLocalDeviceAuthentication), then Keaser selects the expense's account and shows the expense in Edit Expense (route .expense(id)), exactly as for a Spotlight result.

MORE RESULTS
The system's "More results" button runs the new ShowVisualSearchResultsIntent (schema .visualIntelligence.semanticContentSearch). Keaser opens, selects the account of the best match if it is not already selected, and shows Search with the best name typed in, e.g. Blue Bottle Coffee. Search's existing copy applies: "No Results" / "No expenses match “…”." With no match it opens Search empty: "Search Expenses" / "Enter a search term to find expenses".

LOCKED PHONE
The query returns [] while UIApplication.shared.isProtectedDataAvailable is false. This keeps the existing rule that expenses are "only shown on this iPhone, unlocked". The check is needed because the database file is written with .completeFileProtectionUntilFirstUserAuthentication (DatabaseFile.swift:80). Without it, Camera Control on a locked phone could show titles and amounts.

SPEED
- Before reading, the image is scaled to 1600 px on its long side.
- Vision reading is capped at 1.2 s with the existing Deadline helper. If time runs out, only labels are used.
- If no account has any expense, the query returns [] before reading anything.

SWITCHES AND PRO
- Free, like Spotlight, since it searches the person's own data. No Settings row.
- No interaction with Smart Suggestions, the three Shortcut switches, Start Week On or the Pro gates.
- Titles logged by the Wallet automation are exactly the merchant names it matches.
- Search via "More results" is per account (as SearchExpensesIntent already is). That is why it first selects the best match's account.

COPY
- Privacy policy (Keaser/Resources/Legal/privacy.md), a new section after "## Receipts":
  "## Visual Intelligence"
  "When you search what you see with Visual Intelligence, iOS can ask Keaser for matching expenses. Keaser reads the text in the picture on your iPhone to find past expenses with the same name, then lets the image go: it is never saved or sent anywhere. Keaser shows matches only while your iPhone is unlocked."
- The "More results" intent:
  - title: "Show Matching Expenses";
  - description: "Opens Keaser's search with the expenses that match what Visual Intelligence sees.";
  - isDiscoverable = false if the schema macro allows it, because Shortcuts cannot supply its parameter.
- Optional What's New line, only if ReleaseHistory is Keaser's own rather than the reference's (confirm first): "Visual Intelligence: search a shop sign, a receipt or a screenshot to see what you spent there."
- No camera usage string: the system owns the camera.

NOT IN V1 (considered)
- A "New expense from this receipt" result. A second result type would open New Expense filled from a ReceiptDraft read from the pixel buffer. The public API allows it through an OpenIntent on that type. But it:
  - duplicates the in-app scanner and photo picker;
  - needs @UnionValue, whose AppUnionValue protocol is anyAppleOS 27, or a combined entity;
  - stretches the "matching content" purpose of Visual Intelligence.
  About 4 more hours; decide after device testing.
- A per-merchant summary result ("12 expenses · $64.20"). This needs a new entity and OpenIntent, about 2.5 more hours, and is only worth it if 10 near-identical cards look poor on device.

**APIs** (verify again before use)

- VisualIntelligence.SemanticContentDescriptor { public let labels: [String]; public var pixelBuffer: CVReadOnlyPixelBuffer? { get } } (Sendable, no public initializer) (iOS 26.0, macOS 27.0, macCatalyst 27.0; iPhoneOS27.0.sdk VisualIntelligence.framework/Modules/VisualIntelligence.swiftmodule/arm64e-apple-ios.swiftinterface:35-41)
- SemanticContentDescriptor: AppIntents._SystemIntentValue (persistentIdentifier, typeDisplayRepresentation, displayRepresentation) (iOS 26.0; VisualIntelligence.swiftinterface:11-31)
- SemanticContentDescriptor: AppIntentsTypeSupport.IntentValueConvertible (the only iOS 27 addition to the framework; it is what lets AppIntentsTesting pass a descriptor into a value query) (iOS 27.0, macOS 27.0; VisualIntelligence.swiftinterface:32-34)
- SemanticContentDescriptor: Codable (init(from:) / encode(to:)). The only way to build one in tests. The memberwise init(labels:list:pixelBuffer:) and imageFrameResourceID appear only in VisualIntelligence.tbd, not in the swiftinterface, so they are not public. (iOS 26.0; VisualIntelligence.swiftinterface:42-46; VisualIntelligence.framework/VisualIntelligence.tbd (demangled exports))
- Label semantics: general, high-level en_US terms that may change; never translated, never a place's actual name (iOS 26.0; developer.apple.com/documentation/visualintelligence/semanticcontentdescriptor/labels (doc JSON), and 'Integrating your app with visual intelligence')
- protocol IntentValueQuery: PersistentlyIdentifiable, _SupportsAppDependencies, Sendable { associatedtype Input: _IntentValue; associatedtype Result: ResultsCollection = [ResultValue]; init(); func values(for input: Input) async throws -> Result }. Implemented as values(for input: SemanticContentDescriptor) async throws -> [ExpenseEntity] (anyAppleOS 26.0; static allowedExecutionTargets is anyAppleOS 27.0 with a default; AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface:4401-4424)
- Array: ResultsCollection where Element: _IntentValue (so [ExpenseEntity] is a valid Result) (iOS 16.0; AppIntents.swiftinterface:5013-5024)
- Rules: an app may have only one IntentValueQuery taking SemanticContentDescriptor; return several types with @UnionValue; provide an OpenIntent for every returned entity type ('This OpenIntent must exist, otherwise your app won't show up'); keep the list limited (iOS 26.0; developer.apple.com/documentation/visualintelligence/integrating-your-app-with-visual-intelligence; WWDC25 session 275; WWDC26 session 297)
- protocol OpenIntent: SystemIntent { associatedtype Value: AppValue; var target: Value }. Reused: Keaser's OpenExpenseIntent (target: ExpenseEntity, requiresLocalDeviceAuthentication) (iOS 16.0; AppIntents.swiftinterface:10879-10883; Keaser/Intents/OpenIntents.swift:17-40)
- @AppIntent(schema:) macro where T: AppSchemaIntent (iOS 18.0 (the struct using it must also be @available(iOS 26.0, *)); AppIntents.swiftinterface:10943-10944)
- AppSchema .visualIntelligence.semanticContentSearch, which maps to AppSchema.Intent("ShowVisualSearchResultsInAppIntent"). Its parameter is 'var semanticContent: SemanticContentDescriptor'. The deprecated AssistantSchemas copy at :16268-16313 must not be used. (iOS 26.0, macOS 27.0; tvOS/watchOS/visionOS unavailable; AppIntents.swiftinterface:13022-13058; parameter name from WWDC25 275 sample and Apple's integration article)
- AppIntent.supportedModes: IntentModes (.foreground), isDiscoverable, authenticationPolicy (supportedModes anyAppleOS 26.0; isDiscoverable iOS 17.0; AppIntents.swiftinterface:3097-3112, 3250-3262)
- @UnionValue macro (annotated iOS 18) attaches AppUnionValue, which is anyAppleOS 27.0. Not used in v1 because only one result type is returned. (macro iOS 18.0; AppUnionValue anyAppleOS 27.0; AppIntents.swiftinterface:5158-5159, 3716-3720)
- DisplayRepresentation.Image(systemName:isTemplate:) / (data:isTemplate:). ExpenseEntity already uses systemName. (iOS 16.0; AppIntents.swiftinterface:3874-3880; Keaser/Intents/ExpenseEntity.swift:54-60)
- final class CVReadOnlyPixelBuffer: CVPixelBufferRepresentable, Sendable { func withUnsafeBuffer<R>(_ body: (CVPixelBuffer) throws -> sending R) rethrows -> sending R } (iOS 26.0; CoreVideo.framework/Modules/CoreVideo.swiftmodule/arm64e-apple-ios.swiftinterface:566-574)
- VTCreateCGImageFromCVPixelBuffer(_ pixelBuffer: CVPixelBuffer, options: CFDictionary?, imageOut: UnsafeMutablePointer<CGImage?>) -> OSStatus, called inside withUnsafeBuffer as in the WWDC26 297 snippet. CIImage(cvPixelBuffer:) only takes a CVPixelBufferRef (CIImage.h:450), so Apple's article snippet that passes a CVReadOnlyPixelBuffer to it does not compile as written. (iOS 9.0; VideoToolbox.framework/Headers/VTUtilities.h:26-48; CoreImage.framework/Headers/CIImage.h:450)
- CGImage is @unchecked Sendable, so it can leave withUnsafeBuffer's 'sending' closure (iOS SDK 27; CoreGraphics.framework/Modules/CoreGraphics.swiftmodule/arm64e-apple-ios.swiftinterface:567)
- Vision ImageProcessingRequest.perform(on: CGImage | CVPixelBuffer, orientation: CGImagePropertyOrientation? = nil). Reused through ReceiptTextRecognizer.lines(in: CGImage), which takes the RecognizeDocumentsRequest path on iOS 26 and later. (iOS 18.0 (the documents request is iOS 26); Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-ios.swiftinterface:490-504; Packages/KeaserKit/Sources/KeaserIntelligence/ReceiptTextRecognizer.swift:49-69)
- UIApplication.isProtectedDataAvailable (NS_SWIFT_NONISOLATED property; read on the main actor through UIApplication.shared) (iOS 4.0; UIKit.framework/Headers/UIApplication.h:161)
- AppIntentsTesting: IntentDefinitions.valueQueries[typeIdentifier] -> IntentValueQueryDefinition; func values(for input: some IntentValueConvertible) async throws -> ResolvedValueQueryResult { items: DynamicPropertyPathCollection } (iOS 27.0 (test target only; KeaserIntentTests already targets 27.0); Developer/Library/Frameworks/AppIntentsTesting.framework/.../arm64e-apple-ios.swiftinterface:168-189, 226-228)
- NOT USABLE: _ModelDelegationFeatures.visualIntelligence and _ModelDelegationConfiguration.VisualIntelligence (underscored, @_documentation(visibility: internal)). Their direction is also app to system model, not a hand-off of an image to the app. (iOS 27.0 (internal); AppIntents.swiftinterface:2864-2990)
- NOT USABLE: a private visualIntelligence.SaveVisualContentsIntent schema (earlier research found it in the toolchain schema database with visibility 1). Only semanticContentSearch is public. iOS 27's system Visual Intelligence actions write into EventKit, Contacts, HealthKit and Wallet passes, and receipt splitting uses Apple Cash (US only). No path hands a receipt to a third-party app. (iOS 27.0; AppIntents.swiftinterface:13022-13058 (only public VI schema); WWDC26 297; macrumors.com/guide/ios-27-visual-intelligence)
- NOT USED: FoundationModels image Attachment(CGImage | CVPixelBuffer). It could recognise a logo without text, but loading the model takes too long for a query that must answer fast. (iOS 27.0; FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface:2848-2859)
- IGNORE: Xcode's bundled AdditionalDocumentation/Implementing-Visual-Intelligence-in-iOS.md shows a 'VisualIntelligenceSearchIntent' protocol and an 'appLinkURL' entity property. A grep of the iOS 27 AppIntents and VisualIntelligence modules finds neither. (n/a; /Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/Implementing-Visual-Intelligence-in-iOS.md:160-170, 147-149)

**Files**

- NEW Packages/KeaserKit/Sources/KeaserKit/Intelligence/VisualSearch.swift: pure matcher (Foundation only). public enum VisualSearch { static let resultLimit = 10; static func results(lines: [String], labels: [String], in: Database, limit: Int = resultLimit) -> [ExpenseSummary]; static func moreResults(lines:labels:in:) -> (accountID: UUID, text: String)?; internal terms/scoring }. Reuses EntityCatalog.allExpenses, ExpenseQuery.normalized and ReceiptParser.draft (for the merchant).
- NEW Packages/KeaserKit/Tests/KeaserKitTests/IntelligenceVisualSearchTests.swift (Swift Testing)
- CHANGE Packages/KeaserKit/Sources/KeaserIntelligence/ReceiptTextRecognizer.swift: add public static func image(fromPixelBuffer: CVPixelBuffer, maximumPixelSize: Int = 1600) -> CGImage?, using VTCreateCGImageFromCVPixelBuffer and then a CGContext downscale (import VideoToolbox). This compiles for macOS 15 too, so it is testable on the Mac.
- NEW Packages/KeaserKit/Tests/KeaserIntelligenceTests/VisualSearchReadingTests.swift (Vision on the Mac)
- NEW Keaser/Intents/VisualSearch.swift (app only, import VisualIntelligence): @available(iOS 26) struct ExpenseVisualSearchQuery: IntentValueQuery; @available(iOS 26) @AppIntent(schema: .visualIntelligence.semanticContentSearch) struct ShowVisualSearchResultsIntent; @MainActor enum VisualSearchReader (lock check, pixel buffer to lines within Deadline 1.2 s, DEBUG os Logger of labels, pixel size, line count, milliseconds and result count with privacy .private)
- NEW Keaser/Intents/VisualSearchPreview.swift (#if DEBUG): stand-in of the system results sheet listing each result's display representation (symbol, title, subtitle), in the style of SnippetPreview, driven by -KeaserVisualSearch
- CHANGE Keaser/App/DebugLaunch.swift: visualSearch (-KeaserVisualSearch <receipt sample name> | text:<line>|<line> | labels:<a>,<b>) and visualSearchImage (-KeaserVisualSearchImage 1)
- CHANGE Keaser/App/RootView.swift: present VisualSearchPreview when -KeaserVisualSearch is set (beside SnippetPreview at :56)
- CHANGE project.yml: Keaser target dependencies add '- sdk: VisualIntelligence.framework' with 'weak: true' (explicit, so iOS 18 to 25 launches); then run xcodegen generate
- NEW KeaserIntentTests/VisualSearchTests.swift (AppIntentsTesting, iOS 27)
- CHANGE scripts/shots/intents.txt: visual-search-receipt, visual-search-receipt-image, visual-search-sign, visual-search-labels, visual-search-more
- CHANGE Keaser/Resources/Legal/privacy.md: new '## Visual Intelligence' section after '## Receipts'
- CHANGE AGENTS.md: launch-argument rows for -KeaserVisualSearch and -KeaserVisualSearchImage (area intents), and Keaser/Intents/VisualSearch*.swift plus KeaserKit/Intelligence/VisualSearch.swift in 'Where things live'
- OPTIONAL Packages/KeaserKit/Sources/KeaserKit/Settings/ReleaseHistory.swift: What's New line, only if it is Keaser's own history rather than a mirror of the reference's

**Steps**

1. 0. Gate: read the founder's device-test answers first (questions 1-4 below). Stop or descope if the iPhone cannot run Visual Intelligence, if its app results do not show on their iOS version, or if their real titles are generic words rather than merchant names.
2. 1. KeaserKit VisualSearch: term extraction. Fold lines with ExpenseQuery.normalized, collapse punctuation and spaces, and drop prices, dates, phone numbers, addresses, boilerplate and anything under 3 letters. Add ReceiptParser.draft(from:today:prefersMonthFirst:).merchant as a double-weight term when the lines read as a receipt.
3. 2. KeaserKit VisualSearch: scoring over distinct titles from EntityCatalog.allExpenses(in:). Tiers: exact line (3), title as whole words in a line (2), line of 5+ letters as whole words in a title (1.5); one-word titles only against lines of 3 words or fewer; labels (0.5) only when no text tier matched. Output ordering: newest expense of each matched title in score order, then more of the best title, capped at 10. moreResults returns the best title as the newest expense spells it, plus that expense's accountID.
4. 3. Write the KeaserKit tests (list below) and run ./scripts/test.sh.
5. 4. KeaserIntelligence: add ReceiptTextRecognizer.image(fromPixelBuffer:maximumPixelSize:): VTCreateCGImageFromCVPixelBuffer, then draw into a CGContext at most 1600 px on the long side. Test it on the Mac with a CVPixelBuffer made from ReceiptImageRenderer output.
6. 5. App: Keaser/Intents/VisualSearch.swift. In ExpenseVisualSearchQuery.values(for:): (a) return [] unless await MainActor.run { UIApplication.shared.isProtectedDataAvailable }; (b) load DatabaseFile.shared.load() and return [] if no account has any expense; (c) let image = input.pixelBuffer?.withUnsafeBuffer { ReceiptTextRecognizer.image(fromPixelBuffer: $0) }; (d) let lines = await Deadline.value(within: .milliseconds(1200)) { await ReceiptTextRecognizer.lines(in: image) } ?? []; (e) return VisualSearch.results(lines:labels: input.labels, in:).map(ExpenseEntity.init).
7. 6. App: ShowVisualSearchResultsIntent with 'var semanticContent: SemanticContentDescriptor', supportedModes = .foreground, authenticationPolicy = .requiresLocalDeviceAuthentication, and isDiscoverable = false if the macro allows. Its @MainActor perform reads the text again (same reader), runs VisualSearch.moreResults, calls AppEnvironment.store.reloadFromDisk(), calls store.selectAccount(accountID) when it differs from the selected account, then AppIntentRoutes.open(.search(text)). With no match it opens .search("").
8. 7. project.yml: add the weak VisualIntelligence sdk dependency, run xcodegen generate and ./scripts/build.sh, then confirm with 'otool -l' on the built Keaser binary that VisualIntelligence is LC_LOAD_WEAK_DYLIB. FoundationModels currently relies on automatic weak linking and has never been checked on iOS 18; check it in the same pass.
9. 8. DEBUG harness. -KeaserVisualSearch builds lines from ReceiptSamples.named(x).text, from 'text:' or from 'labels:'. With -KeaserVisualSearchImage 1 it renders the sample with ReceiptImageRenderer, wraps it in a CVPixelBuffer and runs the full pixel path. It feeds the in-memory seeded AppEnvironment.store.database (not the file) to VisualSearch.results and shows VisualSearchPreview. Add the shots and screenshot them in light and dark (APPEARANCE=light OUT=screenshots/light).
10. 9. AppIntentsTesting tests (below), run with ./scripts/intents-test.sh KeaserIntentTests/VisualSearchTests.
11. 10. Privacy policy section, AGENTS.md rows, and the optional What's New line after the founder confirms.
12. 11. Device pass on the founder's iPhone. Try a café sign, a printed receipt, a screenshot of an emailed receipt, a random screenshot (which should show no Keaser results), the locked phone (which should show nothing), and More results. Read the DEBUG Logger output for pixel size, orientation, line count and milliseconds. Tune the one-word-title rule and the deadline from real numbers.

**Tests**

- KeaserKit IntelligenceVisualSearchTests: the lines of ReceiptSamples.named("coffee") with a database holding 'Blue Bottle Coffee' x3 and 'Coffee' x2 return the Blue Bottle expenses first, newest first, then Coffee.
- KeaserKit: a line exactly equal to a title outranks a title contained in a longer line.
- KeaserKit: a sign line 'BLUE BOTTLE' finds 'Blue Bottle Coffee' (line inside title), but a 4-letter line 'CAFE' does not find 'Cafe de Flore' through the line-in-title rule.
- KeaserKit: 'CAFÉ DE FLORE' matches 'Cafe de Flore' after case, accent and width folding and punctuation collapsing ('TRADER JOE'S' matches 'Trader Joes').
- KeaserKit: the one-word title 'Lunch' matches the line 'LUNCH' and 'Lunch Menu', but not 'Let's grab lunch after the meeting tomorrow'.
- KeaserKit: boilerplate lines (TOTAL, SUBTOTAL, VISA ****1234, THANK YOU FOR SHOPPING), prices, dates and phone numbers never match, even against expenses titled 'Total' or 'Visa'.
- KeaserKit: titles under 3 letters ('TJ', '7') are never matched.
- KeaserKit: labels ['coffee','cup'] with no lines find the 'Coffee' expenses; ['tower','building'] find nothing; labels are ignored when any text rule matched.
- KeaserKit: at most 10 results; with 3 matched titles the first three results are one per title (diversity), then the best title fills the rest.
- KeaserKit: expenses from every account are searched, and each result keeps its accountID; moreResults returns the newest match's spelling and account.
- KeaserKit: an empty database, or one with accounts but no expenses, returns [] and nil.
- KeaserKit: the demo seed's titles (Coffee, Uber, Gas, Netflix...) match the text lines used by the screenshot arguments, so the shots never come out empty.
- KeaserIntelligence VisualSearchReadingTests (Mac, Vision): the coffee sample rendered with ReceiptImageRenderer, turned into a CVPixelBuffer and read with image(fromPixelBuffer:) then lines(in:), contains 'BLUE BOTTLE COFFEE'. A 4000 px buffer comes back at most 1600 px on its long side. A buffer rotated 90 degrees is recorded as what it reads, to show whether orientation needs handling.
- AppIntentsTesting VisualSearchTests (iOS 27): decode a SemanticContentDescriptor with JSONDecoder from {"labels":["coffee"]}, call definitions.valueQueries["ExpenseVisualSearchQuery"].values(for:) and expect ExpenseEntity items titled 'Coffee' from IntentTestFixture's demo data. The Codable keys are private, so if the decode throws, keep only the registration check and note it.
- AppIntentsTesting: pass the first returned item to definitions.intents["OpenExpenseIntent"].makeIntent(target:).run(), as AddExpenseTests.testTheReturnedExpenseCanBePassedOn does.
- AppIntentsTesting (optional): definitions.intents["ShowVisualSearchResultsIntent"].makeIntent(semanticContent: descriptor).run() leaves Search showing 'Coffee', checked through accessibility only (no taps), matching IntentTestCase's rules.
- Screenshots (scripts/shots/intents.txt, name | args): 'visual-search-receipt | -KeaserSeed demo -KeaserVisualSearch coffee', 'visual-search-receipt-image | -KeaserSeed demo -KeaserVisualSearch coffee -KeaserVisualSearchImage 1', 'visual-search-sign | -KeaserSeed demo -KeaserVisualSearch text:UBER', 'visual-search-labels | -KeaserSeed demo -KeaserVisualSearch labels:coffee,cup', 'visual-search-more | -KeaserSeed demo -KeaserOpenSearch Coffee'.
- Manual (device only, Visual Intelligence cannot run in the simulator): sign, receipt, screenshot, random screenshot showing no Keaser results, locked phone showing nothing, a tap opening Edit Expense after Face ID, More results opening Search in the right account, and the Logger timing under 1.5 s.

**Risks**

- Labels will never name a merchant (Apple doc), so everything depends on Vision reading text in the frame. Logos without text, stylised signs, glare and far-away shots will not match. Only generic titles ('Coffee') can match through labels.
- Cost of running on every search: iOS may call Keaser's query for every visual search anywhere, launching Keaser in the background and spending up to 1.2 s of Vision each time. Mitigations: the empty-database early return, the deadline and the downscale. Measure it with the DEBUG Logger on device.
- Lock screen exposure: Visual Intelligence can start from a locked phone, and the database file is readable after first unlock. The isProtectedDataAvailable guard is required; verify that it really returns nothing while locked.
- Unknown pixel buffer orientation and size: camera frames may arrive rotated. If the logs show that, pass an orientation to Vision or try a second orientation (doubling the time).
- Tests: SemanticContentDescriptor has no public initializer (only Codable), so AppIntentsTesting may not be able to build one, and the pixel path can only be tested through the DEBUG harness and on device.
- The schema intent may reject extra members (supportedModes, isDiscoverable) or require the parameter spelled exactly 'semanticContent'. The macro and the metadata processor reject a wrong shape only at build time.
- Weak linking: VisualIntelligence.framework does not exist before iOS 26, and there is no iOS 18 simulator here. Rely on 'weak: true' plus an otool check; a strong link would crash launch on iOS 18 to 25.
- False positives on screenshots: generic one-word titles ('Gas', 'Lunch') inside ordinary text. The short-line rule limits this but may also miss real signs with extra words; tune it on device.
- Xcode's bundled Visual Intelligence guide names APIs (VisualIntelligenceSearchIntent, appLinkURL) that do not exist, and Apple's article passes a CVReadOnlyPixelBuffer straight to CIImage(cvPixelBuffer:), which only takes a CVPixelBufferRef. Follow the SDK, not those snippets.
- @UnionValue attaches AppUnionValue (anyAppleOS 27) through a macro annotated iOS 18. Any later second result type (receipt draft or merchant summary) must be checked on an iOS 26 target, or be limited to iOS 27.
- Discoverability: people rarely open the app results in Visual Intelligence, and iOS 27 moved it into the Camera app's Siri Mode, where app results may be less prominent. The feature may go unnoticed.
- More results searches one account. It selects the best match's account first, which changes the person's selected account as a side effect, the same as OpenExpenseIntent does today.
- App Review: a 'new expense from receipt' result would stretch the 'matching content' purpose; plain expense search does not.

**Value**

Low value, moderate cost. The public API only lets Keaser answer "which of my expenses match this picture". iOS 27 still has no public way to hand a receipt image to a third-party app, and the internal model-delegation API is not usable. The useful case is narrow: pointing at a café or a receipt to see what you spent there. It happens rarely, needs an Apple Intelligence iPhone, and sits behind the system's own results, where few people look. Logging a receipt, the thing people would actually want, is already covered better by New Expense's scanner and photo picker. Cost is about 11 hours (9 to 14): about 3 h matcher and tests, 1.5 h pixel-buffer reading, 2 h query and More results intent, 1.5 h DEBUG harness and screenshots, 1 h AppIntentsTesting, 0.5 h project, privacy and AGENTS updates, and 2 h of device tuning. Maintenance is small. Recommendation: build it last of the four chosen extras, and only if the device test shows an eligible iPhone, visible app results in the founder's iOS version, and merchant-style titles. Otherwise skip it: a labels-only version (about 5 h) would match only generic words and is not worth shipping. Hold the receipt-draft result and the merchant-summary card until the founder has seen v1 on device.

