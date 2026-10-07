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
scripts/hub.sh translate-queue | grep -q '"enabled":true' || fail translate-queue
scripts/hub.sh translate-queue "$T/tq.json" >/dev/null && grep -q '"sourceLocale":"en-GB"' "$T/tq.json" || fail "translate-queue OUTFILE"
echo '{"lang":"en","title":"T","slug":"t"}' > "$T/article.json"; scripts/hub.sh article 42 "$T/article.json" | grep -q '"article"' || fail article
echo '{"lang":"en","title":"T"}' > "$T/article-bad.json"
scripts/hub.sh article 42 "$T/article-bad.json" >/dev/null 2>"$T/errart" && fail "article missing slug should exit 1"
grep -q 'HTTP 400' "$T/errart" || fail "article missing slug error missing HTTP 400"
scripts/hub.sh articles 42 | grep -q '"articles"' || fail articles
scripts/hub.sh articles 42 "$T/articles.json" >/dev/null && grep -q '"slug":"t"' "$T/articles.json" || fail "articles OUTFILE"
scripts/hub.sh schedule 42 | grep -q scheduled || fail schedule
# v2 phase 4 companion: pull approved briefs for a site
curl -s -X POST localhost:3999/__set-briefs -H 'Authorization: Bearer tok' -H 'content-type: application/json' \
  -d '{"briefs":[{"id":9,"status":"approved","keyword":"k"}]}' >/dev/null
scripts/hub.sh briefs 1 | grep -q '"id":9' || fail briefs
scripts/hub.sh briefs 1 "$T/briefs.json" >/dev/null && grep -q '"keyword":"k"' "$T/briefs.json" || fail "briefs OUTFILE"
# contract 1.9.0: a brief row may carry a pinned "slug" alongside hubRole — both pass through unchanged
curl -s -X POST localhost:3999/__set-briefs -H 'Authorization: Bearer tok' -H 'content-type: application/json' \
  -d '{"briefs":[{"id":10,"status":"approved","keyword":"k2","hubRole":"pillar","slug":"destination-giza"}]}' >/dev/null
