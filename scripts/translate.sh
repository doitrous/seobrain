#!/usr/bin/env bash
# Daily localization pass (hub contract 1.17.0). Exits at once — no Claude session — when the hub
# has nothing to localize. Logs to runs/<date>/translate.log.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
DATE=$(date +%F); mkdir -p "runs/$DATE"
Q="runs/$DATE/translate-queue.json"
scripts/hub.sh translate-queue "$Q" >/dev/null 2>&1 || exit 0
n=$(jq '[.jobs[].locales[]?] | length' "$Q" 2>/dev/null || echo 0)
[ "${n:-0}" -gt 0 ] || exit 0
command -v claude >/dev/null || { echo "claude not on PATH" >> "runs/$DATE/translate.log"; exit 1; }
{
  echo "=== translate $(date) — $n versions queued ==="
  claude --model claude-opus-4-8 -p "/weekly-run --translate-only" --output-format text
  echo "=== exit $? $(date) ==="
} >> "runs/$DATE/translate.log" 2>&1
exit 0
