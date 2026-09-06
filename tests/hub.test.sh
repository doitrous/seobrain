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
JOB=$(scripts/hub.sh create-job "$T/job.json")
echo "$JOB" | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(j.id===42 && j.state==="planned" ? 0 : 1)' || fail create-job
echo '{"facts":[]}' > "$T/research.json"; scripts/hub.sh step 42 research "$T/research.json" | grep -q researched || fail step
echo '{}' > "$T/badstep.json"
scripts/hub.sh step 42 bogus "$T/badstep.json" >/dev/null 2>"$T/errstep" && fail "bad step name should exit 1"
grep -q 'HTTP 400' "$T/errstep" || fail "bad step name error missing HTTP 400"
scripts/hub.sh audit 42 | grep -q '"pass":false' || fail audit
scripts/hub.sh audit 42 "$T/audit.json" >/dev/null && grep -q '"pass":false' "$T/audit.json" || fail "audit OUTFILE"
scripts/hub.sh plan "$T/plan.json" >/dev/null && grep -q '"weekOf"' "$T/plan.json" || fail "plan OUTFILE"
echo '{"lang":"en","title":"T","slug":"t"}' > "$T/article.json"; scripts/hub.sh article 42 "$T/article.json" | grep -q '"article"' || fail article
echo '{"lang":"en","title":"T"}' > "$T/article-bad.json"
scripts/hub.sh article 42 "$T/article-bad.json" >/dev/null 2>"$T/errart" && fail "article missing slug should exit 1"
grep -q 'HTTP 400' "$T/errart" || fail "article missing slug error missing HTTP 400"
scripts/hub.sh schedule 42 | grep -q scheduled || fail schedule
scripts/hub.sh schedule 99 >/dev/null 2>"$T/err" && fail "4xx should exit 1"; grep -q 'not found' "$T/err" || fail "4xx body to stderr"
grep -q 'HTTP 404' "$T/err" || fail "4xx HTTP line missing"
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
# trailing slash in HUB_URL is normalized
[ "$(HUB_URL=http://localhost:3999/ HUB_TOKEN=tok scripts/hub.sh selftest)" = "2026-08-31" ] || fail "trailing slash should be normalized"
# temp file is cleaned up via trap even when the request fails (404 -> no route)
echo '{}' > "$T/p.json"
scripts/hub.sh step 99 research "$T/p.json" >/dev/null 2>"$T/err99" && fail "step on missing job should exit 1"
grep -q 'no route' "$T/err99" || fail "step 99 error body missing 'no route'"
# exhausting retries on 5xx -> exit 3, HTTP 500 in stderr (run last: consumes the mock's forced-500 budget)
curl -s localhost:3999/__down -H 'Authorization: Bearer tok' >/dev/null
code=0; scripts/hub.sh selftest >/dev/null 2>"$T/errdown" || code=$?
[ "$code" -eq 3 ] || fail "exhausted 5xx should exit 3 (got $code)"
grep -q 'HTTP 500' "$T/errdown" || fail "exhaustion error missing HTTP 500"
echo "hub.test.sh: all passed"
