#!/usr/bin/env bash
# Entry point for the scheduled Friday run. Logs to runs/<date>/run.log. Safe to re-run: passes --resume if today's state exists.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
DATE=$(date +%F); mkdir -p "runs/$DATE"
command -v claude >/dev/null || { echo "claude not on PATH" >> "runs/$DATE/run.log"; exit 1; }
ARGS="/weekly-run"; [ -f "runs/$DATE/state.json" ] && ARGS="/weekly-run --resume"
{
  echo "=== seo-brain $(date) ==="
  scripts/hub.sh selftest || { echo "hub unreachable"; echo "=== exit 1 $(date) ==="; exit 1; }
  claude --model claude-opus-4-8 -p "$ARGS" --output-format text
  echo "=== exit $? $(date) ==="
} >> "runs/$DATE/run.log" 2>&1
