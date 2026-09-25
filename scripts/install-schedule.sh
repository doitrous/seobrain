#!/usr/bin/env bash
# Installs (or reinstalls) the Friday 07:00 weekly run and the daily 09:00 localization pass as
# launchd jobs for the current user. Usage: scripts/install-schedule.sh [--uninstall]
set -euo pipefail
case ${1:-} in ""|--uninstall) ;; *) echo "usage: $0 [--uninstall]" >&2; exit 2 ;; esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
for LABEL in com.doitrous.seo-brain com.doitrous.seo-brain-translate; do
  DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  if [ "${1:-}" = "--uninstall" ]; then rm -f "$DEST"; continue; fi
  mkdir -p "$HOME/Library/LaunchAgents" "$REPO/runs"
  sed "s|__REPO__|$REPO|g" "$REPO/scripts/$LABEL.plist" > "$DEST"
  launchctl bootstrap "gui/$(id -u)" "$DEST"
done
[ "${1:-}" = "--uninstall" ] && { echo "uninstalled"; exit 0; }
echo "installed: Friday 07:00 weekly run + daily 09:00 localization pass → $REPO/scripts (logs: runs/<date>/)"
