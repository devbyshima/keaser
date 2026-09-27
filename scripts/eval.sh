#!/bin/bash
# Measures Smart Suggestions' categories with the real on-device model
# (Apple Intelligence) on this Mac: rules and history alone, the model alone,
# and what Keaser ships. Needs macOS 26 or later with Apple Intelligence on.
# Run it after changing CategoryPrompt, the word rules or the ranking, and
# after OS updates (greedy answers only hold for one model version).
#
#   ./scripts/eval.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages/KeaserKit"
KEASER_MODEL_EVALS=1 swift test --filter KeaserIntelligenceEvals 2>&1 \
  | grep -vE "^􀟈|^􀄵|^\s+􀄵|^􁁛  Test [a-zA-Z]+\(\) (started|passed)"
