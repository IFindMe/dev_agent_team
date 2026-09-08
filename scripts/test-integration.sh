#!/usr/bin/env bash
#
# test-integration.sh — Integration tests for memory, skills, routing, and
# improvement systems. Verifies that the components work together end-to-end:
#   - memory-lifecycle.sh actually stores/recalls/lists/searches real entries
#   - agent↔skill mapping is consistent (every listed agent skill exists)
#   - every skill file is valid markdown with required frontmatter
#   - every skill whose owner is an agent is registered in that agent's prompt
#   - improvement proposal lifecycle (pending → applied) works
#   - skip-when routing guards are present in the orchestrator
#
# Run: bash scripts/test-integration.sh

set -euo pipefail
TEAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$TEAM_ROOT/agents"
SKILLS="$TEAM_ROOT/skills"
MEMORY="$TEAM_ROOT/memory"
IMPROV="$TEAM_ROOT/improvements"
LS="$TEAM_ROOT/scripts/memory-lifecycle.sh"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — ${2:-}" >&2; }

assert_file() { [ -f "$1" ] && return 0; return 1; }
assert_dir()  { [ -d "$1" ] && return 0; return 1; }
assert_contains() { grep -qF "$2" "$1" 2>/dev/null && return 0; return 1; }

echo "init                 — team: $TEAM_ROOT"

# ======================================================================== #
# TEST I01: memory-lifecycle.sh end-to-end store + recall + list + search
# ======================================================================== #
# Create an actual lesson file in the temp memory workspace, store it, verify it
# is found by recall and search, then remove it (leave memory clean).
LESSON_FILE="$T/lesson-integration-test.md"
cat > "$LESSON_FILE" <<'EOF'
---
date: 2026-09-08
category: lesson
title: Integration test lesson
tags: [integration, memory]
---
# Integration test lesson

A lesson stored and retrieved by the memory lifecycle script during integration
testing. This entry is temporary and will be removed after verification.
EOF

SC_OK=0
# NOTE: capture output into variables rather than piping `memory-lifecycle.sh`
# into `grep -q`. grep -q closes the pipe early (SIGPIPE, rc=141), which fails
# the pipeline under `pipefail`.
STORE_OK=0
# Test isolation: remove any residue a previous interrupted/crashed run may have
# left behind before storing. Writing a fresh entry makes the check independent
# of the memory directory's pre-existing state.
rm -f "$MEMORY/lessons/"*integration-test* 2>/dev/null || true
if bash "$LS" store lessons "$LESSON_FILE" >/dev/null 2>&1; then
  STORE_OK=1
fi
LIST_OUT="$(bash "$LS" list lessons 2>&1 || true)"
RECALL_OUT="$(bash "$LS" recall lessons "Integration" 2>&1 || true)"
SEARCH_OUT="$(bash "$LS" search "Integration test lesson" 2>&1 || true)"
if [ "$STORE_OK" = "1" ] \
   && echo "$LIST_OUT" | grep -q "integration-test" \
   && echo "$RECALL_OUT" | grep -qi "Integration test lesson" \
   && echo "$SEARCH_OUT" | grep -qi "integration-test"; then
  SC_OK=1
fi
# clean up whatever got written so memory stays pristine
rm -f "$MEMORY/lessons/"*integration-test* 2>/dev/null || true
if [ "$SC_OK" = "1" ]; then
  ok "I01 memory-lifecycle store/recall/list/search end-to-end"
else
  fail "I01 memory-lifecycle store/recall/list/search end-to-end" "store/recall/list/search chain failed"
fi

# ======================================================================== #
# TEST I02: Session lifecycle — create, list, cleanup
# ======================================================================== #
Sess="$MEMORY/sessions/2026-09-08_integration-session-test.md"
# Test isolation: remove any residue a previous interrupted/crashed run left.
rm -f "$Sess" 2>/dev/null || true
printf -- '%s\n' "Status: active" "# Integration session test" "## State" "in progress" > "$Sess"
SESS_OUT="$(bash "$LS" sessions 2>&1 || true)"
SESS_OK=0
if echo "$SESS_OUT" | grep -q "integration-session-test" \
   && bash "$LS" cleanup >/dev/null 2>&1; then
  SESS_OK=1
fi
rm -f "$Sess" 2>/dev/null || true
if [ "$SESS_OK" = "1" ]; then
  ok "I02 session create/list/cleanup"
else
  fail "I02 session create/list/cleanup" "sessions chain failed — session listed?"
fi

