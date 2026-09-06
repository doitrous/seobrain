# Phase 2: seo-brain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code project that, when run every Friday morning on Omar's Max subscription, asks the hub what each site needs this week, has Sonnet 4.6 subagents research, write, audit, and localize each article, posts every step into `seo-hub`, and schedules the articles for the review window.

**Architecture:** `seo-brain` is mostly prompts and one shell script. Opus 4.8 runs the `/weekly-run` skill as the orchestrator; it dispatches five specialized Sonnet 4.6 agents (`.claude/agents/*.md`) stage by stage, with a JSON state file per run under `runs/<date>/` so a run can be resumed. All hub I/O goes through `scripts/hub.sh` (curl + node for JSON, 3 retries on 5xx). No Anthropic API key anywhere: the run is Omar's own `claude` CLI.

**Tech Stack:** Claude Code (skills, subagents, settings permissions), bash, curl, node (for JSON only), launchd for scheduling. Companion repo `seo-hub` (Next.js) supplies the API.

**Spec:** `/Users/doitrous/Documents/CodexGPT/DoitrousTasks/seo-hub/docs/superpowers/specs/2026-09-06-seo-engine-design.md` (section "seo-brain (Claude Code project)" and "Weekly run"). Hub API contract: `/Users/doitrous/Documents/CodexGPT/DoitrousTasks/seo-hub/README.md`.

## Global Constraints

- **No paid Anthropic API.** The run is `claude -p "/weekly-run" --model claude-opus-4-8` on the Max subscription. Nothing in this repo may import an Anthropic SDK or read `ANTHROPIC_API_KEY`.
- Models, exactly: orchestrator `claude-opus-4-8`; every agent file has frontmatter `model: claude-sonnet-4-6`.
- Hub auth: every request carries `Authorization: Bearer $HUB_TOKEN`; `HUB_URL` and `HUB_TOKEN` come from `.env` (git-ignored) loaded by the scripts.
- Hub contract (from seo-hub README): `GET /api/plan` → `{weekOf, sites:[{site, neededThisWeek, queuedTopics, publishedTitles, existingArticles:[{title,slug,lang}], bannedPhrases}]}`; `POST /api/jobs {siteId, topic:{title,keyword,market,lang,source}}` → `{job}` (201 new, 200 dedupe); `POST /api/jobs/:id/steps {name, payload}`; `POST /api/jobs/:id/audit` → `{pass, issues[], stats}`; `POST /api/jobs/:id/articles {lang,title,slug,metaTitle,metaDescription,bodyMd,faq,schemaJsonld,hreflang,internalLinks}`; `POST /api/jobs/:id/schedule`; `POST /api/runs` → `{run}`; `PATCH /api/runs/:id {summary}`.
- Step names, exactly: `research, outline, draft, audit, image_brief, localize:<lang>`. Draft payload keys, exactly: `title, metaTitle, metaDescription, slug, bodyMd, keyword, targetWords, faq [{q,a}], internalLinks [{title,slug}], lang`.
- Every language version of an article shares the primary slug; article paths are `/blog/<lang>/<slug>`; hreflang maps use plain language codes plus `x-default` in phase 2 (region codes arrive in phase 4).
- Audit loop cap: 2 revisions per job (3 drafts total), then the job is left in `drafted` and reported.
- Concurrency cap: at most 4 agents in flight at once.
- All run artifacts live under `runs/<YYYY-MM-DD>/`, which is git-ignored.
- Commit trailer on every commit: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## File Structure

```
seo-brain/
  CLAUDE.md                      # what this repo is, how to run, contracts (short; points to seo-rules.md)
  README.md                      # setup, schedule, manual run, resume, troubleshooting
  .env.example                   # HUB_URL, HUB_TOKEN
  .gitignore                     # .env, runs/
  .claude/settings.json          # permission allow-list so `claude -p` never prompts
  .claude/skills/weekly-run/SKILL.md   # the orchestrator procedure (Opus 4.8)
  .claude/agents/topic-scout.md  # Sonnet 4.6
  .claude/agents/researcher.md
  .claude/agents/writer.md
  .claude/agents/auditor.md
  .claude/agents/localizer.md
  seo-rules.md                   # SEO rules, schema templates, language rules, payload contracts
  scripts/hub.sh                 # hub API wrapper
  scripts/suggest.sh             # Google Autocomplete fetch
  scripts/weekly.sh              # what launchd runs
  scripts/install-schedule.sh    # installs the launchd job
  scripts/com.doitrous.seo-brain.plist
  tests/hub.test.sh              # hub.sh contract test against a tiny node mock server
  tests/mock-hub.js
  runs/                          # git-ignored
```

seo-hub change (Task 2): `lib/seo-audit.ts` internal-link minimum relaxes on sites with fewer than two existing articles.

---

### Task 1: Repo scaffold, `hub.sh`, `suggest.sh`, and their tests

**Files:**
- Create: `.gitignore`, `.env.example`, `scripts/hub.sh`, `scripts/suggest.sh`, `tests/mock-hub.js`, `tests/hub.test.sh`
- Test: `tests/hub.test.sh`

**Interfaces:**
- Produces:
  ```
  scripts/hub.sh plan                        → JSON of GET /api/plan
  scripts/hub.sh run-start                   → run id (number) on stdout
  scripts/hub.sh run-finish <runId> <file>   → PATCH /api/runs/:id with {summary: <file contents>}
  scripts/hub.sh create-job <file>           → job id on stdout; file = {"siteId":N,"topic":{...}}
  scripts/hub.sh step <jobId> <name> <file>  → POST steps with {name, payload: <file contents>}
  scripts/hub.sh audit <jobId>               → audit JSON
  scripts/hub.sh article <jobId> <file>      → POST articles with <file contents>
  scripts/hub.sh schedule <jobId>            → job JSON
  scripts/hub.sh jobs                        → JSON of GET /api/jobs
  scripts/hub.sh selftest                    → prints weekOf, exit 0 on success
  scripts/suggest.sh <lang> <country> <query> → newline-separated suggestions
  ```
  Exit codes: 0 success; 1 on 4xx (no retry) or after 3 failed attempts on 5xx/network; the error body goes to stderr.

- [ ] **Step 1: Scaffold files**

`.gitignore`:
```
.env
runs/
.superpowers/
node_modules/
```

`.env.example`:
```
HUB_URL=https://seo.doitrous.com
HUB_TOKEN=change-me-long-random
```

