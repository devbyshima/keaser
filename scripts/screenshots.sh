#!/bin/bash
# Headless screenshots from cold launches. Never drives the simulator GUI:
# every screen is reached through DebugLaunch arguments (see AGENTS.md).
#
# Shots are listed in scripts/shots/<area>.txt, one per line:
#   name | -KeaserSeed demo -KeaserSheet newExpense
# Blank lines and lines starting with # are ignored.
#
#   ./scripts/screenshots.sh            # every area
#   ./scripts/screenshots.sh home       # only scripts/shots/home.txt
#   SIM="Keaser home" ./scripts/screenshots.sh home
#   SETTLE=4 ./scripts/screenshots.sh   # slower machine
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.fulltimestudio.keaser"
SETTLE="${SETTLE:-3}"
OUT="${OUT:-$ROOT/screenshots}"
UDID="$("$ROOT/scripts/sim.sh")"

echo "==> Building"
DEST="platform=iOS Simulator,id=$UDID" "$ROOT/scripts/build.sh" >/dev/null || { "$ROOT/scripts/build.sh"; exit 1; }
APP="$ROOT/.build/Build/Products/Debug-iphonesimulator/Keaser.app"

echo "==> Booting $UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
# A fresh install each run, so no shot inherits state from the previous run.
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT"
FILES=("$ROOT"/scripts/shots/*.txt)
if [ $# -gt 0 ]; then FILES=(); for a in "$@"; do FILES+=("$ROOT/scripts/shots/$a.txt"); done; fi

for file in "${FILES[@]}"; do
  area="$(basename "$file" .txt)"
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "${line// }" || "$line" == \#* ]] && continue
    name="$(echo "${line%%|*}" | xargs)"
    args="$(echo "${line#*|}" | xargs)"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    xcrun simctl launch "$UDID" "$BUNDLE_ID" $args >/dev/null
    sleep "$SETTLE"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$area-$name.png" >/dev/null 2>&1
    echo "  $area-$name.png"
  done <"$file"
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "==> $OUT"
