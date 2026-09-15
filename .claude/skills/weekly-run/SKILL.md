---
name: weekly-run
description: Produce this week's SEO articles for every enabled site — plan from the hub, dispatch Sonnet 4.6 agents to research, write, audit and localize, post every step to the hub, and schedule the articles. Use for the Friday run or a manual run.
---

# Weekly run (orchestrator)

You are the orchestrator. You never write article text yourself; you dispatch the agents and keep state. Model: this session runs as Opus 4.8 (`claude --model claude-opus-4-8`).

Arguments: `--resume` (continue today's run from `state.json`), `--site <slug>` (only that site), `--dry-run` (plan and choose topics, create no jobs).

## 0. Setup
- Run `date +%F`; that is DATE. RUN_DIR is `runs/<date>`. Run `mkdir -p RUN_DIR`.
- Run `scripts/hub.sh selftest` once (it also checks the hub's contract version — see Rules). `scripts/weekly.sh` already runs this before dispatching you, so it is nearly instant then; running it again is cheap and covers a manual or cloud-routine invocation that skipped weekly.sh.
- Without `--resume`: run `scripts/hub.sh plan RUN_DIR/plan.json` (the second argument is the output file; never use a shell redirect, pipe, `;` or `bash` prefix with `scripts/hub.sh` — only the plain form is permitted in the unattended run, for you and for every agent). For each site in `plan.sites` write `RUN_DIR/site-<site.id>.json` containing the whole plan entry (`site`, `neededThisWeek`, `queuedTopics`, `publishedTitles`, `existingArticles`, `bannedPhrases`, `blockedTopics`).
- `--dry-run` stops here: it does not run `run-start` and does not write `state.json`; only `plan.json` and the per-site files above are written, and §1 prints the chosen topics and stops.
- Otherwise (not `--dry-run`): run `scripts/hub.sh run-start`; the printed number is RUN_ID. Write `RUN_DIR/state.json`:
  `{ "runId": <RUN_ID>, "weekOf": <plan.weekOf>, "jobs": {} }`.
- With `--resume`: read `state.json` and the existing site/job files; skip every job step already marked `done`.
  With `--resume`, §1 runs per site with `stillNeeded = neededThisWeek − (jobs for that site already in state.jobs)`: queued topics whose `topicId` is already in state are skipped, existing `site-<id>-topics.json` entries are reused before dispatching topic-scout again, and topic-scout is asked only for the remaining `k`. The hub also dedupes `POST /api/jobs` by (siteId, topicId) and by title per site, so a repeated create returns the existing job rather than a duplicate.
- Concurrency rule for every stage below: dispatch agents in parallel, **at most 4 in flight**; wait for the batch before the next.

## Agent failure policy (applies to every stage)
An agent has failed when it ends without a RESULT: ok line or its expected output file is missing. Retry that agent once with the same inputs. On the second failure set status = "failed" and error = <the RESULT: fail reason or "no result">, save state.json, and skip the job for the rest of the run; it appears under failed in the summary. The only exception is the localizer: on its second failure set steps["localize:<LANG>"] = "failed" instead, keep status, and continue; the job still ships with its primary version and the language is listed under missingLanguages.

## 1. Topics
For each site with `neededThisWeek > 0` (respecting `--site`):
- Take up to `neededThisWeek` entries from `queuedTopics` (they are user-supplied). Each `queuedTopics[]` row has `id, title, keyword, market, lang, source, pageType`: set `topicId = queuedTopics[].id`, and take `lang`, `market`, `keyword`, `title`, `pageType` from that same row (matched by topicId; `pageType` may be `null` — leave it out of `topic.json` rather than write `null`). Set `intent` to `informational`, unless the keyword clearly signals cost or comparison — then use `commercial`. **Take rows with `source: "refresh"` first** — the hub queued them because a published article reached its refresh date; they carry `refreshJobId`, the job being refreshed, and they are exempt from the keyword guard. Write these to topic.json the same way as a discovered topic.
- If still short by `k`, dispatch **topic-scout** with RUN_DIR, SITE_ID, `NEEDED=k`; read `site-<id>-topics.json` (each entry already carries `pageType` — topic-scout assigns it, see its own file).
- `--dry-run`: print the chosen topics per site and stop here; no `run-start` was called and no `state.json` was written (see §0) — only `plan.json` exists.
- Create jobs: for a queued topic write `{ "siteId", "topicId" }` — and when that topic's `source` is `"refresh"`, write `{ "siteId", "topicId", "refreshOf": <topic.refreshJobId> }` instead (queued topics' `pageType`, if any, is already stored on the topic row — no need to repeat it here). For a discovered one write `{ "siteId", "topic": { …, "pageType" } }` (include `pageType` in the nested `topic` object; omit the key entirely if topic-scout left it unset). Write it to `RUN_DIR/job-tmp.json` and run `scripts/hub.sh create-job RUN_DIR/job-tmp.json`; it prints the job JSON — JOB_ID is its `id`.
  - **HTTP 409 `{"error":"keyword_taken","jobId":<n>}`** means this site already has an article for that keyword and language. Detect it from the failed command's output: `scripts/hub.sh` exits **1** for every 4xx and prints two lines to **stderr** — `HTTP 409` followed by the JSON body. So the marker is exit code 1 *plus* `HTTP 409` on stderr (the body then names `keyword_taken`); exit 1 with any other `HTTP 4xx` line is the ordinary contract violation handled by the Rules. A 409 is not an agent failure: drop the topic, note its title in the summary under `skippedDuplicates`, and ask topic-scout for one replacement topic (once). Never retry the same keyword. If the replacement topic also returns 409, skip that slot for the week — do not ask for a third — and record **both** titles under `skippedDuplicates`.
  - **HTTP 409 `{"error":"topic_owned_by_other_site","ownerSiteId","ownerSiteSlug","targetUrl"}`** means the topic ledger has this keyword+language owned by a different site — topic-scout should already have filtered these out via `blockedTopics`, so seeing one means the ledger changed mid-run. Handle it exactly like `keyword_taken`: drop the topic, note it under `skippedDuplicates`, ask topic-scout for one replacement (once), never retry the same keyword.
  - **HTTP 400 `{"error":"guide_quota_exceeded"}`** means this site already has 3 consecutive `guide` jobs and is under its bottom-funnel quota. Not an agent failure: drop the topic, note it under `skippedDuplicates`, and ask topic-scout for one replacement (once) — the replacement request should prefer a bottom-funnel `pageType` (`cost`, `procedure`/`tour`, `help`, `tool`) if the site's topics support it.
  - If the returned job's `state` is anything other than `planned`, or its `weekOf` differs from `plan.weekOf`, the hub matched an older job to this topic: do not use that job and do not attach steps to it — ask topic-scout for one replacement topic (once) instead, and note the skipped title in the summary under `skippedDuplicates`.
  - Otherwise run `mkdir -p RUN_DIR/job-<JOB_ID>`, write `topic.json` there (title, keyword, market, lang, intent, pageType, source), and add to `state.jobs[JOB_ID] = { "siteId", "topicId" (queued topics only), "title", "lang", "languages": site.languages, "refreshOf": <job id or null>, "steps": {}, "auditLoops": 0, "status": "planned" }`.
- Save `state.json` after every job creation and after every step below.

## 2. Research
For every job without `steps.research`: dispatch **researcher** (`RUN_DIR`, `SITE_ID`, `JOB_ID`). On `RESULT: ok` set `steps.research = "done"`. On fail apply the failure policy.

## 3. Write
For every job with research done and no `steps.draft`: dispatch **writer** with `MODE=write` — or with `MODE=refresh` when the job has `refreshOf` set (its topic came from the refresh queue with `source: "refresh"`, and `refreshOf` is that topic's `refreshJobId`, the original job). The prompt contract is unchanged: `RUN_DIR`, `SITE_ID`, `JOB_ID`, `MODE`; in refresh mode the writer fetches the published article itself with `scripts/hub.sh articles` and revises it. On ok set `steps.outline`, `steps.draft`, `steps.image_brief` to `"done"`. On fail apply the failure policy.

## 4. Audit loop
For every job with a draft and no passing audit:
- Dispatch **auditor**. Read `RUN_DIR/job-<JOB_ID>/audit.json`. On fail apply the failure policy.
- On a medical site the auditor posts the `checklist` step before running its own audit, and its RESULT line ends in `checklist: posted` (`checklist: n/a` on general sites). On a medical site anything other than `checklist: posted` (including `failed`, `n/a` or a missing marker) means re-dispatch the auditor once; if it still does not report `posted`, treat it as an audit failure (same loop as below). Gate on that word, not on the local file. The hub fails `checklist_complete` (critical) at publish time without the step, so the job would sit in `needs_review` forever. A `checklist_gap` issue from the auditor is critical and therefore also a failed audit.
- If `pass`: set `steps.audit = "pass"` (and `steps.checklist = "done"` on medical sites, only once `checklist: posted` was seen).
- Else increment `auditLoops`; if `auditLoops <= 2` dispatch **writer** with `MODE=revise`, then audit again; if `auditLoops > 2` set `status = "needs_review"` and move on (the hub shows the job in `drafted` with the audit issues; Omar can fix it in the dashboard).

## 5. Primary article
For every job with `steps.audit = "pass"` and no `steps.article`: run `scripts/hub.sh article <JOB_ID> RUN_DIR/job-<JOB_ID>/draft.json`, then set `steps.article = "done"`.

## 6. Localize
For every such job and every language in `languages` other than the job's `lang`: dispatch **localizer** with `LANG`. On ok set `steps["localize:<LANG>"] = "done"`. On fail apply the failure policy (localizer exception).

## 7. Schedule
For every job with `steps.article = "done"` and every language in `languages` other than the job's `lang` has `steps["localize:<LANG>"]` equal to `"done"` or `"failed"`: run `scripts/hub.sh schedule <JOB_ID>`, set `status = "scheduled"`.
- **HTTP 409 `{"error":"publish_blocked","reason":...}`** (hub-wide pause, this site's pause, its draft-only ramp, or approval required — see seohub `docs/contracts/README.md`) is expected, not a failure: record `state.jobs[JOB_ID].blockedReason = reason`, leave `status` as it was, and list the job under `blocked` in the summary (§8). Do not retry and do not apply the Agent failure policy.

Scheduling is not publishing. At the end of the review window the hub re-runs the audit in publish mode; a critical failure parks the job in `needs_review` with the failing codes instead of publishing it, and Omar clears it in the dashboard. Reviewer dates are stamped by the hub at that moment, never by this run.

## 8. Finish
Write `RUN_DIR/summary.json`:
`{ "weekOf", "sites": [{ "siteId", "name", "needed", "created", "scheduled", "blocked": [{ "jobId", "reason" }], "needsReview": [jobIds], "failed": [{ "jobId", "error" }], "missingLanguages": [{ "jobId", "lang" }], "skippedDuplicates": [titles] }], "jobs": <count>, "durationMinutes" }`
`missingLanguages` is derived from `steps["localize:<LANG>"] = "failed"`; `failed` from `status = "failed"`; `needsReview` from `status = "needs_review"`; `blocked` from `state.jobs[JOB_ID].blockedReason` set in §7 — the job stays wherever it was, this is not a failure, the hub's gate will let it through on a later run once the reason clears; `skippedDuplicates` from the titles dropped on 409 in §1 (the original and, when it also collided, the replacement).
Then run `scripts/hub.sh run-finish <RUN_ID> RUN_DIR/summary.json`. Print the summary as a short table.

## Rules
- Never skip a hub post to save time; the dashboard is the record.
- If `scripts/hub.sh` fails on a 4xx (exit code 1; stderr carries `HTTP <code>` then the body), read the error body: it is a contract violation in the agent's output (missing key, bad lang). Re-dispatch the responsible agent at most once with the error body quoted; on a second 4xx apply the failure policy. A 4xx from `create-job`, `schedule` or `run-finish` has no agent: mark the job `failed` with the body (for `run-finish`, print the error and stop). **Four exceptions, none a contract violation:** `HTTP 409` `keyword_taken` from `create-job`, `HTTP 409` `topic_owned_by_other_site` from `create-job`, and `HTTP 400` `guide_quota_exceeded` from `create-job` — all three skip the topic and ask for a replacement (§1), mark nothing failed; and `HTTP 409` `publish_blocked` from `schedule` — the hub's publish gate, not a run failure: record the reason and move on (§7). Never hand-edit article content yourself.
- If `scripts/hub.sh selftest` aborts with a contract major mismatch (its own exit 1, message names the hub's and brain's major versions), stop the run — do not attempt any of the above; the fix is updating seobrain for the new contract, not retrying.
- The hub is unreachable when `scripts/hub.sh` exit code 3 is returned (5xx after retries). Save `state.json` and stop with `RESULT: hub unreachable — rerun with --resume`.
- Agent prompts are short: name the agent's inputs (RUN_DIR, SITE_ID, JOB_ID, MODE/LANG/NEEDED) and nothing else; the agent files carry the instructions.
