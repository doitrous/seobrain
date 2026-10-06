#!/usr/bin/env bash
# Daily localization pass (hub contract 1.17.0). Exits 0 at once — no Claude session — when the hub
# has nothing to localize; notifies and exits non-zero on errors. Logs to runs/<date>/translate.log.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
. scripts/notify.sh
DATE=$(date +%F); mkdir -p "runs/$DATE"
LOG="runs/$DATE/translate.log"
Q="runs/$DATE/translate-queue.json"
scripts/hub.sh translate-queue "$Q" >/dev/null 2>"$Q.err"; qrc=$?
if [ "$qrc" -ne 0 ]; then
  reason=$(hub_fail_reason "$qrc")
  { echo "=== translate $(date) — queue fetch failed ==="; cat "$Q.err"; notify "translate pass: $reason"; } >> "$LOG" 2>&1
  exit "$qrc"
fi
n=$(jq '[.jobs[].locales[]?] | length' "$Q" 2>/dev/null) || { notify "translate pass: unreadable translate queue ($Q)" >> "$LOG" 2>&1; exit 1; }
[ "${n:-0}" -gt 0 ] || exit 0
command -v claude >/dev/null || { echo "claude not on PATH" >> "$LOG"; notify "translate pass: claude not on PATH" >> "$LOG" 2>&1; exit 1; }
rc=0
(
  echo "=== translate $(date) — $n versions queued ==="
  claude --model "${SEO_BRAIN_MODEL:-opus}" -p "/weekly-run --translate-only" --output-format text; crc=$?
  echo "=== exit $crc $(date) ==="
  [ "$crc" -eq 0 ] || { notify "translate pass: claude exited $crc (see $LOG)"; exit "$crc"; }
) >> "$LOG" 2>&1 || rc=$?
if grep -q 'has not been trusted' "$LOG"; then
  notify "translate pass: workspace not trusted — run claude interactively here once" >> "$LOG" 2>&1
  [ "$rc" -ne 0 ] || rc=1
fi
exit "$rc"