Create `.env` locally (git-ignored) pointing at the local hub for development: `HUB_URL=http://localhost:3000`, `HUB_TOKEN=change-me-long-random` (the value in seo-hub's `.env.local`).

- [ ] **Step 2: Mock hub and failing test**

Create `tests/mock-hub.js`:

```js
// Minimal stand-in for seo-hub used by tests/hub.test.sh. Records requests, answers the contract.
const http = require('node:http')
const log = []
let flaky = 0 // number of 500s to return before succeeding on /api/plan
const server = http.createServer((req, res) => {
  let body = ''
  req.on('data', (c) => (body += c))
  req.on('end', () => {
    log.push({ method: req.method, url: req.url, auth: req.headers.authorization, body: body ? JSON.parse(body) : null })
    const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)) }
    if (req.headers.authorization !== 'Bearer tok') return send(401, { error: 'unauthorized' })
    if (req.url === '/__log') return send(200, log)
    if (req.url === '/__flaky') { flaky = 2; return send(200, {}) }
    if (req.url === '/api/plan') { if (flaky > 0) { flaky--; return send(500, { error: 'boom' }) } return send(200, { weekOf: '2026-08-31', sites: [] }) }
    if (req.url === '/api/runs' && req.method === 'POST') return send(201, { run: { id: 7 } })
    if (/^\/api\/runs\/\d+$/.test(req.url) && req.method === 'PATCH') return send(200, { run: { id: 7, summary: log.at(-1).body.summary } })
    if (req.url === '/api/jobs' && req.method === 'POST') return send(201, { job: { id: 42 } })
    if (req.url === '/api/jobs' && req.method === 'GET') return send(200, { jobs: [] })
    if (/^\/api\/jobs\/42\/steps$/.test(req.url)) return send(200, { job: { id: 42, state: 'researched' } })
    if (/^\/api\/jobs\/42\/audit$/.test(req.url)) return send(200, { pass: false, issues: [{ code: 'x', severity: 'error', message: 'm' }] })
    if (/^\/api\/jobs\/42\/articles$/.test(req.url)) return send(200, { article: { id: 1 } })
    if (/^\/api\/jobs\/42\/schedule$/.test(req.url)) return send(200, { job: { id: 42, state: 'scheduled' } })
    if (/^\/api\/jobs\/99\/schedule$/.test(req.url)) return send(404, { error: 'not found' })
    send(404, { error: 'no route' })
  })
})
server.listen(Number(process.env.PORT || 3999), () => console.log('mock-hub listening'))
```

Create `tests/hub.test.sh`:

```bash
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
echo "hub.test.sh: all passed"
```

Run: `bash tests/hub.test.sh`
Expected: FAIL at `selftest` (script missing / not executable).

- [ ] **Step 3: Implement `hub.sh`**

Create `scripts/hub.sh` and `chmod +x` it:

```bash
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
```

Note the `4xx` branch: `POST /api/jobs` returns 200 on a dedupe hit and 201 on create; both are `2*` and print the job. The `api()` helper treats `000` (curl failure) as retryable.

Run: `bash tests/hub.test.sh`
Expected: `hub.test.sh: all passed`.

- [ ] **Step 4: `suggest.sh`**

Create `scripts/suggest.sh` and `chmod +x`:

```bash
#!/usr/bin/env bash
# Google Autocomplete suggestions. Usage: scripts/suggest.sh <lang> <COUNTRY> "<query>"  → one suggestion per line
set -euo pipefail
lang=$1; country=$2; q=$3
curl -sS --max-time 15 -A 'Mozilla/5.0' \
  "https://suggestqueries.google.com/complete/search?client=firefox&hl=${lang}&gl=${country}&q=$(node -pe 'encodeURIComponent(process.argv[1])' "$q")" \
  | node -e 'const a=JSON.parse(require("fs").readFileSync(0,"utf8")); (a[1]||[]).forEach(s=>console.log(s))'
```

Verify: `scripts/suggest.sh en SA "hair transplant in egypt"` prints several lines (network dependent; if the endpoint is blocked, the script exits non-zero and the agents fall back to WebSearch — that fallback is written into the topic-scout prompt in Task 4).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: hub.sh and suggest.sh with mock-hub contract test" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: seo-hub — relax the internal-link minimum on sites with fewer than two articles

**Files (in `/Users/doitrous/Documents/CodexGPT/DoitrousTasks/seo-hub`, branch `phase1-hub-core`):**
- Modify: `lib/seo-audit.ts` (the `internal_link_count` check)
- Test: `tests/seo-audit.test.ts`

**Interfaces:**
- Produces: `runAudit` requires `min(2, ctx.existingSlugs.length)` to `4` internal links instead of a flat 2–4. Every other rule unchanged.

- [ ] **Step 1: Failing test**

Add to `tests/seo-audit.test.ts` inside the `runAudit` describe block:

```ts
test('new site with no articles does not require internal links', () => {
  const r = runAudit({ ...good, internalLinks: [] }, { ...ctx, existingSlugs: [] })
  expect(r.issues.map((i) => i.code)).not.toContain('internal_link_count')
})

test('site with one article requires exactly one link, still capped at four', () => {
  const one = { ...ctx, existingSlugs: ['cairo-clinics'] }
  expect(runAudit({ ...good, internalLinks: [] }, one).issues.map((i) => i.code)).toContain('internal_link_count')
  expect(runAudit({ ...good, internalLinks: [{ title: 'c', slug: 'cairo-clinics' }] }, one).issues.map((i) => i.code)).not.toContain('internal_link_count')
})
```

Run: `npm test tests/seo-audit.test.ts` → the first new test FAILS (`internal_link_count` present).

- [ ] **Step 2: Implement**

In `lib/seo-audit.ts`, replace the two lines
```ts
  const n = d.internalLinks.length
  if (n < 2 || n > 4) err('internal_link_count', `${n} internal links; want 2–4`)
```
with
```ts
  const n = d.internalLinks.length
  const need = Math.min(2, ctx.existingSlugs.length) // new sites have nothing to link to yet
  if (n < need || n > 4) err('internal_link_count', `${n} internal links; want ${need}–4`)
```

Run: `npm test` → all pass (the `internal links must exist and be 2-4` test still passes because its ctx has two slugs). `npx tsc --noEmit` clean.

- [ ] **Step 3: Commit and push (updates the open PR)**

```bash
git add lib/seo-audit.ts tests/seo-audit.test.ts
git commit -m "fix(seo-audit): require at most as many internal links as the site can provide" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 3: `seo-rules.md`

**Files:**
- Create: `seo-rules.md`

**Interfaces:**
- Produces: the single document every agent reads first. Sections, exactly these headings: `## Payload contracts`, `## Writing rules`, `## Keyword rules`, `## Structure rules`, `## Language rules`, `## International angle`, `## E-E-A-T and medical safety`, `## Internal links and slugs`, `## Image brief`, `## Schema templates`, `## Hreflang`, `## Audit codes`.

- [ ] **Step 1: Write the document**

Create `seo-rules.md` with this content:

````markdown
# SEO rules for the weekly run

Every agent reads this file before doing anything. The hub's deterministic audit enforces the numeric rules below; the rest are judgment rules the auditor checks.

## Payload contracts

Files live in `runs/<date>/job-<id>/`. Every JSON file is posted to the hub verbatim, so keys must match exactly.

- `topic.json` (topic-scout → orchestrator): `{ "title", "keyword", "market", "lang", "source": "discovered", "intent": "informational|commercial|transactional", "rationale" }`
- `research.json` (researcher): `{ "searchIntent", "facts": [{ "claim", "source_url", "quote" }], "competitorHeadings": [{ "url", "headings": [] }], "peopleAlsoAsk": [], "gaps": [], "localAngle" }`
- `outline.json` (writer): `{ "h1", "sections": [{ "h2", "h3s": [], "purpose" }], "targetWords", "primaryKeyword", "secondaryKeywords": [], "faqQuestions": [], "internalLinks": [{ "title", "slug" }] }`
- `draft.json` (writer, also the article payload): `{ "lang", "title", "metaTitle", "metaDescription", "slug", "bodyMd", "keyword", "targetWords", "faq": [{ "q", "a" }], "internalLinks": [{ "title", "slug" }], "schemaJsonld": [], "hreflang": {} }`
- `image_brief.json` (writer): `{ "prompt", "search_terms": [], "alt", "filename" }`
- `audit.json` (auditor): `{ "pass", "issues": [{ "code", "severity": "error|warn", "message" }], "source": "combined", "deterministic": <hub result>, "eeat": { "pass", "notes": [] } }`
- `article-<lang>.json` (localizer): same shape as `draft.json` with that `lang`.

## Writing rules

- Answer the search intent in the first paragraph (40–60 words), then expand. The first paragraph must contain the primary keyword naturally.
- Every factual, numeric, medical, legal, price, or travel claim must trace to a `facts[]` entry from `research.json`. If no fact supports it, do not write it. Cite sources inline as markdown links on the claim.
- Concrete over generic: named clinics, districts, prices with currency and year, procedure names, durations. No filler ("in today's fast-paced world").
- Paragraphs: 2–4 sentences. Use H2 every 150–300 words. Bulleted lists for steps, options, checklists. One comparison table where two or more options are compared.
- Tone comes from the site brief and `rules`. Never claim guarantees or outcomes. Lines in `rules` starting with `never:` are banned phrases; the hub audit fails the draft if they appear.
- Do not mention AI, the writing process, or "this article".

## Keyword rules

- One primary keyword per article (from `topic.json.keyword`). It appears in: title, H1, first 100 words, at least one H2, meta description, slug. Never more than ~1% density; never awkward repetition.
- 3–6 secondary keywords from research (People Also Ask, competitor headings, autocomplete) used naturally in H2/H3s and body.
- Meta title 45–60 characters, meta description 120–160 (Arabic: 38–70 and 102–188). Meta title ≠ H1 wording exactly; it may add a hook ("2026 guide", "costs & clinics").

## Structure rules

- Exactly one H1 (= `title`). Heading levels never skip (H2 → H3, never H2 → H4).
- Word count: `targetWords` from the outline, 900–1,600 for informational, 600–1,000 for commercial pages; body must land within ±20%.
- FAQ block: 3–6 questions taken from People Also Ask / autocomplete, each answer 40–80 words, answer-first.
- End with a short next-step section (consultation, booking, contact) matching the site's business, no hard sell.

## Language rules

- Write natively in the target language; never translate sentence by sentence. Arabic: Modern Standard Arabic with Gulf-neutral vocabulary for SA/YE/LY readers; numbers as digits; no dialect. Greek, German, Italian, Russian: standard register, formal address (Sie/Lei/вы).
- Sentence length targets (average): en 15–20 words, ar 12–18, de 14–20, el 14–20, it 15–20, ru 12–18.
- Keep proper nouns (clinic names, Cairo districts) in Latin script in Arabic text only when there is no established Arabic form.
- Right-to-left languages: no layout instructions in the text; the site handles direction.

## International angle

Each job has a `market` (ISO country code, e.g. SA, LY, YE, GR, DE, GB). The article is written for readers in that market:
- Name the market in the intro and once in an H2 where natural ("for patients from Saudi Arabia", "Ταξίδι από την Ελλάδα").
- Cover what that reader needs: flights and typical travel time to Cairo, visa notes (from research only), currency and price comparison against their home market, language support, season/timing.
- Do not fabricate visa or price facts; if research has none, say "check current requirements" and link the official source from research.

## E-E-A-T and medical safety

- Byline is the site's `author` (name, credentials). Medical sites: include one sentence of "reviewed by <author>, <credentials>" in the closing section and set `Person` schema.
- Medical content: describe procedures, risks, recovery honestly; recommend a consultation; never diagnose; never promise results; no "best", "painless", "100%".
- Cite at least 2 authoritative external sources (official bodies, peer-reviewed, established medical or tourism authorities) from research, https only.

## Internal links and slugs

- Slug: lowercase, ASCII, hyphens, ≤ 60 chars, contains the primary keyword's main words, no stop words at the ends. All language versions share the primary slug.
- Internal links: from `existingArticles` for the same site, prefer the same language; 2–4 links when the site has ≥ 2 articles, otherwise as many as exist (0 or 1). Link with descriptive anchor text inside a sentence, path `/blog/<lang>/<slug>`. Never link to the article itself.

## Image brief

- `prompt`: one photoreal scene, 25–40 words, no text in image, no faces of identifiable people, matches the site (clinic interior, Cairo skyline, Red Sea resort, consultation room), style "editorial photograph, natural light".
- `search_terms`: 3–5 stock-search phrases.
- `alt`: 8–14 words describing the image and containing the primary keyword once.
- `filename`: `<slug>-hero.jpg`.

## Schema templates

`schemaJsonld` is an array. Fill `{{...}}` from the site and article. Omit any object whose data is missing.

```json
[
  { "@context": "https://schema.org", "@type": "BlogPosting", "headline": "{{title}}", "description": "{{metaDescription}}", "inLanguage": "{{lang}}",
    "author": { "@type": "Person", "name": "{{author.name}}", "jobTitle": "{{author.credentials}}", "description": "{{author.bio}}", "image": "{{author.photoUrl}}" },
    "publisher": { "@type": "Organization", "name": "{{site.name}}", "areaServed": ["{{markets[].country}}"] },
    "mainEntityOfPage": "/blog/{{lang}}/{{slug}}", "datePublished": "{{today ISO date}}" },
  { "@context": "https://schema.org", "@type": "FAQPage",
    "mainEntity": [ { "@type": "Question", "name": "{{faq.q}}", "acceptedAnswer": { "@type": "Answer", "text": "{{faq.a}}" } } ] }
]
```

Medical sites (brief or rules mention clinic, doctor, treatment, surgery, dental, hospital): change `BlogPosting` to `MedicalWebPage` and add `"reviewedBy": { "@type": "Person", "name": "{{author.name}}", "jobTitle": "{{author.credentials}}" }`.

## Hreflang

`hreflang` is an object keyed by language code with the site-relative path of that version, plus `x-default` pointing at the site's first language:

```json
{ "en": "/blog/en/{{slug}}", "ar": "/blog/ar/{{slug}}", "x-default": "/blog/en/{{slug}}" }
```

Include every language in the site's `languages` list, whether or not its localized version exists yet (they share the slug). Region codes (`ar-SA`) come in phase 4.

## Audit codes

Deterministic (hub): `keyword_title, keyword_h1, keyword_intro, keyword_h2 (warn), keyword_meta, meta_title_length, meta_description_length, h1_count, heading_skip, word_count, paragraph_length (warn), internal_link_count, internal_link_missing, external_http, faq_count, title_duplicate, banned_phrase`.
Judgment (auditor, severity error unless noted): `unsupported_claim` (claim with no matching fact), `medical_promise` (guarantee/outcome language), `market_missing` (no market angle), `source_count` (< 2 authoritative sources), `intent_mismatch`, `translationese` (localized text reads as a translation), `faq_generic (warn)`, `thin_section (warn)`.
````

- [ ] **Step 2: Sanity check**

Run: `grep -c '^## ' seo-rules.md` → `12`. Run: `node -e 'JSON.parse(require("fs").readFileSync("seo-rules.md","utf8").split("```json")[1].split("```")[0])'` → no error (the schema template is valid JSON).

- [ ] **Step 3: Commit**

```bash
git add seo-rules.md
git commit -m "docs: seo-rules.md — payload contracts, writing/SEO rules, schema and hreflang templates" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The five agents

**Files:**
- Create: `.claude/agents/topic-scout.md`, `.claude/agents/researcher.md`, `.claude/agents/writer.md`, `.claude/agents/auditor.md`, `.claude/agents/localizer.md`
- Test: `tests/agents.test.sh`

**Interfaces:**
- Consumes: `scripts/hub.sh`, `scripts/suggest.sh`, `seo-rules.md`, the run directory layout `runs/<date>/site-<siteId>.json` and `runs/<date>/job-<jobId>/`.
- Produces: agents invoked by name from the skill with a one-paragraph prompt containing the run dir, site id, job id (and lang for localizer / mode for writer). Each agent ends by printing exactly one line: `RESULT: ok <detail>` or `RESULT: fail <reason>`.

Frontmatter is the same for all five (name/description vary):

```yaml
---
name: <agent-name>
description: <one line>
model: claude-sonnet-4-6
tools: Read, Write, Bash, WebSearch, WebFetch
---
```

- [ ] **Step 1: Failing test**

Create `tests/agents.test.sh`:

```bash
#!/usr/bin/env bash
# Structural checks on agent files: frontmatter, model pin, required sections. Run: bash tests/agents.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
for a in topic-scout researcher writer auditor localizer; do
  f=.claude/agents/$a.md
  [ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }
  head -1 "$f" | grep -q '^---$' || { echo "FAIL: $f no frontmatter"; exit 1; }
  grep -q "^name: $a$" "$f" || { echo "FAIL: $f name"; exit 1; }
  grep -q '^model: claude-sonnet-4-6$' "$f" || { echo "FAIL: $f model pin"; exit 1; }
  grep -q 'seo-rules.md' "$f" || { echo "FAIL: $f must reference seo-rules.md"; exit 1; }
  grep -q 'RESULT: ok' "$f" && grep -q 'RESULT: fail' "$f" || { echo "FAIL: $f result contract"; exit 1; }
done
grep -q 'scripts/suggest.sh' .claude/agents/topic-scout.md || { echo "FAIL: scout must use suggest.sh"; exit 1; }
grep -q 'hub.sh step' .claude/agents/researcher.md || { echo "FAIL: researcher must post step"; exit 1; }
grep -q 'hub.sh audit' .claude/agents/auditor.md || { echo "FAIL: auditor must call hub audit"; exit 1; }
grep -q 'hub.sh article' .claude/agents/localizer.md || { echo "FAIL: localizer must post article"; exit 1; }
echo "agents.test.sh: all passed"
```

Run: `bash tests/agents.test.sh` → FAIL (files missing).

- [ ] **Step 2: topic-scout**

Create `.claude/agents/topic-scout.md`:

````markdown
---
name: topic-scout
description: Finds ranked article topics for one site and one week using autocomplete, People Also Ask and web search. Use when a site needs more topics than its queue holds.
model: claude-sonnet-4-6
tools: Read, Write, Bash, WebSearch, WebFetch
---

You find article topics that can rank for a specific site in specific markets. Read `seo-rules.md` first.

## Inputs (given in your prompt)
- `RUN_DIR` (e.g. `runs/2026-09-04`), `SITE_ID`, `NEEDED` (how many topics to return).
- `RUN_DIR/site-<SITE_ID>.json`: the site object from the hub plan: `site.brief`, `site.languages`, `site.markets`, `site.seedKeywords`, `site.rules`, plus `publishedTitles`, `existingArticles`, `queuedTopics`.

## Procedure
1. Read the site file. Build 6–10 seed queries from `seedKeywords` and the services named in `brief`, phrased the way a reader in each market would search (e.g. "hair transplant Egypt cost" for SA/en, "زراعة الشعر في مصر" for SA/ar).
2. For each seed and each market: run `scripts/suggest.sh <lang> <COUNTRY> "<seed>"` and collect suggestions. If the script fails (network), skip it and rely on step 3.
3. WebSearch each seed (add the market country name to the query) and note People Also Ask style questions and the top-10 titles.
4. Cluster candidates by intent. Drop anything whose normalized title matches an entry in `publishedTitles` or `queuedTopics`, or that duplicates an `existingArticles` title.
5. Rank by: clear intent match, specificity to the site's services, market relevance, low overlap with existing articles. Prefer long-tail, question-shaped and cost/comparison topics.
6. Write `RUN_DIR/site-<SITE_ID>-topics.json`: an array of exactly `NEEDED` objects `{ "title", "keyword", "market", "lang", "source": "discovered", "intent", "rationale" }`. `lang` must be one of `site.languages`; `market` one of `site.markets[].country`; spread topics across markets and languages roughly proportionally.

## Output
Print exactly one final line: `RESULT: ok <NEEDED> topics` or `RESULT: fail <reason>`.
````

- [ ] **Step 3: researcher**

Create `.claude/agents/researcher.md`:

````markdown
---
name: researcher
description: Researches one article topic for one market and records sourced facts, competitor structure and gaps, then posts the research step to the hub.
model: claude-sonnet-4-6
tools: Read, Write, Bash, WebSearch, WebFetch
---

You research one article so the writer never has to invent a fact. Read `seo-rules.md` first (Writing rules, International angle, E-E-A-T).

## Inputs (given in your prompt)
- `RUN_DIR`, `SITE_ID`, `JOB_ID`.
- `RUN_DIR/site-<SITE_ID>.json` (site brief, author, markets, rules) and `RUN_DIR/job-<JOB_ID>/topic.json` (`title`, `keyword`, `market`, `lang`, `intent`).

## Procedure
1. WebSearch the keyword three ways: plain; with the market country name; in the target language if not English. Record the top 10 result titles and URLs.
2. WebFetch the 5 most relevant results (skip social media, forums, and the site itself). For each, record the URL and its H2/H3 headings in order.
3. Extract 12–25 facts the article will need: prices with currency and year, durations, procedure or itinerary details, regulations, travel/visa/flight facts for the market, statistics. Each fact: `{ "claim": <one sentence, specific>, "source_url": <https URL you fetched>, "quote": <≤ 30 words copied from the page supporting it> }`. Prefer official bodies, established clinics/authorities, peer-reviewed or government sources. Never record a fact you did not see on a fetched page.
4. Collect 5–8 People Also Ask / autocomplete style questions relevant to the market.
5. Note 3–5 gaps: things the top results miss that a reader from `market` needs.
6. Write one paragraph `localAngle`: how a reader from `market` approaches this topic (travel, cost comparison to home, language, season).
7. Write `RUN_DIR/job-<JOB_ID>/research.json` as `{ "searchIntent", "facts", "competitorHeadings", "peopleAlsoAsk", "gaps", "localAngle" }`, then post it: `scripts/hub.sh step <JOB_ID> research RUN_DIR/job-<JOB_ID>/research.json`.

## Rules
- At least 2 facts must come from authoritative sources (official/government/medical body/major travel authority).
- All `source_url` values must be https.
- If fewer than 8 facts can be sourced, still write the file and post it, and say so in the result line.

## Output
Print exactly one final line: `RESULT: ok <n> facts from <m> sources` or `RESULT: fail <reason>`.
````

- [ ] **Step 4: writer**

Create `.claude/agents/writer.md`:

````markdown
---
name: writer
description: Writes (or revises) one article from research and the site profile, producing outline, draft, and image brief, and posts each step to the hub.
model: claude-sonnet-4-6
tools: Read, Write, Bash
---

You write one article that answers its search intent, uses only sourced facts, and passes the hub's deterministic audit. Read `seo-rules.md` first — every section applies to you.

## Inputs (given in your prompt)
- `RUN_DIR`, `SITE_ID`, `JOB_ID`, `MODE` = `write` or `revise`.
- `RUN_DIR/site-<SITE_ID>.json` (brief, author, languages, markets, rules, existingArticles, bannedPhrases), `RUN_DIR/job-<JOB_ID>/topic.json`, `RUN_DIR/job-<JOB_ID>/research.json`.
- In `revise` mode also `RUN_DIR/job-<JOB_ID>/audit.json` (issues to fix) and the previous `draft.json`.

## Procedure — `write`
1. Read the site, topic, research. Decide `targetWords` (Structure rules) and the article's market angle from `research.localAngle`.
2. Write `RUN_DIR/job-<JOB_ID>/outline.json` (`h1`, `sections[]` with `h2`, `h3s`, `purpose`, `targetWords`, `primaryKeyword`, `secondaryKeywords`, `faqQuestions`, `internalLinks`). Pick `internalLinks` from `existingArticles` (same site, prefer same `lang`): 2–4 if the site has ≥ 2 articles, else all that exist. Post: `scripts/hub.sh step <JOB_ID> outline <file>`.
3. Write the article in `topic.lang` for `topic.market`, following the outline. Then produce `RUN_DIR/job-<JOB_ID>/draft.json` with every key from the `draft.json` contract: `lang, title, metaTitle, metaDescription, slug, bodyMd, keyword, targetWords, faq, internalLinks, schemaJsonld, hreflang`. `bodyMd` starts with `# <title>` as the single H1, includes the internal links as markdown links to `/blog/<lang>/<slug>`, cites facts inline as `[source](https://...)`, and ends with the next-step section. Build `schemaJsonld` and `hreflang` from the templates in seo-rules.md using the site's `languages` and `author`. Post: `scripts/hub.sh step <JOB_ID> draft <file>`.
4. Before posting the draft, self-check against the deterministic rules: keyword in title/H1/first 100 words/an H2/meta description; meta lengths; one H1; no heading skips; word count within ±20% of `targetWords`; FAQ ≥ 3; internal links exist in `existingArticles`; no banned phrases; every external link https. Fix, then post.
5. Write `RUN_DIR/job-<JOB_ID>/image_brief.json` (`prompt`, `search_terms`, `alt`, `filename` = `<slug>-hero.jpg`). Post: `scripts/hub.sh step <JOB_ID> image_brief <file>`.

## Procedure — `revise`
1. Read `audit.json`. For each issue, change the draft minimally to resolve it; keep everything else. Do not regenerate from scratch.
2. Overwrite `draft.json` and post it again as the `draft` step. If the image brief's `alt` or `filename` changed because the slug or keyword changed, re-post `image_brief` too.

## Output
Print exactly one final line: `RESULT: ok <words> words, <n> internal links` or `RESULT: fail <reason>`.
````

- [ ] **Step 5: auditor**

Create `.claude/agents/auditor.md`:

````markdown
---
name: auditor
description: Runs the hub's deterministic SEO audit on a job's draft, then checks factual grounding, E-E-A-T and market angle, and posts a combined audit step.
model: claude-sonnet-4-6
tools: Read, Write, Bash
---

You decide whether a draft is fit to publish. Read `seo-rules.md` first (Audit codes, E-E-A-T, International angle, Writing rules).

## Inputs (given in your prompt)
- `RUN_DIR`, `SITE_ID`, `JOB_ID`.
- `RUN_DIR/site-<SITE_ID>.json`, `RUN_DIR/job-<JOB_ID>/topic.json`, `research.json`, `draft.json`.

## Procedure
1. Run the deterministic audit: `scripts/hub.sh audit <JOB_ID> > RUN_DIR/job-<JOB_ID>/audit-deterministic.json`. Read it.
2. Judgment checks on `draft.json.bodyMd` against `research.json.facts`:
   - `unsupported_claim`: every number, price, duration, regulation, medical or travel claim must match a fact (same meaning, same figure). List each unsupported one with the sentence.
   - `medical_promise`: guarantees, "best", "painless", "100%", outcome promises, diagnosis language.
   - `market_missing`: the market is not addressed in the intro and at least one section.
   - `source_count`: fewer than 2 authoritative external sources linked.
   - `intent_mismatch`: the article answers a different question than the keyword implies.
   - `faq_generic` (warn), `thin_section` (warn: any H2 section under 60 words).
3. `pass` = deterministic `pass` AND no judgment issue with severity `error`.
4. Write `RUN_DIR/job-<JOB_ID>/audit.json`: `{ "pass", "issues": [<deterministic issues>, <judgment issues>], "source": "combined", "deterministic": <hub result>, "eeat": { "pass": <judgment pass>, "notes": [] } }`. Post: `scripts/hub.sh step <JOB_ID> audit RUN_DIR/job-<JOB_ID>/audit.json`.

## Rules
- Never edit the draft. Never soften an `error` because the draft is otherwise good.
- Quote the offending sentence in each judgment issue's `message` so the writer can find it.

## Output
Print exactly one final line: `RESULT: ok pass` or `RESULT: ok fail <n> errors` or `RESULT: fail <reason>`.
````

- [ ] **Step 6: localizer**

Create `.claude/agents/localizer.md`:

````markdown
---
name: localizer
description: Produces a native-language version of an audited article for one additional site language and posts it to the hub as an article version.
model: claude-sonnet-4-6
tools: Read, Write, Bash
---

You write a native version of an existing article in another language. This is a rewrite for readers of that language, not a translation. Read `seo-rules.md` first (Language rules, Keyword rules, Structure rules, Hreflang).

## Inputs (given in your prompt)
- `RUN_DIR`, `SITE_ID`, `JOB_ID`, `LANG` (target language code).
- `RUN_DIR/site-<SITE_ID>.json`, `RUN_DIR/job-<JOB_ID>/topic.json`, `research.json`, `draft.json` (the audited primary version).

## Procedure
1. Read the draft and research. Keep the same facts, structure, internal links and slug. Rewrite every sentence natively in `LANG` following Language rules (sentence length, register, numerals). Re-express the market angle for readers of `LANG` where the market's language matches (e.g. Arabic for SA/LY/YE).
2. Choose a native primary keyword for `LANG` (how those readers actually search; use `research.peopleAlsoAsk` and the topic keyword as guidance) and apply the Keyword rules with that keyword: title, H1, first 100 words, one H2, meta description.
3. Meta title/description within the `LANG` length rules. FAQ questions rewritten natively.
4. Write `RUN_DIR/job-<JOB_ID>/article-<LANG>.json` with the full `draft.json` shape: `lang` = `LANG`, `slug` = the primary slug unchanged, `keyword` = the native keyword, `schemaJsonld` regenerated with `inLanguage` = `LANG` and the localized headline/description/FAQ, `hreflang` identical to the primary's map.
5. Post: `scripts/hub.sh article <JOB_ID> RUN_DIR/job-<JOB_ID>/article-<LANG>.json`, then post the step marker: write `{"lang":"<LANG>","words":<n>}` to `RUN_DIR/job-<JOB_ID>/localize-<LANG>.json` and run `scripts/hub.sh step <JOB_ID> localize:<LANG> <that file>`.

## Rules
- Never leave untranslated sentences from the source. Never transliterate whole sentences.
- Internal link anchor text is rewritten natively; the link paths change only the `<lang>` segment: `/blog/<LANG>/<slug>`.

## Output
Print exactly one final line: `RESULT: ok <LANG> <words> words` or `RESULT: fail <reason>`.
````

- [ ] **Step 7: Run the structural test and commit**

Run: `bash tests/agents.test.sh` → `agents.test.sh: all passed`.

```bash
git add .claude/agents tests/agents.test.sh
git commit -m "feat: topic-scout, researcher, writer, auditor, localizer agents (Sonnet 4.6)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `/weekly-run` skill, permissions, `CLAUDE.md`

**Files:**
- Create: `.claude/skills/weekly-run/SKILL.md`, `.claude/settings.json`, `CLAUDE.md`
- Test: `tests/skill.test.sh`

**Interfaces:**
- Consumes: agents by name (`topic-scout, researcher, writer, auditor, localizer`), `scripts/hub.sh`, run dir layout.
- Produces: `/weekly-run [--resume] [--site <slug>] [--dry-run]`. State file `runs/<date>/state.json`.

- [ ] **Step 1: Failing test**

Create `tests/skill.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
f=.claude/skills/weekly-run/SKILL.md
[ -f "$f" ] || { echo "FAIL: skill missing"; exit 1; }
grep -q '^name: weekly-run$' "$f" || { echo "FAIL: skill name"; exit 1; }
for a in topic-scout researcher writer auditor localizer; do grep -q "$a" "$f" || { echo "FAIL: skill must dispatch $a"; exit 1; }; done
for s in 'hub.sh plan' 'hub.sh run-start' 'hub.sh create-job' 'hub.sh article' 'hub.sh schedule' 'hub.sh run-finish' 'state.json' '--resume' 'at most 4'; do
  grep -q -- "$s" "$f" || { echo "FAIL: skill must mention '$s'"; exit 1; }
done
node -e 'const s=require("./.claude/settings.json"); const a=s.permissions.allow; for (const need of ["Bash(scripts/hub.sh:*)","Bash(scripts/suggest.sh:*)","WebSearch","WebFetch","Agent","Read","Write"]) if(!a.includes(need)) {console.error("FAIL: settings missing "+need); process.exit(1)}'
grep -q 'claude-opus-4-8' CLAUDE.md || { echo "FAIL: CLAUDE.md must state the orchestrator model"; exit 1; }
echo "skill.test.sh: all passed"
```

Run: `bash tests/skill.test.sh` → FAIL.

- [ ] **Step 2: Permissions**

Create `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(scripts/hub.sh:*)",
      "Bash(scripts/suggest.sh:*)",
      "Bash(mkdir:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(date:*)",
      "Read",
      "Write",
      "Edit",
      "WebSearch",
      "WebFetch",
      "Agent"
    ]
  }
}
```

- [ ] **Step 3: The skill**

Create `.claude/skills/weekly-run/SKILL.md`:

````markdown
---
name: weekly-run
description: Produce this week's SEO articles for every enabled site — plan from the hub, dispatch Sonnet 4.6 agents to research, write, audit and localize, post every step to the hub, and schedule the articles. Use for the Friday run or a manual run.
---

# Weekly run (orchestrator)

You are the orchestrator. You never write article text yourself; you dispatch the agents and keep state. Model: this session runs as Opus 4.8 (`claude --model claude-opus-4-8`).

Arguments: `--resume` (continue today's run from `state.json`), `--site <slug>` (only that site), `--dry-run` (plan and choose topics, create no jobs).

## 0. Setup
- `DATE=$(date +%F)`, `RUN_DIR=runs/$DATE`, `mkdir -p $RUN_DIR`.
- Without `--resume`: `scripts/hub.sh plan > $RUN_DIR/plan.json`; `RUN_ID=$(scripts/hub.sh run-start)`; write `$RUN_DIR/state.json`:
  `{ "runId": <RUN_ID>, "weekOf": <plan.weekOf>, "jobs": {} }`.
  For each site in `plan.sites` write `$RUN_DIR/site-<site.id>.json` containing the whole plan entry (`site`, `neededThisWeek`, `queuedTopics`, `publishedTitles`, `existingArticles`, `bannedPhrases`).
- With `--resume`: read `state.json` and the existing site/job files; skip every job step already marked `done`.
- Concurrency rule for every stage below: dispatch agents in parallel, **at most 4 in flight**; wait for the batch before the next.

## 1. Topics
For each site with `neededThisWeek > 0` (respecting `--site`):
- Take up to `neededThisWeek` entries from `queuedTopics` (they are user-supplied; keep their `topicId`).
- If still short by `k`, dispatch **topic-scout** with `RUN_DIR`, `SITE_ID`, `NEEDED=k`; read `site-<id>-topics.json`.
- `--dry-run`: print the chosen topics per site and stop here.
- Create jobs: for a queued topic write `{ "siteId", "topicId" }`, for a discovered one `{ "siteId", "topic": {…} }`, to `$RUN_DIR/job-tmp.json` and `JOB_ID=$(scripts/hub.sh create-job $RUN_DIR/job-tmp.json)`. Then `mkdir -p $RUN_DIR/job-$JOB_ID`, write `topic.json` there (title, keyword, market, lang, intent, source), and add to `state.jobs[JOB_ID] = { "siteId", "lang", "languages": site.languages, "steps": {}, "auditLoops": 0, "status": "planned" }`.
- Save `state.json` after every job creation and after every step below.

## 2. Research
For every job without `steps.research`: dispatch **researcher** (`RUN_DIR`, `SITE_ID`, `JOB_ID`). On `RESULT: ok` set `steps.research = "done"`. On fail, retry once; on second fail set `status = "failed"`, `error`, and skip this job for the rest of the run.

## 3. Write
For every job with research done and no `steps.draft`: dispatch **writer** with `MODE=write`. On ok set `steps.outline`, `steps.draft`, `steps.image_brief` to `"done"`.

## 4. Audit loop
For every job with a draft and no passing audit:
- Dispatch **auditor**. Read `$RUN_DIR/job-$JOB_ID/audit.json`.
- If `pass`: set `steps.audit = "pass"`.
- Else increment `auditLoops`; if `auditLoops <= 2` dispatch **writer** with `MODE=revise`, then audit again; if `auditLoops > 2` set `status = "needs_review"` and move on (the hub shows the job in `drafted` with the audit issues; Omar can fix it in the dashboard).

## 5. Primary article
For every job with `steps.audit = "pass"` and no `steps.article`: `scripts/hub.sh article $JOB_ID $RUN_DIR/job-$JOB_ID/draft.json` then set `steps.article = "done"`.

## 6. Localize
For every such job and every language in `languages` other than the job's `lang`: dispatch **localizer** with `LANG`. On ok set `steps["localize:<LANG>"] = "done"`. A failed localizer after one retry is recorded in `state` but does not block scheduling (the primary version still ships; the missing language is listed in the summary).

## 7. Schedule
For every job with `steps.article = "done"` and all localizers finished or failed: `scripts/hub.sh schedule $JOB_ID`, set `status = "scheduled"`.

## 8. Finish
Write `$RUN_DIR/summary.json`:
`{ "weekOf", "sites": [{ "siteId", "name", "needed", "created", "scheduled", "needsReview": [jobIds], "failed": [{ "jobId", "error" }], "missingLanguages": [{ "jobId", "lang" }] }], "jobs": <count>, "durationMinutes" }`
then `scripts/hub.sh run-finish $RUN_ID $RUN_DIR/summary.json`. Print the summary as a short table.

## Rules
- Never skip a hub post to save time; the dashboard is the record.
- If `scripts/hub.sh` fails on a 4xx, read the error body: it is a contract violation in the agent's output (missing key, bad lang). Fix the file by re-dispatching that agent with the error quoted; never hand-edit article content yourself.
- If the hub is unreachable (5xx after retries), save `state.json` and stop with `RESULT: hub unreachable — rerun with --resume`.
- Agent prompts are short: name the agent's inputs (RUN_DIR, SITE_ID, JOB_ID, MODE/LANG/NEEDED) and nothing else; the agent files carry the instructions.
````

- [ ] **Step 4: CLAUDE.md**

Create `CLAUDE.md`:

```markdown
# seo-brain