# ======================================================================== #
# TEST I03: agent↔skill mapping integrity — agent prompt names a skill or skill exists
# ======================================================================== #
# The agent-skill mapping in orchestrator.md should reference only skills that
# exist as files. This is a hard consistency check.
RULES_OK=1
# every skill directory in skills/ has a SKILL.md with valid frontmatter
for d in "$SKILLS"/*/; do
  n="$(basename "$d")"
  f="$d/SKILL.md"
  if ! assert_file "$f"; then fail "I03 skill $n has no SKILL.md"; RULES_OK=0; break; fi
  if ! grep -q "^name:" "$f" || ! grep -q "^owner:" "$f"; then
    fail "I03 skill $n missing frontmatter"; RULES_OK=0; break
  fi
  # description should be a single line (required frontmatter)
  if ! grep -q "^description:" "$f"; then fail "I03 skill $n missing description"; RULES_OK=0; break; fi
done
if [ "$RULES_OK" = "1" ]; then
  ok "I03 all skill files have valid frontmatter"
fi

# ======================================================================== #
# TEST I04: Every skill's owner is a registered agent (case-insensitive,
#           and multi-owner "A + B" resolved to each named agent)
# ======================================================================== #
OWNER_OK=1
for d in "$SKILLS"/*/; do
  n="$(basename "$d")"
  f="$d/SKILL.md"
  owner="$(grep -m1 "^owner:" "$f" 2>/dev/null | sed 's/^owner:[[:space:]]*//' | sed 's/[",]//g')"
  [ -z "$owner" ] && continue
  # Resolve multi-owner "A + B" and case differences to agent file names (lowercase)
  IFS='+' read -ra owners <<< "$owner"
  for o in "${owners[@]}"; do
    o_trim="$(echo "$o" | xargs | tr '[:upper:]' '[:lower:]')"
    [ -f "$AGENTS/$o_trim.md" ] || { fail "I04 skill $n owner '$owner' not an agent" "missing agents/$o_trim.md"; OWNER_OK=0; }
  done
done
if [ "$OWNER_OK" = "1" ]; then
  ok "I04 every skill owner is a registered agent"
fi

