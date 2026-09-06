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
