#!/bin/bash
# Runs the App Intents tests (KeaserIntentTests, AppIntentsTesting) on an
# iOS 27 simulator of their own, headless: every intent and entity query goes
# through the system as Siri and Shortcuts would run it. The tests replace the
# app's data on that simulator (ResetTestDataIntent, Debug builds only), so
# never point SIM at a simulator whose Keaser data you want to keep.
#
#   ./scripts/intents-test.sh
#   ./scripts/intents-test.sh KeaserIntentTests/SpendingTests   # one class
#   SIM="Keaser intents test 2" ./scripts/intents-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build
BUNDLE_ID="com.fulltimestudio.keaser"
LOG="$ROOT/.build/intents-test.log"
export SIM="${SIM:-Keaser intents test}"
UDID="$("$ROOT/scripts/sim.sh")"

xcodegen generate --quiet || exit 1

echo "==> Booting $SIM ($UDID)"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array en-US en >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" defaults write -g AppleLocale en_US >/dev/null 2>&1 || true
# A fresh install, so no test sees data or a Spotlight index from an earlier run.
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

ONLY=()
for a in "$@"; do ONLY+=("-only-testing:$a"); done

echo "==> Testing (log: $LOG)"
xcodebuild -project Keaser.xcodeproj -scheme KeaserIntentTests -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$ROOT/.build" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
  ${ONLY[@]+"${ONLY[@]}"} test >"$LOG" 2>&1
STATUS=$?

grep -E "^$ROOT/.*(error|warning):" "$LOG" | sort -u
grep -E "^(error|fatal error):|error: -\[|: error: " "$LOG" | grep -v "^$ROOT" | sort -u
grep -E "^Test Case .* (passed|failed|skipped)" "$LOG"
grep -E "Executed [0-9]+ tests?" "$LOG" | tail -1
if [ $STATUS -eq 0 ]; then
  echo "TESTS PASSED"
else
  echo "TESTS FAILED (full log: $LOG)"
fi
exit $STATUS
