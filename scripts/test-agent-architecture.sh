#!/usr/bin/env bash
set -uo pipefail

# test-agent-architecture.sh — Structural tests for the adaptive, evidence-driven,
# repository-aware, cost-aware architecture upgrade.
#
# What this verifies: the AGENT DEFINITIONS actually contain the required
# architecture elements (decision loop, complexity estimation, action catalog,
# evidence-state model, adaptive planning, failure recovery, process quality,
# cost awareness, quality gates, stop conditions, repository intelligence).
#
# What this does NOT verify: live runtime behavior of the agent team.
# The 12 runtime evaluation scenarios live in docs/EVALUATION_SCENARIOS.md and
# require an interactive opencode session to execute and score.
#
# Exit codes: 0 = all pass, 1 = any failure (PASS/FAIL per test, summary at end)
# Conventions follow test-repo-bootstrap.sh / verify-permission-patterns.sh:
#   PASS/FAIL echo, deterministic assertions, no external deps beyond bash + grep.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AGENTS="$TEAM_ROOT/agents"
DOCS="$TEAM_ROOT/docs"
SCRIPTS="$TEAM_ROOT/scripts"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_contains() { # <file> <pattern> → 0 if file contains pattern
  grep -qF "$2" "$1" 2>/dev/null && return 0; return 1
}

ORCH="$AGENTS/orchestrator.md"

# ======================================================================== #
# TEST 1: Orchestrator is a decision loop (not a linear pipeline)
# ======================================================================== #
if assert_contains "$ORCH" "UNDERSTAND → ESTIMATE → LOAD CONTEXT → CHOOSE ACTION" \
   && assert_contains "$ORCH" "adaptive loop" \
   && assert_contains "$ORCH" "You are a decision engine, not a pipeline"; then
  ok "T01 orchestrator core behavior is an adaptive decision loop"
else
  fail "T01 orchestrator core behavior is an adaptive decision loop" "loop markers missing"
fi

# ======================================================================== #
# TEST 2: Task complexity estimation (ESTIMATE → EXECUTE → EXPAND)
# ======================================================================== #
if assert_contains "$ORCH" "## Task Complexity Estimation" \
   && assert_contains "$ORCH" "ESTIMATE → EXECUTE → EXPAND" \
   && assert_contains "$ORCH" "scope:            small | medium | large"; then
  ok "T02 complexity estimation present"
else
  fail "T02 complexity estimation present" "missing section or ESTIMATE→EXECUTE→EXPAND"
fi

# ======================================================================== #
# TEST 3: Action catalog / tool cards
# ======================================================================== #
if assert_contains "$ORCH" "## Action Catalog (choose the next best action)" \
   && assert_contains "$ORCH" "| # | Action | Purpose | Inputs | Outputs | Read-only | Cost | Risk | Prereq | Failure modes |" \
   && assert_contains "$ORCH" "A1 | inspect repository" \
   && grep -qE "A[0-9]+ . re-plan" "$ORCH"; then
  ok "T03 action catalog with tool cards present"
else
  fail "T03 action catalog with tool cards present" "catalog/table markers missing"
fi

# ======================================================================== #
# TEST 4: Evidence-first state model (all 9 fields)
# ======================================================================== #
STATE_OK=1
for field in "goal:" "hypothesis:" "evidence:" "actions_taken:" "result:" \
             "verification:" "confidence:" "remaining_unknowns:" "recommended_next_action:"; do
  assert_contains "$ORCH" "$field" || STATE_OK=0
done
if [ "$STATE_OK" = "1" ] && assert_contains "$ORCH" "## Evidence-First State and Handoff Discipline"; then
  ok "T04 evidence-state model with 9 fields present"
else
  fail "T04 evidence-state model with 9 fields present" "missing fields or section"
fi

# ======================================================================== #
# TEST 5: Adaptive planning + failure recovery (7 failure types)
# ======================================================================== #
REC_OK=1
for ftype in "tool |" "environment |" "assumption |" "plan |" "implementation |" "test |" "coordination |"; do
  assert_contains "$ORCH" "$ftype" || REC_OK=0
done
if [ "$REC_OK" = "1" ] && assert_contains "$ORCH" "## Adaptive Planning and Failure Recovery"; then
  ok "T05 adaptive planning with 7 failure types present"
else
  fail "T05 adaptive planning with 7 failure types present" "missing section or failure types"
fi

# ======================================================================== #
# TEST 6: Quality gates
# ======================================================================== #
if assert_contains "$ORCH" "UNDERSTANDING → PLAN → IMPLEMENT → VERIFY → REVIEW → COMPLETE"; then
  ok "T06 quality gates present"
else
  fail "T06 quality gates present" "gate chain missing"
fi

# ======================================================================== #
# TEST 7: Process quality anti-patterns
# ======================================================================== #
if assert_contains "$ORCH" "## Process Quality" \
   && assert_contains "$ORCH" "blind retries" \
   && assert_contains "$ORCH" "fixing symptoms without evidence"; then
  ok "T07 process quality anti-patterns present"
else
  fail "T07 process quality anti-patterns present" "section or anti-pattern markers missing"
fi

# ======================================================================== #
# TEST 8: Cost awareness
# ======================================================================== #
if assert_contains "$ORCH" "## Cost and Token Awareness" \
   && assert_contains "$ORCH" "cheapest action that produces the needed evidence"; then
  ok "T08 cost/token awareness present"
else
  fail "T08 cost/token awareness present" "section or cost rule missing"
fi

# ======================================================================== #
# TEST 9: Stop conditions
# ======================================================================== #
if assert_contains "$ORCH" "## Stop Conditions and Completion Rule" \
   && assert_contains "$ORCH" "no useful next action remains"; then
  ok "T09 explicit stop conditions present"
