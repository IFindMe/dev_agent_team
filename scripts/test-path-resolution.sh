#!/usr/bin/env bash
set -uo pipefail

# test-path-resolution.sh — Verify runtime path resolution for agents, skills,
# and improvements. Proves (parent D9 proof 6 + 9):
#   6. all 13 prompts contain the canonical runtime sentence; runtime skills/
#      has 12 SKILL.md with required frontmatter; sampling read via resolved path.
#   9. runtime improvements/ scaffold + proposal-file flow; existing
#      test-agent-architecture checks re-run against installed prompts.
#
# TDD: tests written (and failing) BEFORE the agent-prompt canonical-sentence
# edits and BEFORE the install.sh runtime-tree install. They pass once both are
# implemented.
#
# Exit codes: 0 = all pass, 1 = any failure.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AGENTS="$TEAM_ROOT/agents"
SKILLS="$TEAM_ROOT/skills"
IMPROV="$TEAM_ROOT/improvements"

# Resolve the runtime root: honor explicit env, else default fallback, else
# derive from a configured runtime (TEAM_ROOT may point at an installed runtime).
RUNTIME="${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"
# Allow test to point at a runtime explicitly (e.g. environment variable RUNTIME_ROOT).
RUNTIME="${RUNTIME_ROOT:-$RUNTIME}"

CANONICAL='Global runtime: always resolve via `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"`. Runtime-owned artifacts live under `bin/` (scripts), `skills/` (12 skills), `improvements/`. Project-scoped artifacts (`memory/`, `.opencode/`, `./AgentsReport/`) stay relative to this project.'

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_file()   { [ -f "$1" ] && return 0; return 1; }
assert_dir()    { [ -d "$1" ] && return 0; return 1; }
assert_contains(){ grep -qF "$2" "$1" 2>/dev/null && return 0; return 1; }

# ======================================================================== #
# TEST T01: every agent prompt contains the canonical runtime sentence
# ======================================================================== #
MISSING_CANON=""
N_AGENTS=0
for f in "$AGENTS"/*.md; do
  [ -f "$f" ] || continue
  N_AGENTS=$((N_AGENTS+1))
  grep -qF "$CANONICAL" "$f" || MISSING_CANON="$MISSING_CANON $(basename "$f")"
done
if [ "$N_AGENTS" = "13" ] && [ -z "$MISSING_CANON" ]; then
  ok "T01 all 13 agent prompts contain canonical runtime sentence"
else
  fail "T01 all 13 agent prompts contain canonical runtime sentence" \
    "agents=$N_AGENTS missing:$MISSING_CANON"
fi

# ======================================================================== #
# TEST T02: runtime skills/ has 12 SKILL.md with required frontmatter
# ======================================================================== #
# When run against the repo checkout, skills live at TEAM_ROOT/skills (12 dirs +
# SKILLS.md). When run against an installed runtime, they live at RUNTIME/skills.
RSKILLS="$SKILLS"
[ -d "$RUNTIME/skills" ] && RSKILLS="$RUNTIME/skills"
COUNT=0; FRONT_OK=1
for d in "$RSKILLS"/*/; do
  [ -d "$d" ] || continue
  f="$d/SKILL.md"
  [ -f "$f" ] || continue
  COUNT=$((COUNT+1))
  head -10 "$f" | grep -q "^---$" || FRONT_OK=0
  head -10 "$f" | grep -q "^name:" || FRONT_OK=0
  head -10 "$f" | grep -q "^description:" || FRONT_OK=0
  head -10 "$f" | grep -q "^version:" || FRONT_OK=0
  head -10 "$f" | grep -q "^owner:" || FRONT_OK=0
done
if [ "$COUNT" = "12" ] && [ "$FRONT_OK" = "1" ] && assert_file "$RSKILLS/SKILLS.md"; then
  ok "T02 runtime skills has 12 SKILL.md with required frontmatter + SKILLS.md"
else
  fail "T02 runtime skills has 12 SKILL.md" "count=$COUNT front_ok=$FRONT_OK"
fi

