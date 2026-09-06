---
name: weekly-run
description: Produce this week's SEO articles for every enabled site — plan from the hub, dispatch Sonnet 4.6 agents to research, write, audit and localize, post every step to the hub, and schedule the articles. Use for the Friday run or a manual run.
---

# Weekly run (orchestrator)

You are the orchestrator. You never write article text yourself; you dispatch the agents and keep state. Model: this session runs as Opus 4.8 (`claude --model claude-opus-4-8`).

Arguments: `--resume` (continue today's run from `state.json`), `--site <slug>` (only that site), `--dry-run` (plan and choose topics, create no jobs).

## 0. Setup
- Run `date +%F`; that is DATE. RUN_DIR is `runs/<date>`. Run `mkdir -p RUN_DIR`.
- Without `--resume`: run `scripts/hub.sh plan RUN_DIR/plan.json` (the second argument is the output file; never use a shell redirect, pipe, `;` or `bash` prefix with `scripts/hub.sh` — only the plain form is permitted in the unattended run, for you and for every agent). For each site in `plan.sites` write `RUN_DIR/site-<site.id>.json` containing the whole plan entry (`site`, `neededThisWeek`, `queuedTopics`, `publishedTitles`, `existingArticles`, `bannedPhrases`).
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
- Take up to `neededThisWeek` entries from `queuedTopics` (they are user-supplied). Each `queuedTopics[]` row has `id, title, keyword, market, lang, source`: set `topicId = queuedTopics[].id`, and take `lang`, `market`, `keyword`, `title` from that same row (matched by topicId). Set `intent` to `informational`, unless the keyword clearly signals cost or comparison — then use `commercial`. Write these to topic.json the same way as a discovered topic.
- If still short by `k`, dispatch **topic-scout** with RUN_DIR, SITE_ID, `NEEDED=k`; read `site-<id>-topics.json`.
- `--dry-run`: print the chosen topics per site and stop here; no `run-start` was called and no `state.json` was written (see §0) — only `plan.json` exists.
- Create jobs: for a queued topic write `{ "siteId", "topicId" }`, for a discovered one `{ "siteId", "topic": {…} }`, to `RUN_DIR/job-tmp.json`. Run `scripts/hub.sh create-job RUN_DIR/job-tmp.json`; it prints the job JSON — JOB_ID is its `id`. If the returned job's `state` is anything other than `planned`, or its `weekOf` differs from `plan.weekOf`, the hub matched an older job to this topic: do not use that job and do not attach steps to it — ask topic-scout for one replacement topic (once) instead, and note the skipped title in the summary under `skippedDuplicates`. Otherwise run `mkdir -p RUN_DIR/job-<JOB_ID>`, write `topic.json` there (title, keyword, market, lang, intent, source), and add to `state.jobs[JOB_ID] = { "siteId", "topicId" (queued topics only), "title", "lang", "languages": site.languages, "steps": {}, "auditLoops": 0, "status": "planned" }`.
- Save `state.json` after every job creation and after every step below.

## 2. Research
For every job without `steps.research`: dispatch **researcher** (`RUN_DIR`, `SITE_ID`, `JOB_ID`). On `RESULT: ok` set `steps.research = "done"`. On fail apply the failure policy.

## 3. Write
For every job with research done and no `steps.draft`: dispatch **writer** with `MODE=write`. On ok set `steps.outline`, `steps.draft`, `steps.image_brief` to `"done"`. On fail apply the failure policy.

## 4. Audit loop
For every job with a draft and no passing audit:
- Dispatch **auditor**. Read `RUN_DIR/job-<JOB_ID>/audit.json`. On fail apply the failure policy.
- If `pass`: set `steps.audit = "pass"`.
- Else increment `auditLoops`; if `auditLoops <= 2` dispatch **writer** with `MODE=revise`, then audit again; if `auditLoops > 2` set `status = "needs_review"` and move on (the hub shows the job in `drafted` with the audit issues; Omar can fix it in the dashboard).

## 5. Primary article
For every job with `steps.audit = "pass"` and no `steps.article`: run `scripts/hub.sh article <JOB_ID> RUN_DIR/job-<JOB_ID>/draft.json`, then set `steps.article = "done"`.

## 6. Localize
For every such job and every language in `languages` other than the job's `lang`: dispatch **localizer** with `LANG`. On ok set `steps["localize:<LANG>"] = "done"`. On fail apply the failure policy (localizer exception).

## 7. Schedule
For every job with `steps.article = "done"` and every language in `languages` other than the job's `lang` has `steps["localize:<LANG>"]` equal to `"done"` or `"failed"`: run `scripts/hub.sh schedule <JOB_ID>`, set `status = "scheduled"`.

## 8. Finish
Write `RUN_DIR/summary.json`:
`{ "weekOf", "sites": [{ "siteId", "name", "needed", "created", "scheduled", "needsReview": [jobIds], "failed": [{ "jobId", "error" }], "missingLanguages": [{ "jobId", "lang" }], "skippedDuplicates": [titles] }], "jobs": <count>, "durationMinutes" }`
`missingLanguages` is derived from `steps["localize:<LANG>"] = "failed"`; `failed` from `status = "failed"`; `needsReview` from `status = "needs_review"`; `skippedDuplicates` from the replacement-topic titles skipped in §1.
Then run `scripts/hub.sh run-finish <RUN_ID> RUN_DIR/summary.json`. Print the summary as a short table.

## Rules
- Never skip a hub post to save time; the dashboard is the record.
- If `scripts/hub.sh` fails on a 4xx, read the error body: it is a contract violation in the agent's output (missing key, bad lang). Re-dispatch the responsible agent at most once with the error body quoted; on a second 4xx apply the failure policy. A 4xx from `create-job`, `schedule` or `run-finish` has no agent: mark the job `failed` with the body (for `run-finish`, print the error and stop). Never hand-edit article content yourself.
- The hub is unreachable when `scripts/hub.sh` exit code 3 is returned (5xx after retries). Save `state.json` and stop with `RESULT: hub unreachable — rerun with --resume`.
- Agent prompts are short: name the agent's inputs (RUN_DIR, SITE_ID, JOB_ID, MODE/LANG/NEEDED) and nothing else; the agent files carry the instructions.
