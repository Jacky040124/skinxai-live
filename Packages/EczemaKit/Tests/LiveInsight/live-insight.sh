#!/bin/bash
# Live check of the Insight system prompt + JSON contract through OpenRouter, with a cheap model.
#
#   vault-run Packages/EczemaKit/Tests/LiveInsight/live-insight.sh "$PWD/Packages/EczemaKit" [model]
#
# vault-run substitutes the vaulted OpenRouter key into a private temp copy of this file at run time.
# The key only lives in this process's environment; nothing here prints it (no `set -x`, no echo).
set -euo pipefail
PKG="${1:?usage: vault-run live-insight.sh <absolute path to Packages/EczemaKit> [model]}"
export INSIGHT_LIVE_MODEL="${2:-deepseek/deepseek-v4-flash}"
export OPENROUTER_API_KEY='<agent-vault:botiverse-openrouter-api-key>'
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
cd "$PKG"
swift test --filter LiveInsightTests \
  -Xswiftc -F"$FW" -Xlinker -F"$FW" -Xlinker -rpath -Xlinker "$FW" 2>&1 \
  | grep -v "duplicate -rpath"
