# Keaser

A simple, fast expense tracker for iPhone. Log an expense in a couple of taps,
from the app, a Shortcut, or an Apple Wallet automation; see where the money
went with charts and filters; keep separate accounts; glance at a widget; and
optionally mirror an account to a Notion database.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    xcodegen generate
    open Keaser.xcodeproj

Or from the command line:

    ./scripts/build.sh      # simulator build
    ./scripts/test.sh       # KeaserKit unit tests (runs on the Mac)

The app targets iOS 18 and adopts Liquid Glass on iOS 26 and later.
