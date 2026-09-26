# Keaser

A simple, fast expense tracker for iPhone. Log an expense in a couple of taps,
from the app, a Shortcut, or an Apple Wallet automation; see where the money
went with charts and filters; keep separate accounts; glance at a widget; and
optionally mirror an account to a Notion database.

## Features

- **Expenses**: title, amount, category, payment method and date. Smart
  Suggestions offer past expenses as you type a title and guess a category and
  payment method for new titles.
- **Accounts**: separate ledgers (Personal, Business), each with its own
  categories and payment methods, fully editable with 40+ icons.
- **Insights**: a spending total and bar chart for Today, This Week, This
  Month, This Year or All Time, filterable by category and payment method, plus
  search.
- **Widgets**: home screen (small, medium) and lock screen (rectangular,
  circular, inline) spending widgets, and an "Add Expense" control.
- **Shortcuts**: "Add Expense" and "Log Wallet Transaction" App Intents, with
  Siri phrases, for lock screen logging and Apple Wallet automations.
- **Weekly summary**: an optional notification with the week's total.
- **Notion sync**: link an account to a Notion database with your own
  internal integration token; changes flow both ways.
- **Keaser Pro**: a 7-day pass on first run, then a yearly subscription or a
  lifetime purchase (StoreKit 2) for widgets, more filters, multiple accounts
  and long-term insights.
- Settings for currency (every ISO currency), first day of the week, and more.
  Dark only, with Liquid Glass on iOS 26 and later.

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
Xcode offers the yearly and lifetime products locally. Set real products and
prices in App Store Connect before release; the IDs are
`com.fulltimestudio.keaser.pro.yearly` and `com.fulltimestudio.keaser.pro.lifetime`.

### Connecting Notion

1. Create an internal integration at notion.so/my-integrations and copy its
   secret.
2. In Notion, open the database to sync, then Connections, and add the
   integration.
3. In Keaser: Add Account, Connect to Notion, paste the secret, pick the
   database (or let Keaser create one), and review the property mapping.

Keaser adds a "Keaser ID" column so it can match rows to expenses. The token
is stored in the Keychain and only ever sent to Notion.

## Before shipping

- Fill in `Keaser/App/AppLinks.swift` (support email, feature requests, social
  profiles). Until then, Help & Feedback and Follow Us stay hidden.
- Create the products in App Store Connect and add the privacy policy URL
  there (the in-app policy is `Keaser/Resources/Legal/privacy.md`).

## Layout

- `Packages/KeaserKit` - models, the store, persistence and all pure logic
  (charts, filters, suggestions, Notion client and sync planner, Pro rules).
- `Keaser` - the SwiftUI app.
- `KeaserWidgets` - the WidgetKit extension.

See `AGENTS.md` for architecture notes and the debug launch arguments.