The weekly article producer for Omar's sites. The hub (`seo-hub`, Next.js) stores everything and publishes; this repo only generates.

- Orchestrator: `/weekly-run` skill, run as `claude --model claude-opus-4-8 -p "/weekly-run"` from this directory (Max subscription, no API key).
- Agents (`.claude/agents/`, all `claude-sonnet-4-6`): topic-scout, researcher, writer, auditor, localizer. They read `seo-rules.md` first and talk to the hub only through `scripts/hub.sh`.
- Config: `.env` with `HUB_URL`, `HUB_TOKEN` (see `.env.example`). Run artifacts: `runs/<date>/` (git-ignored).
- Contracts: payload shapes in `seo-rules.md` → "Payload contracts"; hub endpoints in `scripts/hub.sh` usage.
- Tests: `bash tests/hub.test.sh && bash tests/agents.test.sh && bash tests/skill.test.sh`.
- Never add an Anthropic SDK or API key to this repo.
```

- [ ] **Step 5: Test and commit**

Run: `bash tests/skill.test.sh` → passes. Run all three test scripts.

```bash
git add .claude/settings.json .claude/skills CLAUDE.md tests/skill.test.sh
git commit -m "feat: weekly-run orchestrator skill, permissions, CLAUDE.md" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Scheduling (launchd) and README