BRIEF=$(scripts/hub.sh briefs 1)
echo "$BRIEF" | grep -q '"hubRole":"pillar"' || fail "briefs must pass through hubRole unchanged"
echo "$BRIEF" | grep -q '"slug":"destination-giza"' || fail "briefs must pass through the pinned slug"
# contract 1.21.0: keyword-metrics and serp post IN_FILE to /api/sites/SITE/... and write OUT_FILE
echo '{"lang":"ar","country":"SA","keywords":["زراعة الشعر","hair cost"]}' > "$T/kw.json"
scripts/hub.sh keyword-metrics 1 "$T/kw.json" "$T/kw-out.json" >/dev/null || fail keyword-metrics
node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(r.source==="dataforseo" && r.results.length===2 && r.results[0].volume===320 && r.results[1].volume===null ? 0 : 1)' "$T/kw-out.json" || fail "keyword-metrics OUTFILE"
scripts/hub.sh keyword-metrics s "$T/kw.json" | grep -q '"source":"dataforseo"' || fail "keyword-metrics by slug"
echo '{"lang":"ar","country":"SA","keywords":["capped"]}' > "$T/kwcap.json"
code=0; scripts/hub.sh keyword-metrics 1 "$T/kwcap.json" "$T/kwcap-out.json" >/dev/null 2>"$T/errcap" || code=$?
[ "$code" -eq 1 ] || fail "dataforseo cap should exit 1 (got $code)"
grep -q 'HTTP 429' "$T/errcap" && grep -q 'dataforseo_cap' "$T/errcap" || fail "cap error must print HTTP 429 and dataforseo_cap to stderr"
echo '{"lang":"ar","country":"AE","keywords":["x"]}' > "$T/kwbad.json"
scripts/hub.sh keyword-metrics 1 "$T/kwbad.json" >/dev/null 2>"$T/errkw" && fail "unknown market should exit 1"
grep -q 'unknown_market' "$T/errkw" || fail "unknown market body to stderr"
echo '{"lang":"en","country":"EG","keyword":"hair transplant cost egypt"}' > "$T/serp.json"
scripts/hub.sh serp 1 "$T/serp.json" "$T/serp-out.json" >/dev/null || fail serp
grep -q '"url":"https://a.example/x"' "$T/serp-out.json" || fail "serp OUTFILE"
echo '{"lang":"en","country":"EG","keyword":"free"}' > "$T/serpfree.json"
scripts/hub.sh serp 1 "$T/serpfree.json" | grep -q '"results":\[\]' || fail "serp free fallback shape"
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
const f=log.find(r=>r.url==="/api/runs/7"); if(f.body.summary.jobs!==3)process.exit(3);
const k=log.find(r=>r.url==="/api/sites/1/keyword-metrics"); if(!k||k.method!=="POST"||k.body.keywords.length!==2)process.exit(4);'
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
# contract version check (PR 1c): major mismatch aborts selftest with a clear message
curl -s localhost:3999/__contract-major-bump -H 'Authorization: Bearer tok' >/dev/null
code=0; scripts/hub.sh selftest >/dev/null 2>"$T/errcontract" || code=$?
[ "$code" -eq 1 ] || fail "contract major mismatch should abort selftest with exit 1 (got $code)"
grep -q 'major' "$T/errcontract" || fail "contract mismatch message should mention major"
curl -s localhost:3999/__contract-reset -H 'Authorization: Bearer tok' >/dev/null
[ "$(scripts/hub.sh selftest 2>"$T/errok")" = "2026-08-31" ] || fail "selftest should pass again once contract major matches"
grep -q 'continuing' "$T/errok" || fail "matching contract major should print a continuing note"
# weekly.sh / translate.sh: distinguish failures, notify, exit non-zero (stub claude + osascript via a fake HOME)
R="$T/repo"; mkdir -p "$R/scripts" "$T/home/.local/bin"
cp scripts/weekly.sh scripts/translate.sh scripts/notify.sh scripts/hub.sh "$R/scripts/"
printf '#!/bin/sh\necho "claude $*" >> "%s/claude.calls"\nexit "${STUB_CLAUDE_RC:-0}"\n' "$T" > "$T/home/.local/bin/claude"
printf '#!/bin/sh\necho "$*" >> "%s/osa.calls"\n' "$T" > "$T/home/.local/bin/osascript"
chmod +x "$T/home/.local/bin/"*
runr() { (cd "$R" && env -u HUB_URL -u HUB_TOKEN HOME="$T/home" bash "scripts/$1" >/dev/null 2>&1); }
rm -f "$T/osa.calls" "$T/claude.calls"
code=0; runr weekly.sh || code=$?
[ "$code" -eq 1 ] || fail "weekly.sh without .env should exit 1 (got $code)"
grep -q '.env missing' "$R"/runs/*/run.log || fail "weekly.sh should log missing .env"
[ -s "$T/osa.calls" ] || fail "weekly.sh should notify on a failed selftest"
rm -rf "$R/runs"; rm -f "$T/osa.calls"
printf 'HUB_URL=http://localhost:3999\nHUB_TOKEN=wrong\n' > "$R/.env"
code=0; runr weekly.sh || code=$?
[ "$code" -eq 1 ] || fail "weekly.sh with a bad token should exit 1 (got $code)"
grep -q 'hub rejected' "$R"/runs/*/run.log || fail "weekly.sh should log 4xx as hub rejected"
! grep -q 'unreachable' "$R"/runs/*/run.log || fail "weekly.sh must not call a 4xx unreachable"
rm -rf "$R/runs"
printf 'HUB_URL=http://localhost:1\nHUB_TOKEN=tok\n' > "$R/.env"
code=0; runr weekly.sh || code=$?
[ "$code" -eq 3 ] || fail "weekly.sh with an unreachable hub should exit 3 (got $code)"
grep -q 'hub unreachable' "$R"/runs/*/run.log || fail "weekly.sh should log unreachable"
rm -rf "$R/runs"; rm -f "$T/osa.calls"
printf 'HUB_URL=http://localhost:3999\nHUB_TOKEN=tok\n' > "$R/.env"
code=0; runr weekly.sh || code=$?
[ "$code" -eq 0 ] || fail "weekly.sh happy path should exit 0 (got $code)"
grep -q 'claude --model opus -p /weekly-run' "$T/claude.calls" || fail "weekly.sh should run claude with the opus alias"
[ ! -s "$T/osa.calls" ] || fail "no notification on success"
grep -qF 'weekly-run --site s' "$T/claude.calls" || fail "weekly.sh should run one session for site s"
grep -qF 'weekly-run --site forced' "$T/claude.calls" || fail "weekly.sh should run a site that only has forcedTopics"
! grep -qE 'site (paused|idle)' "$T/claude.calls" || fail "weekly.sh must skip paused and idle sites"
[ "$(wc -l < "$T/claude.calls")" -eq 2 ] || fail "weekly.sh should start exactly one session per site with work"
! grep -q -- '--resume' "$T/claude.calls" || fail "no --resume without state.json"
mkdir -p "$R/runs/$(date +%F)/s"; echo '{}' > "$R/runs/$(date +%F)/s/state.json"; rm -f "$T/claude.calls"
runr weekly.sh || fail "weekly.sh resume run should exit 0"
grep -qF 'weekly-run --site s --resume' "$T/claude.calls" || fail "weekly.sh should pass --resume for a site with state.json"
! grep -qF 'site forced --resume' "$T/claude.calls" || fail "--resume only for sites with state"
rm -f "$T/claude.calls"
code=0; STUB_CLAUDE_RC=2 runr weekly.sh || code=$?
[ "$code" -eq 2 ] || fail "weekly.sh should exit with claude's non-zero code (got $code)"
[ -s "$T/osa.calls" ] || fail "weekly.sh should notify when claude fails"
[ "$(grep -c 'claude --model' "$T/claude.calls")" -ge 2 ] || fail "weekly.sh must continue to the next site after a failure"
rm -rf "$R/runs"; rm -f "$T/osa.calls" "$T/claude.calls"
# translate.sh: bad token notifies; reachable hub with a queued version runs claude; SEO_BRAIN_MODEL overrides the alias
printf 'HUB_URL=http://localhost:3999\nHUB_TOKEN=wrong\n' > "$R/.env"
code=0; runr translate.sh || code=$?
[ "$code" -eq 1 ] || fail "translate.sh with a bad token should exit 1 (got $code)"
[ -s "$T/osa.calls" ] || fail "translate.sh should notify on a queue error"
printf 'HUB_URL=http://localhost:3999\nHUB_TOKEN=tok\n' > "$R/.env"
code=0; SEO_BRAIN_MODEL=sonnet runr translate.sh || code=$?
[ "$code" -eq 0 ] || fail "translate.sh happy path should exit 0 (got $code)"
grep -q 'claude --model sonnet -p /weekly-run --translate-only' "$T/claude.calls" || fail "translate.sh should honour SEO_BRAIN_MODEL"
# plan fixture carries the 1.18.0 pause flags
scripts/hub.sh plan | node -e 'const p=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(p.publishingPaused===false && p.sites.some(s=>s.site.publishingPaused===true) ? 0 : 1)' || fail "plan publishingPaused fields"
# plan fixture carries 1.19.0 translateLocales
scripts/hub.sh plan | node -e 'const p=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(p.sites.every(s=>Array.isArray(s.site.translateLocales)) ? 0 : 1)' || fail "plan translateLocales fields"
# exhausting retries on 5xx -> exit 3, HTTP 500 in stderr (run last: consumes the mock's forced-500 budget)
curl -s localhost:3999/__down -H 'Authorization: Bearer tok' >/dev/null
code=0; scripts/hub.sh selftest >/dev/null 2>"$T/errdown" || code=$?
[ "$code" -eq 3 ] || fail "exhausted 5xx should exit 3 (got $code)"
grep -q 'HTTP 500' "$T/errdown" || fail "exhaustion error missing HTTP 500"
# translate.sh: valid bash, and it leaves before starting Claude when nothing is queued
bash -n scripts/translate.sh || fail "translate.sh syntax"
grep -q '\[ "\${n:-0}" -gt 0 \] || exit 0' scripts/translate.sh || fail "translate.sh must exit when the queue is empty"
echo "hub.test.sh: all passed"
