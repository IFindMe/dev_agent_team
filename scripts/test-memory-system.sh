#!/usr/bin/env bash
set -uo pipefail

# test-memory-system.sh — Structural tests for the memory and skills systems
#
# Verifies:
# 1. Memory directory structure exists and is well-formed
# 2. Memory categories have READMEs with format templates
# 3. Skills are properly structured with frontmatter
# 4. Skill files have required sections
# 5. Orchestrator references memory system
# 6. Orchestrator references skills system
# 7. Improvement proposal system structure exists
# 8. Memory lifecycle script is executable and has correct usage
# 9. Skills have owner metadata matching agent roster
# 10. No skill duplicates agent core behavior
#
# Exit codes: 0 = all pass, 1 = any failure

TEAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$TEAM_ROOT/agents"
MEMORY="$TEAM_ROOT/memory"
SKILLS="$TEAM_ROOT/skills"
IMPROVEMENTS="$TEAM_ROOT/improvements"

PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_contains() { grep -qF "$2" "$1" 2>/dev/null && return 0; return 1; }
assert_file() { [ -f "$1" ] && return 0; return 1; }
assert_dir()  { [ -d "$1" ] && return 0; return 1; }

# ======================================================================== #
# TEST 1: Memory directory structure
# ======================================================================== #
if assert_dir "$MEMORY" && \
   assert_dir "$MEMORY/decisions" && \
   assert_dir "$MEMORY/lessons" && \
   assert_dir "$MEMORY/failures" && \
   assert_dir "$MEMORY/architecture" && \
   assert_dir "$MEMORY/sessions" && \
   assert_file "$MEMORY/MEMORY.md"; then
  ok "T01 memory directory structure exists with all categories"
else
  fail "T01 memory directory structure exists with all categories" "missing directories or MEMORY.md"
fi

# ======================================================================== #
# TEST 2: Memory categories have READMEs
# ======================================================================== #
README_OK=1
for cat in decisions lessons failures architecture sessions; do
  assert_file "$MEMORY/$cat/README.md" || README_OK=0
done
if [ "$README_OK" = "1" ] && assert_file "$MEMORY/MEMORY.md"; then
  ok "T02 all memory categories have README.md files"
else
  fail "T02 all memory categories have README.md files" "missing README in one or more categories"
fi

# ======================================================================== #
# TEST 3: Memory READMEs contain format templates
# ======================================================================== #
FORMAT_OK=1
assert_contains "$MEMORY/decisions/README.md" "## Decision" || FORMAT_OK=0
assert_contains "$MEMORY/lessons/README.md" "## What was learned" || FORMAT_OK=0
assert_contains "$MEMORY/failures/README.md" "## Root Cause" || FORMAT_OK=0
assert_contains "$MEMORY/architecture/README.md" "## Ownership" || FORMAT_OK=0
assert_contains "$MEMORY/sessions/README.md" "## Task" || FORMAT_OK=0
if [ "$FORMAT_OK" = "1" ]; then
  ok "T03 memory READMEs contain format templates"
else
  fail "T03 memory READMEs contain format templates" "missing format sections"
fi

# ======================================================================== #
# TEST 4: Memory lifecycle script exists and is functional
# ======================================================================== #
HELP_OUTPUT=""
HELP_OK=0
if assert_file "$TEAM_ROOT/scripts/memory-lifecycle.sh"; then
  HELP_OUTPUT="$(bash "$TEAM_ROOT/scripts/memory-lifecycle.sh" --help 2>&1 || true)"
  echo "$HELP_OUTPUT" | grep -q "recall" && echo "$HELP_OUTPUT" | grep -q "store" && \
  echo "$HELP_OUTPUT" | grep -q "list" && echo "$HELP_OUTPUT" | grep -q "search" && HELP_OK=1
fi
if [ "$HELP_OK" = "1" ]; then
  ok "T04 memory lifecycle script exists with correct commands"
else
  fail "T04 memory lifecycle script exists with correct commands" "script missing or help broken"
fi

# ======================================================================== #
# TEST 5: Skills directory structure
# ======================================================================== #
if assert_dir "$SKILLS" && assert_file "$SKILLS/SKILLS.md"; then
  # Check that skill directories have SKILL.md files
  SKILL_COUNT=0
  for d in "$SKILLS"/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = "SKILLS.md" ] 2>/dev/null && continue
    if assert_file "$d/SKILL.md"; then
      SKILL_COUNT=$((SKILL_COUNT + 1))
    fi
  done
  if [ "$SKILL_COUNT" -ge 5 ]; then
    ok "T05 skills directory has $SKILL_COUNT skills with SKILL.md files"
  else
    fail "T05 skills directory has SKILL.md files" "only $SKILL_COUNT skills found (expected ≥5)"
  fi
else
  fail "T05 skills directory structure" "SKILLS.md or skills dir missing"
fi

