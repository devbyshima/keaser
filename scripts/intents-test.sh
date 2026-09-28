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
# -collect-test-diagnostics never: otherwise xcodebuild collects the
# simulator's diagnostics after the run and can wait 600 s for them, even when
# every test passed. The tally below reads only the log.
xcodebuild -project Keaser.xcodeproj -scheme KeaserIntentTests -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$ROOT/.build" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics never \
  ${ONLY[@]+"${ONLY[@]}"} test >"$LOG" 2>&1
STATUS=$?

grep -E "^$ROOT/.*(error|warning):" "$LOG" | sort -u
grep -E "^(error|fatal error):|error: -\[|: error: " "$LOG" | grep -v "^$ROOT" | sort -u

# The tally comes from the test cases themselves, not from xcodebuild's
# suite summaries: after a test exceeds its time allowance the runner
# restarts, and the restarted run reports "Executed 0 tests" and "passed"
# for the suite it skipped.
PASSED="$(grep -cE "^Test Case '.*' passed" "$LOG")"
FAILED="$(grep -cE "^Test Case '.*' failed" "$LOG")"
TIMED_OUT="$(grep -cE "^Test Case '.*' exceeded execution time allowance" "$LOG")"
RESTARTS="$(grep -c "^Restarting after unexpected exit, crash, or test timeout" "$LOG")"
# Tests that started but never passed or failed (killed by a timeout or a
# crash).
UNFINISHED="$(python3 - "$LOG" <<'PY'
import re, sys
started, ended = [], set()
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"Test Case '-\[(\S+) (\S+)\]' (started|passed|failed)", line)
    if not m: continue
    name = f"{m.group(1).split('.')[-1]}.{m.group(2)}"
    if m.group(3) == "started": started.append(name)
    else: ended.add(name)
for name in dict.fromkeys(started):
    if name not in ended: print(name)
PY
)"

grep -E "^Test Case '.*' (passed|failed|skipped)" "$LOG"
grep -E "^Test Case '.*' exceeded execution time allowance" "$LOG" | sed -E "s/ The test may have hung.*//"
if [ -n "$UNFINISHED" ]; then
  echo "Did not finish:"
  echo "$UNFINISHED" | sed 's/^/    /'
fi
sed -n '/^Failing tests:/,/^$/p' "$LOG"
echo "$PASSED passed, $FAILED failed, $TIMED_OUT over the time allowance, $RESTARTS runner restarts"

PROBLEMS=$((FAILED + TIMED_OUT + RESTARTS))
[ -n "$UNFINISHED" ] && PROBLEMS=$((PROBLEMS + 1))
if [ $STATUS -eq 0 ] && [ "$PROBLEMS" -eq 0 ] && [ "$PASSED" -gt 0 ]; then
  echo "TESTS PASSED"
  exit 0
fi
echo "TESTS FAILED (full log: $LOG)"
[ $STATUS -eq 0 ] && STATUS=1
exit $STATUS
