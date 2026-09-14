# seo-brain

Weekly SEO article producer. Runs in Omar's own Claude Code (Max subscription). Opus 4.8 orchestrates; Sonnet 4.6 agents research, write, audit, localize; everything is posted to the hub (`seo-hub`), which holds the review window and publishes.

## Setup
1. `cp .env.example .env` and set `HUB_URL` (e.g. `https://seo.doitrous.com`) and `HUB_TOKEN` (the hub's `HUB_TOKEN`).
2. `scripts/hub.sh selftest` prints the current week (Monday) if the hub is reachable.
3. `bash tests/hub.test.sh && bash tests/agents.test.sh && bash tests/skill.test.sh`.
4. Trust the workspace once: run `claude` interactively in this directory and accept the trust dialog. Until then `claude -p` ignores `.claude/settings.json` (it prints "Ignoring N permissions.allow entries") and every tool call in the unattended run is denied.

## Run manually
```bash
claude --model claude-opus-4-8 -p "/weekly-run"            # full run
claude --model claude-opus-4-8 -p "/weekly-run --site aspects-clinica"
claude --model claude-opus-4-8 -p "/weekly-run --dry-run"  # choose topics only, create nothing
claude --model claude-opus-4-8 -p "/weekly-run --resume"   # continue today's run after an interruption
```
Or interactively: `claude --model claude-opus-4-8` then type `/weekly-run`.

## Schedule (Friday 07:00, this Mac)
`scripts/install-schedule.sh` installs a launchd agent that runs `scripts/weekly.sh`. The Mac must be awake at 07:00 (System Settings → Energy, or `pmset repeat wakeorpoweron F 06:55:00` once with admin rights) **and Omar must be logged in** — the job runs in the launchd `gui` domain and needs the logged-in session's Claude Code keychain login. Logs: `runs/<date>/run.log`. Uninstall: `scripts/install-schedule.sh --uninstall`.

Alternative when the Mac cannot be awake: a Claude Code cloud routine (`/schedule` in Claude Code) on cron `0 7 * * 5` Africa/Cairo running `/weekly-run` from this repo, with `HUB_URL`/`HUB_TOKEN` as routine environment variables. Same skill, same agents.

## What a run does
plan → topics (refresh queue first, then user queue, then topic-scout) → jobs → researcher → writer (outline, draft with introduction/secondary keywords/OG/references, image brief) → auditor (hub deterministic audit + judgment + the 20-item medical checklist) → primary article → localizer per extra language → schedule → run summary. The hub re-audits at the end of the review window and only then publishes and stamps the reviewer dates. State: `runs/<date>/state.json`; per-job files under `runs/<date>/job-<id>/`.

## Files
- `.claude/skills/weekly-run/SKILL.md` — the orchestrator procedure
- `.claude/agents/*.md` — the five agents (`model: claude-sonnet-4-6`)
- `seo-rules.md` — rules, payload contracts, schema/hreflang templates, audit codes
- `scripts/hub.sh` — hub API wrapper (`plan, run-start, run-finish, create-job, step, audit, article, articles, schedule, jobs, selftest`)
- `scripts/suggest.sh` — Google Autocomplete

## Troubleshooting
- `hub.sh` prints a 4xx body: an agent produced a payload that violates the contract (see `seo-rules.md` → Payload contracts). The orchestrator re-dispatches that agent with the error.
- `hub.sh` exit 3: hub unreachable.
- A job ends in `needs_review`: it failed the audit three times; open it in the hub dashboard, fix, re-run audit there.
- `hub unreachable`: check `HUB_URL`, the hub's `HUB_TOKEN`, then re-run with `--resume`.
- hreflang maps list the site's planned languages; the hub trims each map to the languages that actually shipped before it publishes, so a failed localization drops out there and the receiver only ever sees real versions. The draft-time `hreflang_reciprocal` warning is expected and never blocks.
- A job that ends `failed` or `needs_review` still counts toward the site's weekly cadence; there is no automatic top-up that week.
- `create-job` returns 409 `keyword_taken`: the site already covers that keyword in that language. Not a bug — the run skips the topic and asks for a replacement.
- A job sits in `needs_review` after its window closed: it failed the hub's publish-time audit. The job's `error` lists the failing check codes; the dashboard shows each with its fix text.
- `schedule` returns 409 `publish_blocked`: the hub's publish gate is holding the job — a global or site pause, its draft-only ramp, or approval required (see seohub `docs/contracts/README.md`). Not a bug — the run logs the reason and moves on; the job publishes once the gate clears or Omar approves it in the dashboard.
- `scripts/hub.sh selftest` now also warns (minor/patch contract drift, safe to ignore) or aborts (a major contract mismatch) based on `GET /api/contracts/version` vs. `BRAIN_CONTRACT_MAJOR` in `scripts/hub.sh`. The hub also exposes brain-token `PATCH /api/sites/:slug` and `PATCH /api/sites/:slug/settings` for site config; this repo does not call either yet.
