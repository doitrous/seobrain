#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
f=.claude/skills/weekly-run/SKILL.md
[ -f "$f" ] || { echo "FAIL: skill missing"; exit 1; }
grep -q '^name: weekly-run$' "$f" || { echo "FAIL: skill name"; exit 1; }
for a in topic-scout researcher writer auditor localizer; do grep -q "$a" "$f" || { echo "FAIL: skill must dispatch $a"; exit 1; }; done
for s in 'hub.sh plan' 'hub.sh run-start' 'hub.sh create-job' 'hub.sh article' 'hub.sh schedule' 'hub.sh run-finish' 'state.json' '--resume' 'at most 4' 'Agent failure policy' '"failed"' 'translationsPending' 'LOCALIZE_DAILY_MAX' 'topicId' 'skippedDuplicates' 'exit code 3' 'queuedTopics[].id' 'checklist' 'keyword_taken' 'refresh' 'refreshOf' 'MODE=refresh' 'checklist: posted' 'hub.sh articles' 'hubRole' 'slug' 'forcedTopics' 'MODE=refine'; do
  grep -qF -- "$s" "$f" || { echo "FAIL: skill must mention '$s'"; exit 1; }
done
# contract 1.9.0: a brief-based job's topic.json must copy the pinned slug the same way it already copies hubRole
grep -qF -- '`hubRole` **and `slug`** are copied from the brief' "$f" || { echo "FAIL: skill must copy slug from the brief into topic.json alongside hubRole"; exit 1; }
grep -qF -- 'omit `hubRole`/`slug` entirely for a scout-discovered or queued-topic job' "$f" || { echo "FAIL: skill must omit slug (like hubRole) for non-brief jobs"; exit 1; }
node -e 'const s=require("./.claude/settings.json"); const a=s.permissions.allow; for (const need of ["Bash(scripts/hub.sh:*)","Bash(scripts/suggest.sh:*)","WebSearch","WebFetch","Agent","Read","Write"]) if(!a.includes(need)) {console.error("FAIL: settings missing "+need); process.exit(1)}'
node -e 'const s=require("./.claude/settings.json"); const d=s.permissions.deny; if(!Array.isArray(d)||!d.includes("Read(./.env)")) {console.error("FAIL: settings.json permissions.deny must include Read(./.env)"); process.exit(1)}'
grep -q 'claude-opus-4-8' CLAUDE.md || { echo "FAIL: CLAUDE.md must state the orchestrator model"; exit 1; }
echo "skill.test.sh: all passed"
