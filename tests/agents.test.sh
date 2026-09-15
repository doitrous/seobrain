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
grep -q 'introduction' .claude/agents/writer.md || { echo "FAIL: writer must produce introduction"; exit 1; }
grep -q 'secondaryKeywords' .claude/agents/writer.md || { echo "FAIL: writer must produce secondaryKeywords"; exit 1; }
grep -q 'searchIntent' .claude/agents/writer.md || { echo "FAIL: writer must produce searchIntent"; exit 1; }
grep -q 'references' .claude/agents/writer.md || { echo "FAIL: writer must produce references"; exit 1; }
grep -qF '"sections"' .claude/agents/writer.md || { echo "FAIL: writer must emit sections in the draft"; exit 1; }
grep -qF 'MODE=refresh' .claude/skills/weekly-run/SKILL.md || { echo "FAIL: refresh jobs must be dispatched with MODE=refresh"; exit 1; }
grep -qF '`refresh`' .claude/agents/writer.md || { echo "FAIL: writer must have a refresh procedure"; exit 1; }
grep -qF 'hub.sh articles' .claude/agents/writer.md || { echo "FAIL: writer refresh must fetch the published article"; exit 1; }
grep -qF 'articles)' scripts/hub.sh || { echo "FAIL: hub.sh must expose the articles command"; exit 1; }
grep -qF 'checklist_gap' .claude/agents/writer.md || { echo "FAIL: writer revise must handle checklist_gap"; exit 1; }
grep -qF 'checklist.json' .claude/agents/localizer.md || { echo "FAIL: localizer must read sections from checklist.json"; exit 1; }
! grep -rq sectionsOmitted seo-rules.md .claude || { echo "FAIL: sectionsOmitted is gone; sections comes from the writer"; exit 1; }
grep -q 'hub.sh step <JOB_ID> checklist' .claude/agents/auditor.md || { echo "FAIL: auditor must post the checklist step"; exit 1; }
grep -q 'checklist_gap' .claude/agents/auditor.md || { echo "FAIL: auditor must define checklist_gap"; exit 1; }
grep -qF 'checklist: posted' .claude/agents/auditor.md || { echo "FAIL: auditor RESULT must report checklist: posted"; exit 1; }
for k in publication_dates translation_status doctor_approval seo_approval publication_approval; do
  grep -qF "$k" .claude/agents/auditor.md || { echo "FAIL: auditor must name pipeline-evidenced item $k"; exit 1; }
done
grep -q 'readiness' .claude/agents/auditor.md || { echo "FAIL: auditor must report readiness"; exit 1; }
grep -q 'introduction' .claude/agents/localizer.md || { echo "FAIL: localizer must translate introduction"; exit 1; }
grep -q 'sections' .claude/agents/localizer.md || { echo "FAIL: localizer must re-point sections"; exit 1; }
grep -q 'primaryKeyword' .claude/agents/topic-scout.md || { echo "FAIL: scout must avoid primaryKeyword collisions"; exit 1; }
grep -qF 'contentKind' seo-rules.md || { echo "FAIL: seo-rules must gate medical rules on contentKind"; exit 1; }
grep -qF 'Arabic ≤ 70' seo-rules.md || { echo "FAIL: seo-rules Arabic meta title ceiling must be 70"; exit 1; }
grep -qF 'hub.sh articles' seo-rules.md || { echo "FAIL: seo-rules refresh must name hub.sh articles"; exit 1; }
for k in named_author education_not_diagnosis no_guarantees publication_approval; do
  grep -qF "$k" seo-rules.md || { echo "FAIL: seo-rules must list checklist item $k"; exit 1; }
done
for k in who_may_benefit who_may_not_be_suitable risks_limitations when_to_seek_help; do
  grep -qF "$k" seo-rules.md || { echo "FAIL: seo-rules must list safety section $k"; exit 1; }
done
echo "agents.test.sh: all passed"
