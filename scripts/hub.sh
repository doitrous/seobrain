#!/usr/bin/env bash
# seo-hub API wrapper. Usage: scripts/hub.sh <command> [args]. Needs HUB_URL and HUB_TOKEN (from .env or the environment).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
: "${HUB_URL:?HUB_URL not set}" "${HUB_TOKEN:?HUB_TOKEN not set}"

api() { # api METHOD PATH [JSON_FILE]  -> body on stdout; exit 1 on 4xx or after 3 failures
  local m=$1 p=$2 f=${3:-} out code body i
  for i in 1 2 3; do
    if [ -n "$f" ]; then
      out=$(curl -sS -w $'\n%{http_code}' -X "$m" "$HUB_URL$p" -H "Authorization: Bearer $HUB_TOKEN" -H 'content-type: application/json' --data-binary @"$f" 2>&1) || out=$'\n000'
    else
      out=$(curl -sS -w $'\n%{http_code}' -X "$m" "$HUB_URL$p" -H "Authorization: Bearer $HUB_TOKEN" 2>&1) || out=$'\n000'
    fi
    code=${out##*$'\n'}; body=${out%$'\n'*}
    case $code in
      2*) printf '%s\n' "$body"; return 0 ;;
      4*) printf '%s\n' "$body" >&2; return 1 ;;
    esac
    sleep $((i * 3))
  done
  printf '%s\n' "$body" >&2; return 1
}
jget() { node -pe "JSON.parse(require('fs').readFileSync(0,'utf8'))$1"; } # jget .run.id

case ${1:-} in
  plan)       api GET /api/plan ;;
  run-start)  api POST /api/runs | jget .run.id ;;
  run-finish) f=$(mktemp); node -e 'process.stdout.write(JSON.stringify({summary: JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}))' "$3" > "$f"; api PATCH "/api/runs/$2" "$f"; rm -f "$f" ;;
  create-job) api POST /api/jobs "$2" | jget .job.id ;;
  step)       f=$(mktemp); node -e 'process.stdout.write(JSON.stringify({name: process.argv[1], payload: JSON.parse(require("fs").readFileSync(process.argv[2],"utf8"))}))' "$3" "$4" > "$f"; api POST "/api/jobs/$2/steps" "$f"; rm -f "$f" ;;
  audit)      api POST "/api/jobs/$2/audit" ;;
  article)    api POST "/api/jobs/$2/articles" "$3" ;;
  schedule)   api POST "/api/jobs/$2/schedule" ;;
  jobs)       api GET /api/jobs ;;
  selftest)   api GET /api/plan | jget .weekOf ;;
  *) echo "usage: hub.sh plan|run-start|run-finish ID FILE|create-job FILE|step JOB NAME FILE|audit JOB|article JOB FILE|schedule JOB|jobs|selftest" >&2; exit 2 ;;
esac