else
  fail "T09 explicit stop conditions present" "section or stop criterion missing"
fi

# ======================================================================== #
# TEST 10: every subagent has Evidence & Handoffs with the 9-field state record
# ======================================================================== #
SUBAGENTS=""
SUB_FAIL=""
for f in "$AGENTS"/*.md; do
  name="$(basename "$f")"
  [ "$name" = "orchestrator.md" ] && continue
  SUBAGENTS="$SUBAGENTS $name"
  if ! assert_contains "$f" "## Evidence & Handoffs"; then
    SUB_FAIL="$SUB_FAIL $name(no-section)"
  fi
  for field in "goal:" "hypothesis:" "evidence:" "actions_taken:" "result:" \
               "verification:" "confidence:" "remaining_unknowns:" "recommended_next_action:"; do
    assert_contains "$f" "$field" || SUB_FAIL="$SUB_FAIL $name(no-$field)"
  done
done
if [ -z "$SUB_FAIL" ]; then
  ok "T10 all 13 subagents have Evidence & Handoffs with 9-field state"
else
  fail "T10 all 13 subagents have Evidence & Handoffs with 9-field state" "$SUB_FAIL"
fi

# ======================================================================== #
# TEST 11: roster integrity — exactly 14 agents, 1 primary + 13 subagents
# ======================================================================== #
ROSTER_OK=1
N_FILES=0
N_PRIMARY=0
N_SUB=0
for f in "$AGENTS"/*.md; do
  N_FILES=$((N_FILES+1))
  if grep -q "^mode: primary$" "$f"; then N_PRIMARY=$((N_PRIMARY+1)); fi
  if grep -q "^mode: subagent$" "$f"; then N_SUB=$((N_SUB+1)); fi
  grep -q "^name: " "$f" || ROSTER_OK=0
done
if [ "$ROSTER_OK" = "1" ] && [ "$N_FILES" = "14" ] && [ "$N_PRIMARY" = "1" ] && [ "$N_SUB" = "13" ]; then
  ok "T11 roster integrity: 14 agents (1 primary + 13 subagents)"
else
  fail "T11 roster integrity: 14 agents (1 primary + 13 subagents)" \
       "files=$N_FILES primary=$N_PRIMARY sub=$N_SUB valid_names=$ROSTER_OK"
fi

# ======================================================================== #
# TEST 12: repository intelligence preserved — every agent references .opencode
# ======================================================================== #
N_REF=0
for f in "$AGENTS"/*.md; do
  assert_contains "$f" ".opencode" && N_REF=$((N_REF+1))
done
if [ "$N_REF" = "14" ]; then
  ok "T12 all 14 agents reference the .opencode repository intelligence layer"
else
  fail "T12 all 14 agents reference the .opencode repository intelligence layer" "only $N_REF/14"
fi

# ======================================================================== #
# TEST 13: repository intelligence bootstrap section intact (second-upgrade goal:
#          extend, do not discard existing work)
# ======================================================================== #
if assert_contains "$ORCH" "## Repository Intelligence Bootstrap" \
   && assert_contains "$ORCH" "### Knowledge lifecycle" \
   && assert_contains "$ORCH" "### Ownership rules"; then
  ok "T13 bootstrap + knowledge lifecycle sections preserved"
else
  fail "T13 bootstrap + knowledge lifecycle sections preserved" "bootstrap section or subsections missing"
fi

# ======================================================================== #
# TEST 14: state separation (context management) documented
# ======================================================================== #
if assert_contains "$ORCH" "repository knowledge  → .opencode/ skills" \
   && assert_contains "$ORCH" "task state            → .tasks/<goal>/tasks.json" \
   && assert_contains "$ORCH" "scratch               → /tmp/opencode"; then
  ok "T14 context/state separation documented"
else
  fail "T14 context/state separation documented" "state separation block missing"
fi

# ======================================================================== #
# TEST 15: behavioral acceptance test present (what the team SHOULD/NOT look like)
# ======================================================================== #
if assert_contains "$ORCH" "Behavioral acceptance test" \
   && assert_contains "$ORCH" "NOT like:" \
   && assert_contains "$ORCH" "call every agent"; then
  ok "T15 behavioral acceptance test present in orchestrator"
else
  fail "T15 behavioral acceptance test present in orchestrator" "accept/reject blocks missing"
fi

# ======================================================================== #
# TEST 16: architecture docs + evaluation scenarios exist
# ======================================================================== #
if [ -f "$DOCS/AGENT_ARCHITECTURE.md" ] && [ -f "$DOCS/EVALUATION_SCENARIOS.md" ]; then
  ok "T16 docs/AGENT_ARCHITECTURE.md and docs/EVALUATION_SCENARIOS.md exist"
else
  fail "T16 docs/AGENT_ARCHITECTURE.md and docs/EVALUATION_SCENARIOS.md exist" "one or both missing"
fi

# ======================================================================== #
# TEST 17: Task Breakdown dispatch threshold (breakdowner trigger markers)
# ======================================================================== #
if assert_contains "$ORCH" "## Task Breakdown Dispatch" \
   && assert_contains "$ORCH" "MUST dispatch breakdowner" \
   && assert_contains "$ORCH" "MUST NOT dispatch breakdowner" \
   && [ -f "$AGENTS/breakdowner.md" ] \
   && assert_contains "$AGENTS/breakdowner.md" "## Validation Invariant"; then
  ok "T17 Task Breakdown dispatch threshold defined (breakdowner trigger markers)"
else
  fail "T17 Task Breakdown dispatch threshold defined (breakdowner trigger markers)" "orchestrator markers or agents/breakdowner.md missing"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))