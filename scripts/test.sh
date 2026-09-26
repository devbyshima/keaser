#!/bin/bash
# Runs the KeaserKit test suite on the Mac. No simulator needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages/KeaserKit"
swift test "$@" 2>&1 | grep -vE "^􀄵|^\s+􀄵" | tail -40
