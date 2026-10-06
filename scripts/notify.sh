#!/usr/bin/env bash
# Sourced by weekly.sh / translate.sh. notify "message": logs the message and, when osascript exists (macOS),
# also posts a desktop notification. Never fails the caller.
notify() {
  local msg=$1
  echo "NOTIFY: $msg"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${msg//[\"\\]/ }\" with title \"seo-brain\"" >/dev/null 2>&1 || true
  fi
  return 0
}
# hub_fail_reason EXIT_CODE -> human reason for a scripts/hub.sh failure (1 = 4xx/contract/config, 3 = unreachable)
hub_fail_reason() {
  case $1 in
    3) echo "hub unreachable (5xx or no response after retries)" ;;
    1) if [ -f .env ]; then echo "hub rejected the request (4xx: bad HUB_TOKEN/HUB_URL, or contract major mismatch) — see log"; else echo ".env missing (HUB_URL/HUB_TOKEN not set)"; fi ;;
    *) echo "hub check failed (exit $1)" ;;
  esac
}
