# seo-brain

The weekly article producer for Omar's sites. The hub (`seo-hub`, Next.js) stores everything and publishes; this repo only generates.

- Orchestrator: `/weekly-run` skill, run as `claude --model claude-opus-4-8 -p "/weekly-run"` from this directory (Max subscription, no API key).
- Agents (`.claude/agents/`, all `claude-sonnet-4-6`): topic-scout, researcher, writer, auditor, localizer. They read `seo-rules.md` first and talk to the hub only through `scripts/hub.sh`.
- Config: `.env` with `HUB_URL`, `HUB_TOKEN` (see `.env.example`). Run artifacts: `runs/<date>/` (git-ignored).
- Contracts: payload shapes in `seo-rules.md` → "Payload contracts"; hub endpoints in `scripts/hub.sh` usage.
- Tests: `bash tests/hub.test.sh && bash tests/agents.test.sh && bash tests/skill.test.sh`.
- Never add an Anthropic SDK or API key to this repo.
- **`seo-rules.md` is the SEO structure/rulebook of record — keep it current.** Any SEO-flow change (new hub contract version, `pageType`, audit code, payload field, writer mode, or SEO practice we adopt) updates `seo-rules.md` in the same change, reconciled against `seo-hub/docs/contracts/README.md`. Don't let the rulebook drift from what the hub does.