**Files:**
- Create: `scripts/weekly.sh`, `scripts/com.doitrous.seo-brain.plist`, `scripts/install-schedule.sh`, `README.md`

**Interfaces:**
- Produces: `scripts/install-schedule.sh` installs a launchd agent that runs `scripts/weekly.sh` every Friday 07:00 local time; `scripts/weekly.sh` runs the orchestrator non-interactively and logs to `runs/<date>/run.log`.

- [ ] **Step 1: weekly.sh**

Create `scripts/weekly.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Entry point for the scheduled Friday run. Logs to runs/<date>/run.log. Safe to re-run: passes --resume if today's state exists.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
DATE=$(date +%F); mkdir -p "runs/$DATE"
ARGS="/weekly-run"; [ -f "runs/$DATE/state.json" ] && ARGS="/weekly-run --resume"
{
  echo "=== seo-brain $(date) ==="
  scripts/hub.sh selftest || { echo "hub unreachable"; exit 1; }
  claude --model claude-opus-4-8 -p "$ARGS" --output-format text
  echo "=== exit $? $(date) ==="
} >> "runs/$DATE/run.log" 2>&1
```

- [ ] **Step 2: plist and installer**

Create `scripts/com.doitrous.seo-brain.plist` (the installer substitutes `__REPO__`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.doitrous.seo-brain</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>__REPO__/scripts/weekly.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
  <key>WorkingDirectory</key><string>__REPO__</string>
  <key>StandardOutPath</key><string>__REPO__/runs/launchd.log</string>
  <key>StandardErrorPath</key><string>__REPO__/runs/launchd.log</string>
</dict></plist>
```

Create `scripts/install-schedule.sh` (`chmod +x`):

```bash
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
```

Verify the plist is valid without installing: `plutil -lint scripts/com.doitrous.seo-brain.plist` → `OK`. Do **not** run the installer in this task (Task 7 covers it with the owner's approval).

- [ ] **Step 3: README**

Create `README.md`:

````markdown
# seo-brain

Weekly SEO article producer. Runs in Omar's own Claude Code (Max subscription). Opus 4.8 orchestrates; Sonnet 4.6 agents research, write, audit, localize; everything is posted to the hub (`seo-hub`), which holds the review window and publishes.

## Setup
1. `cp .env.example .env` and set `HUB_URL` (e.g. `https://seo.doitrous.com`) and `HUB_TOKEN` (the hub's `HUB_TOKEN`).
2. `scripts/hub.sh selftest` prints the current week (Monday) if the hub is reachable.
3. `bash tests/hub.test.sh && bash tests/agents.test.sh && bash tests/skill.test.sh`.

## Run manually
```bash
claude --model claude-opus-4-8 -p "/weekly-run"            # full run
claude --model claude-opus-4-8 -p "/weekly-run --site aspects-clinica"
claude --model claude-opus-4-8 -p "/weekly-run --dry-run"  # choose topics only, create nothing
claude --model claude-opus-4-8 -p "/weekly-run --resume"   # continue today's run after an interruption
```
Or interactively: `claude --model claude-opus-4-8` then type `/weekly-run`.

## Schedule (Friday 07:00, this Mac)
`scripts/install-schedule.sh` installs a launchd agent that runs `scripts/weekly.sh`. The Mac must be awake at 07:00 (System Settings → Energy, or `pmset repeat wakeorpoweron F 06:55:00` once with admin rights). Logs: `runs/<date>/run.log`. Uninstall: `scripts/install-schedule.sh --uninstall`.

Alternative when the Mac cannot be awake: a Claude Code cloud routine (`/schedule` in Claude Code) on cron `0 7 * * 5` Africa/Cairo running `/weekly-run` from this repo, with `HUB_URL`/`HUB_TOKEN` as routine environment variables. Same skill, same agents.

## What a run does
plan → topics (queue first, then topic-scout) → jobs → researcher → writer (outline, draft, image brief) → auditor (hub deterministic audit + judgment; up to 2 revisions) → primary article → localizer per extra language → schedule → run summary. State: `runs/<date>/state.json`; per-job files under `runs/<date>/job-<id>/`.

## Files
- `.claude/skills/weekly-run/SKILL.md` — the orchestrator procedure
- `.claude/agents/*.md` — the five agents (`model: claude-sonnet-4-6`)
- `seo-rules.md` — rules, payload contracts, schema/hreflang templates, audit codes
- `scripts/hub.sh` — hub API wrapper (`plan, run-start, run-finish, create-job, step, audit, article, schedule, jobs, selftest`)
- `scripts/suggest.sh` — Google Autocomplete

## Troubleshooting
- `hub.sh` prints a 4xx body: an agent produced a payload that violates the contract (see `seo-rules.md` → Payload contracts). The orchestrator re-dispatches that agent with the error.
- A job ends in `needs_review`: it failed the audit three times; open it in the hub dashboard, fix, re-run audit there.
- `hub unreachable`: check `HUB_URL`, the hub's `HUB_TOKEN`, then re-run with `--resume`.
````

- [ ] **Step 4: Commit**

```bash
plutil -lint scripts/com.doitrous.seo-brain.plist
git add scripts/weekly.sh scripts/com.doitrous.seo-brain.plist scripts/install-schedule.sh README.md
git commit -m "feat: Friday launchd schedule, weekly.sh entry point, README" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: End-to-end run against the local hub (controller-executed)

This task is run by the controller in the owner's Claude Code, not by an implementer subagent, because it spends real Max usage and invokes `claude` itself.

**Files:** none created in the repo (artifacts under `runs/`).

- [ ] **Step 1: Prepare the hub**

In `seo-hub` (branch `phase1-hub-core`, local Postgres on 5433): start `npm run dev`. Create a test site via the dashboard or API with: slug `test-brain`, name `Test Clinic`, brief describing a Cairo hair-transplant clinic serving Saudi and Libyan patients, author `Dr. Test, MD`, languages `["en","ar"]`, markets `[{"country":"SA","lang":"ar"},{"country":"GB","lang":"en"}]`, cadencePerWeek `1`, reviewHours `0`, adapter `{ "type": "custom", "url": "", "secret": "" }`, rules containing `never: guaranteed results`. Disable every other site (`enabled=false`) so the run touches only this one.

- [ ] **Step 2: Dry run**

From `seo-brain` with `.env` pointing at `http://localhost:3000`:
```bash
claude --model claude-opus-4-8 -p "/weekly-run --dry-run --site test-brain" --output-format text
```
Expected: one topic printed for the site, no jobs created (`scripts/hub.sh jobs` unchanged).

- [ ] **Step 3: Full run**

```bash
claude --model claude-opus-4-8 -p "/weekly-run --site test-brain" --output-format text | tee runs/manual-run.log
```
Expected in the hub dashboard: one run row with a summary; one job for `Test Clinic` with steps `research, outline, draft, audit (pass), image_brief, localize:ar`, two article versions (`en`, `ar`) sharing one slug, state `scheduled` then (cron with `reviewHours 0`) `waiting_image`. `runs/<date>/state.json` shows every step `done`.

- [ ] **Step 4: Resume path**

Delete `steps["localize:ar"]` from `state.json`, run `claude --model claude-opus-4-8 -p "/weekly-run --resume --site test-brain"`. Expected: only the localizer is dispatched; the article version is upserted (same id), job stays `scheduled`.

- [ ] **Step 5: Record**

Append the observed job id, run id, word counts, and any agent failures to `docs/superpowers/plans/2026-09-06-phase2-seo-brain.md` under a `## Test run log` heading, commit with `docs: phase 2 test run log`.

---

## Self-review

**Spec coverage (seo-brain section):** CLAUDE.md ✔ (T5), five agents with Sonnet 4.6 ✔ (T4), `weekly-run` skill with steps 1–4 of the spec's "Weekly run" ✔ (T5: plan/run row; queue-first topics then scout; researcher/writer/auditor/localizer; schedule; summary), `seo-rules.md` ✔ (T3: rules, schema templates, hreflang, E-E-A-T), `scripts/hub.sh` with retries ✔ (T1), local `run-<date>.json` for `--resume` ✔ (`state.json`, T5), scheduling Friday 07:00 Cairo ✔ (T6 launchd; cloud routine documented), subagent failure policy (retry once, mark failed, continue) ✔ (T5 §2). Deviations recorded: JSON-LD built by writer/localizer from templates instead of by the orchestrator (fewer hand-offs); localized versions per site language, market-specific siblings and region hreflang deferred to phase 4; no hub "fail job" endpoint, failures live in the run summary and `state.json`.

**Placeholder scan:** none.

**Type consistency:** `hub.sh` commands used in agents and skill match Task 1's interface (`step JOB NAME FILE`, `article JOB FILE`, `audit JOB`, `schedule JOB`, `create-job FILE`, `run-start`, `run-finish ID FILE`). Payload keys in agents match `seo-rules.md` contracts and the hub README. `RESULT:` line contract shared by all agents and consumed by the skill.
