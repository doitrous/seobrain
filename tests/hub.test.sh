#!/usr/bin/env bash
# Contract test for scripts/hub.sh against tests/mock-hub.js. Run: bash tests/hub.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=3999 node tests/mock-hub.js & MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -s -o /dev/null "http://localhost:3999/api/plan" -H 'Authorization: Bearer tok' && break; sleep 0.2; done
export HUB_URL=http://localhost:3999 HUB_TOKEN=tok
T=$(mktemp -d)
fail() { echo "FAIL: $1"; exit 1; }

[ "$(scripts/hub.sh selftest)" = "2026-08-31" ] || fail selftest
[ "$(scripts/hub.sh run-start)" = "7" ] || fail run-start
echo '{"jobs":3}' > "$T/summary.json"; scripts/hub.sh run-finish 7 "$T/summary.json" | grep -q '"jobs":3' || fail run-finish
echo '{"siteId":1,"topic":{"title":"T","keyword":"k","market":"SA","lang":"en","source":"discovered"}}' > "$T/job.json"
[ "$(scripts/hub.sh create-job "$T/job.json")" = "42" ] || fail create-job
echo '{"facts":[]}' > "$T/research.json"; scripts/hub.sh step 42 research "$T/research.json" | grep -q researched || fail step
scripts/hub.sh audit 42 | grep -q '"pass":false' || fail audit
echo '{"lang":"en","title":"T","slug":"t"}' > "$T/article.json"; scripts/hub.sh article 42 "$T/article.json" | grep -q '"article"' || fail article
scripts/hub.sh schedule 42 | grep -q scheduled || fail schedule
scripts/hub.sh schedule 99 >/dev/null 2>"$T/err" && fail "4xx should exit 1"; grep -q 'not found' "$T/err" || fail "4xx body to stderr"
curl -s localhost:3999/__flaky -H 'Authorization: Bearer tok' >/dev/null
[ "$(scripts/hub.sh selftest)" = "2026-08-31" ] || fail "retry on 5xx"
# step wraps {name,payload} and sends bearer
curl -s localhost:3999/__log -H 'Authorization: Bearer tok' | node -e '
const log=JSON.parse(require("fs").readFileSync(0,"utf8"));
const s=log.find(r=>r.url==="/api/jobs/42/steps");
if(!s||s.body.name!=="research"||JSON.stringify(s.body.payload)!=="{\"facts\":[]}")process.exit(1);
if(!log.every(r=>r.auth==="Bearer tok"))process.exit(2);
const f=log.find(r=>r.url==="/api/runs/7"); if(f.body.summary.jobs!==3)process.exit(3);'
# environment must win over .env
cp -r scripts "$T/scripts"
printf 'HUB_URL=http://localhost:1\nHUB_TOKEN=wrong\n' > "$T/.env"
[ "$(cd "$T" && HUB_URL=http://localhost:3999 HUB_TOKEN=tok scripts/hub.sh selftest)" = "2026-08-31" ] || fail "env should override .env"
# temp file is cleaned up via trap even when the request fails (404 -> no route)
echo '{}' > "$T/p.json"
scripts/hub.sh step 99 research "$T/p.json" >/dev/null 2>"$T/err99" && fail "step on missing job should exit 1"
grep -q 'no route' "$T/err99" || fail "step 99 error body missing 'no route'"
echo "hub.test.sh: all passed"