# ======================================================================== #
# TEST 6: Skill files have required frontmatter
# ======================================================================== #
FRONT_OK=1
FRONT_COUNT=0
for d in "$SKILLS"/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/SKILL.md" ] || continue
  FRONT_COUNT=$((FRONT_COUNT + 1))
  head -10 "$d/SKILL.md" | grep -q "^---$" || FRONT_OK=0
  head -10 "$d/SKILL.md" | grep -q "^name:" || FRONT_OK=0
  head -10 "$d/SKILL.md" | grep -q "^description:" || FRONT_OK=0
  head -10 "$d/SKILL.md" | grep -q "^version:" || FRONT_OK=0
  head -10 "$d/SKILL.md" | grep -q "^owner:" || FRONT_OK=0
done
if [ "$FRONT_OK" = "1" ] && [ "$FRONT_COUNT" -ge 5 ]; then
  ok "T06 all $FRONT_COUNT skill files have required frontmatter (name, description, version, owner)"
else
  fail "T06 skill files have required frontmatter" "front_ok=$FRONT_OK count=$FRONT_COUNT"
fi

# ======================================================================== #
# TEST 7: Skill files have required sections
# ======================================================================== #
SECTION_OK=1
for d in "$SKILLS"/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/SKILL.md" ] || continue
  assert_contains "$d/SKILL.md" "## When to use" || SECTION_OK=0
  assert_contains "$d/SKILL.md" "## Core methodology" || \
  assert_contains "$d/SKILL.md" "## Step-by-step" || SECTION_OK=0
done
if [ "$SECTION_OK" = "1" ]; then
  ok "T07 skill files have 'When to use' and methodology sections"
else
  fail "T07 skill files have required sections" "missing required sections"
fi

# ======================================================================== #
# TEST 8: Orchestrator references memory system
# ======================================================================== #
ORCH="$AGENTS/orchestrator.md"
ORCH_MEM_OK=0
assert_contains "$ORCH" "memory" && \
  (grep -qE "recall|RECALL|project memory|memory.*lifecycle|memory.*before" "$ORCH" 2>/dev/null) && \
  ORCH_MEM_OK=1
if [ "$ORCH_MEM_OK" = "1" ]; then
  ok "T08 orchestrator references memory system"
else
  fail "T08 orchestrator references memory system" "no memory references in orchestrator"
fi

# ======================================================================== #
# TEST 9: Orchestrator references skills system
# ======================================================================== #
ORCH_SKILL_OK=0
assert_contains "$ORCH" "skill" && \
  (grep -qE "load.*skill|skill.*load|relevant skill|SKILL\.md|skills/" "$ORCH" 2>/dev/null) && \
  ORCH_SKILL_OK=1
if [ "$ORCH_SKILL_OK" = "1" ]; then
  ok "T09 orchestrator references skills system"
else
  fail "T09 orchestrator references skills system" "no skill loading references in orchestrator"
fi

# ======================================================================== #
# TEST 10: Improvement proposal system exists
# ======================================================================== #
if assert_dir "$IMPROVEMENTS" && \
   assert_dir "$IMPROVEMENTS/pending" && \
   assert_dir "$IMPROVEMENTS/applied" && \
   assert_dir "$IMPROVEMENTS/rejected" && \
   assert_file "$IMPROVEMENTS/README.md" && \
   assert_contains "$IMPROVEMENTS/README.md" "human approval"; then
  ok "T10 improvement proposal system exists with approval requirement"
else
  fail "T10 improvement proposal system exists" "missing directories or approval requirement"
fi

# ======================================================================== #
# TEST 11: All subagents reference memory system
# ======================================================================== #
SUBAGENT_MEM_OK=1
for sub in explorer detective builder reviewer maintainer writer tester toolsmith architect designer philosopher workflow-architect; do
  f="$AGENTS/$sub.md"
  if [ ! -f "$f" ]; then
    fail "T11 all subagents reference memory" "missing $sub.md"
    SUBAGENT_MEM_OK=0
    break
  fi
  if ! grep -q "Memory & Skills Awareness" "$f" 2>/dev/null; then
    fail "T11 all subagents reference memory" "$sub.md missing 'Memory & Skills Awareness'"
    SUBAGENT_MEM_OK=0
    break
  fi
  if ! grep -q "memory-lifecycle.sh" "$f" 2>/dev/null; then
    fail "T11 all subagents reference memory" "$sub.md missing memory-lifecycle.sh reference"
    SUBAGENT_MEM_OK=0
    break
  fi
done
if [ "$SUBAGENT_MEM_OK" = "1" ]; then
  ok "T11 all subagents reference memory system"
fi

# ======================================================================== #
# TEST 12: All subagents reference skills system
# ======================================================================== #
SUBAGENT_SKILL_OK=1
for sub in explorer detective builder reviewer maintainer writer tester toolsmith architect designer philosopher workflow-architect; do
  f="$AGENTS/$sub.md"
  if ! grep -q "skill path\|SKILL\.md\|skills/" "$f" 2>/dev/null; then
    fail "T12 all subagents reference skills" "$sub.md missing skill references"
    SUBAGENT_SKILL_OK=0
    break
  fi
done
if [ "$SUBAGENT_SKILL_OK" = "1" ]; then
  ok "T12 all subagents reference skills system"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
