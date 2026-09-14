#!/usr/bin/env bash
# seo-hub API wrapper. Usage: scripts/hub.sh <command> [args]. Needs HUB_URL and HUB_TOKEN (from .env or the environment).
# Exit codes: 1 = client error (4xx) or a major contract mismatch, 3 = hub unreachable.
set -euo pipefail
cd "$(dirname "$0")/.."
# seohub docs/contracts/VERSION major this brain is written against (see docs/contracts/README.md).
# Bump only after reading the new contract docs for breaking changes; a minor/patch bump is additive and safe.
BRAIN_CONTRACT_MAJOR=1
_env_url=${HUB_URL:-} _env_token=${HUB_TOKEN:-}
[ -f .env ] && set -a && . ./.env && set +a
[ -n "$_env_url" ] && HUB_URL=$_env_url
[ -n "$_env_token" ] && HUB_TOKEN=$_env_token
: "${HUB_URL:?HUB_URL not set}" "${HUB_TOKEN:?HUB_TOKEN not set}"
HUB_URL=${HUB_URL%/}

f=""
trap 'rm -f "${f:-}"' EXIT

api() { # api METHOD PATH [JSON_FILE]  -> body on stdout; exit 1 on 4xx, exit 3 after 3 failed attempts (5xx/000)
  local m=$1 p=$2 f=${3:-} out code body i
  for i in 1 2 3; do
    if [ -n "$f" ]; then
      out=$(curl -sS -w $'\n%{http_code}' --connect-timeout 10 --max-time 120 -X "$m" "$HUB_URL$p" -H "Authorization: Bearer $HUB_TOKEN" -H 'content-type: application/json' --data-binary @"$f" 2>&1) || out=$'\n000'
    else
      out=$(curl -sS -w $'\n%{http_code}' --connect-timeout 10 --max-time 120 -X "$m" "$HUB_URL$p" -H "Authorization: Bearer $HUB_TOKEN" 2>&1) || out=$'\n000'
    fi
    code=${out##*$'\n'}; body=${out%$'\n'*}
    case $code in
      2*) printf '%s\n' "$body"; return 0 ;;
      4*) printf 'HTTP %s\n' "$code" >&2; printf '%s\n' "$body" >&2; return 1 ;;
    esac
    [ "$i" -lt 3 ] && sleep $((i * 3))
  done
  printf 'HTTP %s\n' "$code" >&2; printf '%s\n' "$body" >&2; return 3
}
jget() { node -pe "JSON.parse(require('fs').readFileSync(0,'utf8'))$1"; } # jget .run.id

# Fetch the hub's contract version once per run (called from selftest, the run's pre-flight check).
# Same major as BRAIN_CONTRACT_MAJOR: print the version to stderr and continue — a minor/patch bump
# is additive. Different major: abort (set -e propagates this function's exit status).
check_contract_version() {
  local v major
  v=$(api GET /api/contracts/version); v=$(jget .version <<<"$v")
  major=${v%%.*}
  if [ "$major" != "$BRAIN_CONTRACT_MAJOR" ]; then
    echo "hub contract v$v is major v$major; this brain is pinned to v$BRAIN_CONTRACT_MAJOR — aborting, update seobrain for the new contract" >&2
    return 1
  fi
  echo "hub contract v$v (brain pinned to major v$BRAIN_CONTRACT_MAJOR) — continuing" >&2
}

case ${1:-} in
  plan)       api GET /api/plan | tee "${2:-/dev/null}" ;;
  run-start)  out=$(api POST /api/runs); jget .run.id <<<"$out" ;;
  run-finish) f=$(mktemp); node -e 'process.stdout.write(JSON.stringify({summary: JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}))' "$3" > "$f"; api PATCH "/api/runs/$2" "$f" ;;
  create-job) out=$(api POST /api/jobs "$2"); node -pe "JSON.stringify(JSON.parse(require('fs').readFileSync(0,'utf8')).job)" <<<"$out" ;;
  step)       f=$(mktemp); node -e 'process.stdout.write(JSON.stringify({name: process.argv[1], payload: JSON.parse(require("fs").readFileSync(process.argv[2],"utf8"))}))' "$3" "$4" > "$f"; api POST "/api/jobs/$2/steps" "$f" ;;
  audit)      api POST "/api/jobs/$2/audit" | tee "${3:-/dev/null}" ;;
  articles)   api GET "/api/jobs/$2/articles" | tee "${3:-/dev/null}" ;;
  article)    api POST "/api/jobs/$2/articles" "$3" ;;
  schedule)   api POST "/api/jobs/$2/schedule" ;;
  jobs)       api GET /api/jobs ;;
  selftest)   check_contract_version; out=$(api GET /api/plan); jget .weekOf <<<"$out" ;;
  *) echo "usage: hub.sh plan [OUTFILE]|run-start|run-finish ID FILE|create-job FILE|step JOB NAME FILE|audit JOB [OUTFILE]|article JOB FILE|articles JOB [OUTFILE]|schedule JOB|jobs|selftest (exit 1 = client error (4xx) or major contract mismatch, 3 = hub unreachable)" >&2; exit 2 ;;
esac
