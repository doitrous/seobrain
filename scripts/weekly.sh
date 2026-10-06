#!/usr/bin/env bash
# Entry point for the scheduled Friday run. Logs to runs/<date>/run.log. Safe to re-run: passes --resume per site if that site's state exists.
# One Claude session per site (sequential) so a long week never exhausts a single session's limit; a failing site does not stop the others.
# Exits non-zero (and notifies) on any failure: hub check, any site's claude exit, untrusted workspace.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
. scripts/notify.sh
DATE=$(date +%F); mkdir -p "runs/$DATE"
LOG="runs/$DATE/run.log"
command -v claude >/dev/null || { echo "claude not on PATH" >> "$LOG"; notify "weekly run: claude not on PATH" >> "$LOG" 2>&1; exit 1; }
rc=0
(
  echo "=== seo-brain $(date) ==="
  scripts/hub.sh selftest; src=$?
  if [ "$src" -ne 0 ]; then
    reason=$(hub_fail_reason "$src")
    echo "$reason"; notify "weekly run not started: $reason"; echo "=== exit $src $(date) ==="
    exit "$src"
  fi
  PLAN="runs/$DATE/plan.json"
  scripts/hub.sh plan "$PLAN"; prc=$?
  if [ "$prc" -ne 0 ]; then
    reason=$(hub_fail_reason "$prc")
    echo "$reason"; notify "weekly run not started: plan fetch failed: $reason"; echo "=== exit $prc $(date) ==="
    exit "$prc"
  fi
  # Sites with work this week: neededThisWeek > 0 or forcedTopics, and not paused (site or global; missing = false).
  SLUGS=$(node -e '
    const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(p.publishingPaused===true) process.exit(0);
    for(const e of p.sites||[]){
      if(e.site&&e.site.publishingPaused===true) continue;
      if((e.neededThisWeek||0)>0||(Array.isArray(e.forcedTopics)&&e.forcedTopics.length>0)) console.log(e.site.slug);
    }' "$PLAN") || { notify "weekly run: unreadable plan ($PLAN)"; echo "=== exit 1 $(date) ==="; exit 1; }
  if [ -z "$SLUGS" ]; then echo "no site has work this week (or publishing is paused)"; echo "=== exit 0 $(date) ==="; exit 0; fi
  failed=0
  for slug in $SLUGS; do
    ARGS="/weekly-run --site $slug"; [ -f "runs/$DATE/$slug/state.json" ] && ARGS="$ARGS --resume"
    echo "=== site $slug start $(date) ==="
    claude --model "${SEO_BRAIN_MODEL:-opus}" -p "$ARGS" --output-format text; crc=$?
    echo "=== site $slug exit $crc $(date) ==="
    if [ "$crc" -ne 0 ]; then
      failed=$((failed+1)); [ "$failed" -ne 1 ] || first=$crc
      notify "weekly run: site $slug claude exited $crc (see $LOG)"
    fi
  done
  echo "=== exit ${first:-0} $(date) ==="
  [ "$failed" -eq 0 ] || exit "$first"
) >> "$LOG" 2>&1 || rc=$?
if grep -q 'has not been trusted' "$LOG"; then
  echo "workspace not trusted: run claude interactively here once (README → Setup 4)" >> "$LOG"
  notify "weekly run: workspace not trusted — run claude interactively here once" >> "$LOG" 2>&1
  [ "$rc" -ne 0 ] || rc=1
fi
exit "$rc"
