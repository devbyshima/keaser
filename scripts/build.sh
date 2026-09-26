#!/bin/bash
# Generates the Xcode project and builds the app (and widget extension) for the
# simulator. Prints only errors, warnings from our own sources, and the result.
#
#   ./scripts/build.sh
#   DEST="platform=iOS Simulator,id=<udid>" ./scripts/build.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build

xcodegen generate --quiet || exit 1

DEST="${DEST:-generic/platform=iOS Simulator}"
LOG="$ROOT/.build/build.log"

xcodebuild -project Keaser.xcodeproj -scheme Keaser -configuration Debug \
  -destination "$DEST" -derivedDataPath "$ROOT/.build" \
  -jobs "${JOBS:-4}" build >"$LOG" 2>&1
STATUS=$?

grep -E "^$ROOT/.*(error|warning):" "$LOG" | sort -u
grep -E "^(error|fatal error):" "$LOG" | sort -u
if [ $STATUS -eq 0 ]; then
  echo "BUILD SUCCEEDED"
else
  echo "BUILD FAILED (full log: $LOG)"
fi
exit $STATUS
