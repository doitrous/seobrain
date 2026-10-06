#!/usr/bin/env bash
# Entry point for the scheduled Friday run. Logs to runs/<date>/run.log. Safe to re-run: passes --resume if today's state exists.
# Exits non-zero (and notifies) on any failure: hub check, claude exit, untrusted workspace.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
. scripts/notify.sh
DATE=$(date +%F); mkdir -p "runs/$DATE"
LOG="runs/$DATE/run.log"
command -v claude >/dev/null || { echo "claude not on PATH" >> "$LOG"; notify "weekly run: claude not on PATH" >> "$LOG" 2>&1; exit 1; }
ARGS="/weekly-run"; [ -f "runs/$DATE/state.json" ] && ARGS="/weekly-run --resume"
rc=0
(
  echo "=== seo-brain $(date) ==="
  scripts/hub.sh selftest; src=$?
  if [ "$src" -ne 0 ]; then
    reason=$(hub_fail_reason "$src")
    echo "$reason"; notify "weekly run not started: $reason"; echo "=== exit $src $(date) ==="
    exit "$src"
  fi
  claude --model "${SEO_BRAIN_MODEL:-opus}" -p "$ARGS" --output-format text; crc=$?
  echo "=== exit $crc $(date) ==="
  [ "$crc" -eq 0 ] || { notify "weekly run: claude exited $crc (see $LOG)"; exit "$crc"; }
) >> "$LOG" 2>&1 || rc=$?
if grep -q 'has not been trusted' "$LOG"; then
  echo "workspace not trusted: run claude interactively here once (README → Setup 4)" >> "$LOG"
  notify "weekly run: workspace not trusted — run claude interactively here once" >> "$LOG" 2>&1
  [ "$rc" -ne 0 ] || rc=1
fi
exit "$rc"
