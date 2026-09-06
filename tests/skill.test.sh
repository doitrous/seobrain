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
