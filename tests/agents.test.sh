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
