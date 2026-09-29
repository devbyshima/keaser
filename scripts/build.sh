#!/bin/bash
# Generates the Xcode project and builds the app (and widget extension) for the
# simulator. Prints only errors, warnings from our own sources, and the result.
#
#   ./scripts/build.sh
#   DEST="platform=iOS Simulator,id=<udid>" ./scripts/build.sh
#   CLOUD=1 ./scripts/build.sh   # the iCloud sync configuration (see below)
#
# CLOUD=1 builds with the CloudSyncSigning template instead of the one
# project.yml names (iCloud entitlements, KEASER_CLOUD, KeaserCloudSync), into
# .build/cloud, to prove that configuration compiles; simulator builds need
# no provisioning profile. The default project is generated again afterwards,
# so the checked-in Info.plist is left as project.yml describes it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build

DEST="${DEST:-generic/platform=iOS Simulator}"
DERIVED="$ROOT/.build"
LOG="$ROOT/.build/build.log"

if [ "${CLOUD:-0}" = "1" ]; then
  sed 's/templates: \[FreeTeamSigning\]/templates: [CloudSyncSigning]/' project.yml >.build/project-cloud.yml
  grep -q 'templates: \[CloudSyncSigning\]' .build/project-cloud.yml || { echo "project.yml names no signing template"; exit 1; }
  xcodegen generate --quiet --spec .build/project-cloud.yml --project-root "$ROOT" --project "$ROOT" || exit 1
  DERIVED="$ROOT/.build/cloud"
  LOG="$ROOT/.build/build-cloud.log"
else
  xcodegen generate --quiet || exit 1
fi

xcodebuild -project Keaser.xcodeproj -scheme Keaser -configuration Debug \
  -destination "$DEST" -derivedDataPath "$DERIVED" \
  -jobs "${JOBS:-4}" build >"$LOG" 2>&1
STATUS=$?

if [ "${CLOUD:-0}" = "1" ]; then
  xcodegen generate --quiet || exit 1
fi

grep -E "^$ROOT/.*(error|warning):" "$LOG" | sort -u
grep -E "^(error|fatal error):" "$LOG" | sort -u
if [ $STATUS -eq 0 ]; then
  echo "BUILD SUCCEEDED"
else
  echo "BUILD FAILED (full log: $LOG)"
fi
exit $STATUS
