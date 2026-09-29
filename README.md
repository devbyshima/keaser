<div align="center">

<img src="docs/app-icon.png" alt="Keaser" width="120">

# Keaser

**A simple, fast expense tracker for iPhone.**

Native iOS · SwiftUI · iOS 18 and later · no third-party packages

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-487%20in%2068%20suites-brightgreen.svg)](Packages/KeaserKit/Tests)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)

</div>

A simple, fast expense tracker for iPhone. Log an expense in a couple of taps,
from the app, a Shortcut, or an Apple Wallet automation; see where the money
went with charts and filters; keep separate accounts; and glance at a
widget. Everything stays on your iPhone.

## Features

- **Expenses**: title, amount, category, payment method and date. Smart
  Suggestions offer past expenses as you type a title and guess a category and
  payment method for new titles; with Apple Intelligence, an on-device model
  helps pick the category. Scan a receipt or pick a photo of one to fill in
  the merchant, total and date, read on device, and keep the photo with the
  expense (or attach one to any expense), on this iPhone only.
- **Accounts**: separate ledgers (Personal, Business), each with its own
  categories and payment methods, fully editable with 40+ icons.
- **Insights**: a spending total and bar chart for Today, This Week, This
  Month, This Year or All Time, filterable by category and payment method, plus
  search. On iOS 27, swipe an expense to edit or delete it.
- **Widgets**: one simple Spending widget in every size (small, medium,
  large and, on iOS 27, extra large portrait on the home screen;
  rectangular, circular and inline on the lock screen), each showing what
  you spent Today, This Week, This Month or This Year the same way ("Spent
  This Month" over the total), for any account.
  Two controls (Control Center, lock screen, Action button): "Add Expense"
  opens Keaser straight on New Expense, and "Scan Receipt" opens it with the
  camera up, to photograph a receipt into one.
- **Shortcuts**: "Add Expense" and "Log Wallet Transaction" App Intents, with
  Siri phrases, for lock screen logging and Apple Wallet automations. Add
  Expense guides you one detail at a time, with Go Back and a confirmation
  card before it saves.
- **Siri and Spotlight**: ask "How Much Did I Spend", open an expense or an
  account, search and delete expenses, and find them in Spotlight, where they
  are indexed by default.
- **Weekly summary**: an optional notification with the week's total.
- **Keaser Pro**: a 7-day pass on first run, then a monthly or yearly
  subscription or a lifetime purchase (StoreKit 2) for widgets, more filters,
  multiple accounts and long-term insights.
- Settings for currency (every ISO currency), first day of the week, and more.
  Light and dark appearance, with Liquid Glass on iOS 26 and later.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    xcodegen generate
    open Keaser.xcodeproj

The app targets iOS 18. From the command line:

    ./scripts/build.sh          # simulator build, prints errors and warnings only
    ./scripts/test.sh           # KeaserKit tests, run on the Mac (no simulator)
    ./scripts/screenshots.sh    # every screen, headless, into screenshots/

To run on a device, select your team in Xcode (the project uses automatic
signing) and keep the app group `group.com.fulltimestudio.keaser` on both the
app and the widget extension.

### Testing purchases

The `Keaser` scheme uses `Keaser/Resources/Keaser.storekit`, so running from
Xcode offers the monthly, yearly and lifetime products locally. Set real
products and prices in App Store Connect before release; the IDs are
`com.fulltimestudio.keaser.pro.monthly`, `com.fulltimestudio.keaser.pro.yearly`
and `com.fulltimestudio.keaser.pro.lifetime`. The paywall's struck-through
"regular" lifetime price is `ProPricing.lifetimeRegularPriceMultiplier`.

## Before shipping

- Fill in `Keaser/App/AppLinks.swift` (support email, feature requests, social
  profiles). Until then, Help & Feedback and Follow Us stay hidden.
- Create the products in App Store Connect and add the privacy policy URL
  there (the in-app policy is `Keaser/Resources/Legal/privacy.md`).
- iCloud sync is built but off, because the free personal team cannot sign
  iCloud. With the paid Apple Developer Program, switch it on as AGENTS.md
  describes under "iCloud sync" (one word in `project.yml`), and deploy the
  CloudKit schema to Production before shipping.

## Layout

- `Packages/KeaserKit` - models, the store, persistence and all pure logic
  (charts, filters, suggestions, Shortcuts matching, Pro rules).
- `Keaser` - the SwiftUI app.
- `KeaserWidgets` - the WidgetKit extension.

See `AGENTS.md` for architecture notes and the debug launch arguments.

## License

Keaser is free and open source. You can use, study, change and share it under
the terms of the [GNU General Public License v3.0](LICENSE): if you distribute
a modified version, it must stay open source under the same license.
