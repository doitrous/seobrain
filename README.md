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
