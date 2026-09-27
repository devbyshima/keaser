#!/bin/bash
# Measures Keaser's use of the real on-device model (Apple Intelligence) on
# this Mac. Smart Suggestions' categories: rules and history alone, the model
# alone, and what Keaser ships. Receipt scanning: the heuristics alone, the
# model alone and what ships, on the sample receipts' text and on images of
# them read with Vision, plus receipts only the model reads right. Needs
# macOS 26 or later with Apple Intelligence on. Run it after changing
# CategoryPrompt, ReceiptPrompt or the receipt model's guides, the word
# rules, the heuristics or the ranking, and after OS updates (greedy answers
# only hold for one model version).
#
#   ./scripts/eval.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages/KeaserKit"
KEASER_MODEL_EVALS=1 swift test --filter KeaserIntelligenceEvals 2>&1 \
  | grep -vE "^􀟈|^􀄵|^\s+􀄵|^􁁛  Test [a-zA-Z]+\(\) (started|passed)"
