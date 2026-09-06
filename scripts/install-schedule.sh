#!/usr/bin/env bash
# Installs (or reinstalls) the Friday 07:00 launchd job for the current user. Usage: scripts/install-schedule.sh [--uninstall]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
LABEL=com.doitrous.seo-brain
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--uninstall" ]; then rm -f "$DEST"; echo "uninstalled"; exit 0; fi
mkdir -p "$HOME/Library/LaunchAgents" "$REPO/runs"
sed "s|__REPO__|$REPO|g" "$REPO/scripts/$LABEL.plist" > "$DEST"
launchctl bootstrap "gui/$(id -u)" "$DEST"
launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|program' | head -3
echo "installed: Friday 07:00 local → $REPO/scripts/weekly.sh (log: runs/<date>/run.log)"