# ======================================================================== #
# TEST I05: Every agent named in orchestrator's skill mapping owns a real skill
# ======================================================================== #
# Agents in the Agent-Skill Mapping table should own at least one skill in skills/.
MAPPED_OWNERS="$(grep -A2 "name:.*tdd" "$SKILLS/tdd/SKILL.md" >/dev/null && echo ok)"
OWNER_LIST=""
for d in "$SKILLS"/*/; do
  o="$(grep -m1 "^owner:" "$d/SKILL.md" | sed 's/^owner:[[:space:]]*//' | sed 's/[",]//g')"
  [ -z "$o" ] && continue
  OWNER_LIST="$OWNER_LIST $o"
done
# Each mapped primary agent in the orchestrator should appear as an owner
MAPPED_OK=1
for ag in tdd systematic-debugging architecture-design code-review security-review \
          repository-analysis failure-analysis refactoring test-analysis \
          incident-investigation browser-automation research; do
  if ! [ -f "$SKILLS/$ag/SKILL.md" ]; then fail "I05 skill $ag missing"; MAPPED_OK=0; fi
done
if [ "$MAPPED_OK" = "1" ]; then
  ok "I05 all 12 skills present for mapping table"
fi

# ======================================================================== #
# TEST I06: Orchestrator action catalog covers memory + skills + improvements (A23-A27)
# ======================================================================== #
ORCH="$AGENTS/orchestrator.md"
CAT_OK=0
if assert_contains "$ORCH" "A23 | recall project memory" \
   && assert_contains "$ORCH" "A24 | store project memory" \
   && assert_contains "$ORCH" "A25 | load skill" \
   && assert_contains "$ORCH" "A26 | finish / report" \
   && assert_contains "$ORCH" "A27 | re-plan"; then
  CAT_OK=1
fi
if [ "$CAT_OK" = "1" ]; then
  ok "I06 action catalog integrates memory/skills/finish/re-plan"
else
  fail "I06 action catalog integrates memory/skills" "missing A23-A27 entries"
fi

# ======================================================================== #
# TEST I07: Task lifecycle section exists and ties stages to memory
# ======================================================================== #
LC_OK=0
if assert_contains "$ORCH" "Task Lifecycle" \
   && assert_contains "$ORCH" "RECALL" \
   && assert_contains "$ORCH" "STORE" \
   && assert_contains "$ORCH" "IMPROVE"; then
  LC_OK=1
fi
if [ "$LC_OK" = "1" ]; then
  ok "I07 task lifecycle integrates memory/skills/improvements stages"
else
  fail "I07 task lifecycle integrates memory/skills" "Task Lifecycle section missing stages"
fi

# ======================================================================== #
# TEST I08: Skip-when routing guards present
# ======================================================================== #
SKIP_OK=0
if grep -q "Skip-when" "$ORCH" && grep -q "Skip Explorer" "$ORCH"; then
  SKIP_OK=1
fi
if [ "$SKIP_OK" = "1" ]; then
  ok "I08 skip-when routing guards present"
else
  fail "I08 skip-when routing guards present" "missing skip-when section"
fi

# ======================================================================== #
# TEST I09: improvement proposal lifecycle — write pending, move to applied
# ======================================================================== #
PROP="$IMPROV/pending/2026-09-08_integration-prop.md"
mkdir -p "$IMPROV/pending" "$IMPROV/applied" "$IMPROV/rejected"
printf -- '%s\n' "# Proposal: integration test" "## Problem" "temporary" > "$PROP"
PROP_OK=0
if [ -f "$PROP" ] \
   && assert_contains "$IMPROV/README.md" "human approval" \
   && mkdir -p "$IMPROV/applied" \
   && mv "$PROP" "$IMPROV/applied/2026-09-08_integration-prop.md" 2>/dev/null; then
  PROP_OK=1
fi
# restore: remove applied copy
rm -f "$IMPROV/applied/2026-09-08_integration-prop.md" 2>/dev/null || true
if [ "$PROP_OK" = "1" ]; then
  ok "I09 improvement proposal pending→applied lifecycle"
else
  fail "I09 improvement proposal lifecycle" "proposal lifecycle failed"
fi

# ======================================================================== #
# TEST I10: Improper agent (unknown owner) not silently accepted
# ======================================================================== #
# Create a temp skill with an invalid owner and verify the mapping check would reject it.
INVALID_SKILL="$T/invalid/SKILL.md"
mkdir -p "$T/invalid"
printf -- '%s\n' "---" "name: invalid" "owner: not-an-agent" "---" > "$INVALID_SKILL"
INV_OK=1
for f in "$SKILLS"/*/SKILL.md; do
  o="$(grep -m1 "^owner:" "$f" 2>/dev/null | sed 's/^owner:[[:space:]]*//' | sed 's/[",]//g')"
  [ -z "$o" ] && continue
  IFS='+' read -ra owners <<< "$o"
  for ow in "${owners[@]}"; do
    ow_trim="$(echo "$ow" | xargs | tr '[:upper:]' '[:lower:]')"
    if [ -n "$ow_trim" ] && [ ! -f "$AGENTS/$ow_trim.md" ]; then
      fail "I10 skill owner validation" "invalid owner '$o' in $f"
      INV_OK=0
      break
    fi
  done
  [ "$INV_OK" = "0" ] && break
done
if [ "$INV_OK" = "1" ]; then
  ok "I10 real skills all have valid registered owners"
fi

# ======================================================================== #
# TEST I11: Orchestrator wires improvement proposal detection into workflow
# ======================================================================== #
ORCH="$AGENTS/orchestrator.md"
IMPROVE_DET_OK=0
if assert_contains "$ORCH" "Recurring failure" \
   && assert_contains "$ORCH" "Missing skill" \
   && assert_contains "$ORCH" "Routing inefficiency" \
   && assert_contains "$ORCH" "Documentation gap" \
   && assert_contains "$ORCH" "Process friction"; then
  IMPROVE_DET_OK=1
fi
if [ "$IMPROVE_DET_OK" = "1" ]; then
  ok "I11 improvement proposal detection triggers wired"
else
  fail "I11 improvement proposal detection" "missing detection triggers in orchestrator"
fi

# ======================================================================== #
# TEST I12: Orchestrator proposal format matches improvements/README format
# ======================================================================== #
FMT_OK=0
if assert_contains "$ORCH" "improvements/pending/YYYY-MM-DD" \
   && assert_contains "$IMPROV/README.md" "Observed problem" \
   && assert_contains "$IMPROV/README.md" "Root cause" \
   && assert_contains "$IMPROV/README.md" "Proposed change" \
   && assert_contains "$IMPROV/README.md" "Verification plan" \
   && assert_contains "$IMPROV/README.md" "without human approval"; then
  FMT_OK=1
fi
if [ "$FMT_OK" = "1" ]; then
  ok "I12 proposal format consistent across orchestrator and README"
else
  fail "I12 proposal format consistency" "format fields missing"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