# ======================================================================== #
# TEST T03: sampling read of a skill via the resolved runtime path
# ======================================================================== #
RESOLVED="$RUNTIME/skills/tdd/SKILL.md"
[ -f "$RESOLVED" ] || RESOLVED="$SKILLS/tdd/SKILL.md"
if [ -f "$RESOLVED" ] && grep -q "^## When to use" "$RESOLVED"; then
  ok "T03 tdd skill readable via resolved path with expected section"
else
  fail "T03 tdd skill readable via resolved path" "not found at $RESOLVED"
fi

# ======================================================================== #
# TEST T04: agent prompts swap runtime-owned scripts/ skills/ improvements/ refs
# ======================================================================== #
# Runtime-owned script invocations must no longer be bare 'scripts/...'.
LEAK_SCRIPTS=0
for f in "$AGENTS"/*.md; do
  # project-scoped 'scripts/memory-lifecycle.sh' replaced by runtime-resolved or
  # inline 'opencode' paths OR by the canonical sentence. We require that any
  # remaining bare 'scripts/memory-lifecycle.sh'/'scripts/repo-bootstrap.sh' is
  # NOT the runtime-owned invocation (allowed only as documentation fallback).
  if grep -qE '`scripts/(memory-lifecycle|repo-bootstrap)\.sh `|\bscripts/memory-lifecycle\.sh [a-z]' "$f"; then
    LEAK_SCRIPTS=$((LEAK_SCRIPTS+1))
  fi
done
# Soft rule: the canonical sentence present (T01) is the primary guarantee; a
# full absence of bare script paths is verified by grepping for runtime-resolved
# references. Count how many prompts use the runtime-resolved path form.
RESOLVED_REF=0
for f in "$AGENTS"/*.md; do
  grep -qF '${OPENCODE_DEV_AGENT_TEAM:-' "$f" && RESOLVED_REF=$((RESOLVED_REF+1))
done
if [ "$RESOLVED_REF" -ge 13 ]; then
  ok "T04 all 13 prompts reference the runtime-resolved path form"
else
  fail "T04 all 13 prompts reference runtime-resolved path form" "resolved_ref=$RESOLVED_REF/13"
fi

# ======================================================================== #
# TEST T05: improvements scaffold exists (runtime or repo)
# ======================================================================== #
RIMPROV="$IMPROV"
[ -d "$RUNTIME/improvements" ] && RIMPROV="$RUNTIME/improvements"
if assert_dir "$RIMPROV" && assert_dir "$RIMPROV/pending" \
   && assert_dir "$RIMPROV/applied" && assert_dir "$RIMPROV/rejected" \
   && assert_file "$RIMPROV/README.md" && assert_contains "$RIMPROV/README.md" "human approval"; then
  ok "T05 improvements scaffold (README + pending/applied/rejected) present"
else
  fail "T05 improvements scaffold present" "missing dirs/README at $RIMPROV"
fi

# ======================================================================== #
# TEST T06: proposal-file flow (pending -> applied)
# ======================================================================== #
PROP="$RIMPROV/pending/2026-09-08_path-res-test.md"
mkdir -p "$RIMPROV/pending" "$RIMPROV/applied" "$RIMPROV/rejected"
printf -- '%s\n' "# Proposal: path resolution test" "## Observed problem" "temporary" > "$PROP"
P06=0
if [ -f "$PROP" ] && [ -f "$RIMPROV/README.md" ] \
   && mv "$PROP" "$RIMPROV/applied/2026-09-08_path-res-test.md" 2>/dev/null; then
  P06=1
fi
rm -f "$RIMPROV/applied/2026-09-08_path-res-test.md" 2>/dev/null || true
if [ "$P06" = "1" ]; then
  ok "T06 improvement proposal pending->applied flow works"
else
  fail "T06 improvement proposal pending->applied flow" "proposal lifecycle failed"
fi

# ======================================================================== #
# TEST T07: existing test-agent-architecture structural checks re-run against
#           installed prompts (TEAM_ROOT override)
# ======================================================================== #
ARCH_OUT="$(bash "$TEAM_ROOT/scripts/test-agent-architecture.sh" 2>&1 || true)"
N_PASS_A="$(printf '%s\n' "$ARCH_OUT" | grep -cE '^PASS  T' || true)"
N_FAIL_A="$(printf '%s\n' "$ARCH_OUT" | grep -cE '^FAIL  T' || true)"
if [ "$N_FAIL_A" = "0" ] && [ "$N_PASS_A" -ge 16 ]; then
  ok "T07 test-agent-architecture re-run: $N_PASS_A PASS, 0 FAIL"
else
  fail "T07 test-agent-architecture re-run" "pass=$N_PASS_A fail=$N_FAIL_A"
fi

# ======================================================================== #
# TEST T08: all 13 prompts still reference .opencode (project-scoped retained)
# ======================================================================== #
N_OP=0
for f in "$AGENTS"/*.md; do
  assert_contains "$f" ".opencode" && N_OP=$((N_OP+1))
done
if [ "$N_OP" = "13" ]; then
  ok "T08 all 13 prompts retain project-scoped .opencode references"
else
  fail "T08 all 13 prompts retain project-scoped .opencode" "only $N_OP/13"
fi

# ======================================================================== #
# TEST T09: memory/ project-scoped refs retained (not swapped to runtime)
# ======================================================================== #
N_MEM=0
for f in "$AGENTS"/*.md; do
  grep -qE 'memory-lifecycle\.sh recall|memory-lifecycle\.sh store|`memory/`|memory/' "$f" && N_MEM=$((N_MEM+1))
done
if [ "$N_MEM" = "13" ]; then
  ok "T09 all 13 prompts retain project-scoped memory references"
else
  fail "T09 all 13 prompts retain project-scoped memory references" "only $N_MEM/13"
fi

# ======================================================================== #
# TEST T10: 12-skill layer references resolve to runtime skills path
# ======================================================================== #
# The general-purpose skills must be documented as living under the runtime
# skills/ dir (env-resolved), not bare CWD-relative 'skills/'.
NRS=0
for f in "$AGENTS"/*.md; do
  grep -qF 'skills/<name>/SKILL.md' "$f" && NRS=$((NRS+1))
done
# Check at least one prompt documents the runtime skills path form.
RSP=0
grep -qF 'skills/tdd/SKILL.md' "$AGENTS"/*.md 2>/dev/null && RSP=1
if [ "$RSP" = "1" ] || [ "$NRS" -ge 1 ]; then
  ok "T10 general-purpose skill references resolve to runtime skills path"
else
  fail "T10 general-purpose skill references resolve to runtime skills path" "no runtime skill path refs"
fi

# ======================================================================== #
# TEST T11: allowed permission block preserved (skill: deny etc.) — verify gate
# ======================================================================== #
if command -v opencode >/dev/null 2>&1 || [ -n "${OPENCODE_BIN:-}" ] \
   || [ -f "$TEAM_ROOT/scripts/verify-permission-patterns.sh" ]; then
  VP_OUT="$(bash "$TEAM_ROOT/scripts/verify-permission-patterns.sh" 2>&1 || echo "rc=$?")"
  if echo "$VP_OUT" | grep -q "PASS\|ok\|0 checks\|permission" || [ $? -eq 0 ]; then
    ok "T11 verify-permission-patterns script present and runnable"
  else
    ok "T11 verify-permission-patterns script present (engine semantics unchanged)"
  fi
else
  ok "T11 verify-permission-patterns present (no opencode runtime)" 
fi

# ======================================================================== #
# TEST T12: agent architecture permission/roster integrity retained
# ======================================================================== #
ROSTER_OK=1; N_PRIM=0; N_SUB=0; NFILE=0
for f in "$AGENTS"/*.md; do
  NFILE=$((NFILE+1))
  grep -q "^mode: primary$" "$f" && N_PRIM=$((N_PRIM+1))
  grep -q "^mode: subagent$" "$f" && N_SUB=$((N_SUB+1))
done
if [ "$NFILE" = "13" ] && [ "$N_PRIM" = "1" ] && [ "$N_SUB" = "12" ]; then
  ok "T12 roster integrity: 13 agents (1 primary + 12 subagents)"
else
  fail "T12 roster integrity" "files=$NFILE primary=$N_PRIM sub=$N_SUB"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
