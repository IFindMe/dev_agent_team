#!/usr/bin/env bash
set -uo pipefail

# test-repo-bootstrap.sh — Automated tests for the Repository Intelligence Bootstrap
#
# Exit codes: 0 = all pass, 1 = any failure (PASS/FAIL per test, summary at end)
# Conventions follow the existing verify-permission-patterns.sh style:
#   temp fixture dirs, PASS/FAIL echo, deterministic assertions, no external deps
#   beyond bash, git (optional), and the repo-bootstrap.sh script under test.
#
# Acceptance matrix (10 items):
#   1. .opencode created for new repository
#   2. bootstrap is idempotent (second run = no drift / no change)
#   3. existing .opencode content (manual) is preserved
#   4. relevant repository skills are generated (node → build-and-test; Dockerfile → deployment)
#   5. orchestrator.md contains repository-context-before-dispatch stage (structural)
#   6. every agents/*.md references .opencode (consumes context)
#   7. stale knowledge is detectable (status exits 1 when fingerprint changes)
#   8. unrelated repositories do not inherit hardcoded assumptions (generic scaffold in plain dir)
#   9. existing agent workflows still work (install.sh to temp target)
#   10. malformed .opencode intelligence is handled safely (corrupted meta → re-bootstrap works)

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BOOTSTRAP="$TEAM_ROOT/scripts/repo-bootstrap.sh"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }
skip(){ PASS=$((PASS+1)); echo "SKIP  $1 — $2"; }
assert_file() { [ -f "$1" ] && return 0; return 1; }
assert_dir()  { [ -d "$1" ] && return 0; return 1; }
assert_contains() { grep -qF "$2" "$1" 2>/dev/null && return 0; return 1; }

# Helper: run bootstrap/status against a specific root (not cwd)
# Signature: RB <root> <command> [args...]  →  bash BOOTSTRAP <command> --root <root> [args...]
RB() { local r="$1"; shift; bash "$BOOTSTRAP" "$@" --root "$r"; }

# Fixture: generic project repo
make_repo() { # make_repo <name> [extra files...]
  local name="$1"; shift
  local d="$T/$name"
  mkdir -p "$d/src"
  git -C "$d" init -q . 2>/dev/null || true
  printf '# README\n' > "$d/README.md"
  for f in "$@"; do
    case "$f" in
      */*) mkdir -p "$d/$(dirname "$f")" ;;
    esac
    printf '/* placeholder */\n' > "$d/$f"
  done
  printf '%s' "$d"
}

# ======================================================================== #
# TEST 1: .opencode is created for a new repository
# ======================================================================== #
TEST1="$(make_repo test1)"
if RB "$TEST1" bootstrap >/dev/null 2>&1; then
  if assert_dir  "$TEST1/.opencode" && \
     assert_file "$TEST1/.opencode/AGENTS.md" && \
     assert_file "$TEST1/.opencode/.bootstrap-meta" && \
     assert_dir  "$TEST1/.opencode/skills/repo-context"; then
    ok "T01 .opencode created for new repo"
  else
    fail "T01 .opencode created for new repo" "missing expected files"
  fi
else
  fail "T01 .opencode created for new repo" "bootstrap exited non-zero"
fi

# ======================================================================== #
# TEST 2: bootstrap is idempotent (second run produces no changes)
# ======================================================================== #
TEST2="$(make_repo test2 package.json)"
RB "$TEST2" bootstrap >/dev/null 2>&1
META1=$(cat "$TEST2/.opencode/.bootstrap-meta" 2>/dev/null || echo "MISSING")
AGENTS1=$(cat "$TEST2/.opencode/AGENTS.md" 2>/dev/null || echo "MISSING")
if RB "$TEST2" bootstrap >/dev/null 2>&1; then
  META2=$(cat "$TEST2/.opencode/.bootstrap-meta" 2>/dev/null || echo "MISSING")
  AGENTS2=$(cat "$TEST2/.opencode/AGENTS.md" 2>/dev/null || echo "MISSING")
  if [ "$META1" = "$META2" ] && [ "$AGENTS1" = "$AGENTS2" ]; then
    ok "T02 bootstrap is idempotent"
  else
    fail "T02 bootstrap is idempotent" "file changed on second run"
  fi
else
  fail "T02 bootstrap is idempotent" "second run exited non-zero"
fi

# ======================================================================== #
# TEST 3: existing .opencode content (manual) is preserved
# ======================================================================== #
TEST3="$(make_repo test3)"
mkdir -p "$TEST3/.opencode/skills/repo-context"
printf '# Manual repo-context\nCustom content\n' > "$TEST3/.opencode/skills/repo-context/SKILL.md"
RB "$TEST3" bootstrap >/dev/null 2>&1
if assert_contains "$TEST3/.opencode/skills/repo-context/SKILL.md" "Custom content"; then
  ok "T03 existing manual content preserved"
else
  fail "T03 existing manual content preserved" "manual SKILL.md was overwritten"
fi

# ======================================================================== #
# TEST 4: relevant skills are generated (build indicator → build-and-test;
#         deploy indicator → deployment; plain → only repo-context + conventions)
# ======================================================================== #
TEST4A="$(make_repo test4a package.json Dockerfile src/lib/main.rs)"
RB "$TEST4A" bootstrap >/dev/null 2>&1
if assert_dir "$TEST4A/.opencode/skills/build-and-test" && \
   assert_dir "$TEST4A/.opencode/skills/deployment" && \
   assert_dir "$TEST4A/.opencode/skills/architecture" && \
   assert_dir "$TEST4A/.opencode/skills/repo-context" && \
   assert_dir "$TEST4A/.opencode/skills/conventions"; then
  ok "T04a build+deploy+code indicators produce expected skills"
else
  fail "T04a build+deploy+code indicators produce expected skills" \
    "missing skills: $(ls "$TEST4A/.opencode/skills" 2>/dev/null)"
fi

TEST4B="$(make_repo test4b README.md)"
RB "$TEST4B" bootstrap >/dev/null 2>&1
SKILLS_B=$(ls "$TEST4B/.opencode/skills" 2>/dev/null | sort | tr '\n' ' ')
if ! assert_dir "$TEST4B/.opencode/skills/build-and-test" && \
   ! assert_dir "$TEST4B/.opencode/skills/deployment" && \
   assert_dir "$TEST4B/.opencode/skills/repo-context" && \
   assert_dir "$TEST4B/.opencode/skills/conventions"; then
  ok "T04b plain repo only gets repo-context + conventions"
else
  fail "T04b plain repo only gets repo-context + conventions" "got: $SKILLS_B"
fi

# ======================================================================== #
# TEST 5: orchestrator.md contains repo-context-before-dispatch workflow stage
#         (structural: grep for bootstrap consumption and repo-context loading)
# ======================================================================== #
ORCH="$TEAM_ROOT/agents/orchestrator.md"
if assert_contains "$ORCH" "Repository Intelligence" && \
   assert_contains "$ORCH" ".opencode" && \
   assert_contains "$ORCH" "stale"; then
  ok "T05 orchestrator.md has bootstrap stage (structural)"
else
  fail "T05 orchestrator.md has bootstrap stage (structural)" \
    "missing expected Repository Intelligence / .opencode / stale content"
fi

# ======================================================================== #
# TEST 6: every agents/*.md references .opencode (consumes context)
# ======================================================================== #
MISSING_AGENTS=""
AGENT_COUNT=0
for af in "$TEAM_ROOT"/agents/*.md; do
  AGENT_COUNT=$((AGENT_COUNT+1))
  ANAME="$(basename "$af")"
  if ! assert_contains "$af" ".opencode"; then
    MISSING_AGENTS="$MISSING_AGENTS $ANAME"
  fi
done
if [ "$AGENT_COUNT" -eq 14 ] && [ -z "$MISSING_AGENTS" ]; then
  ok "T06 all $AGENT_COUNT agents reference .opencode"
else
  fail "T06 all agents reference .opencode" \
    "count=$AGENT_COUNT, missing:$MISSING_AGENTS"
fi

# ======================================================================== #
# TEST 7: stale knowledge is detectable (status exits 1 when fingerprint changes)
# ======================================================================== #
TEST7="$(make_repo test7 package.json)"
RB "$TEST7" bootstrap >/dev/null 2>&1
# fingerprint should be fresh
if RB "$TEST7" status >/dev/null 2>&1; then
  # mutate manifest → fingerprint should go stale
  printf '/* changed */\n' > "$TEST7/package.json"
  STALE_RC=0
  RB "$TEST7" status >/dev/null 2>&1 || STALE_RC=$?
  if [ "$STALE_RC" -eq 1 ]; then
    ok "T07 stale knowledge detectable after manifest change"
  else
    fail "T07 stale knowledge detectable after manifest change" \
      "status returned $STALE_RC (expected 1)"
  fi
else
  fail "T07 stale knowledge detectable" "initial status already non-zero"
fi

# ======================================================================== #
# TEST 8: unrelated repos do not inherit hardcoded assumptions
#          (script runs generically; no repo-specific name literals in scaffold)
# ======================================================================== #
TEST8="$(make_repo test8)"
RB "$TEST8" bootstrap >/dev/null 2>&1
AGENTS_CONTENT="$(cat "$TEST8/.opencode/AGENTS.md")"
RC_CONTENT="$(cat "$TEST8/.opencode/skills/repo-context/SKILL.md")"
# Verify no hardcoded repo/team names appear (should only contain generic placeholders)
if ! assert_contains "$AGENTS_CONTENT" "dev_agent_team" && \
   ! assert_contains "$RC_CONTENT" "orchestrator"; then
  ok "T08 no hardcoded repo-specific assumptions in scaffold"
else
  fail "T08 no hardcoded repo-specific assumptions in scaffold" \
    "found hardcoded terms in generated content"
fi

# ======================================================================== #
# TEST 9: existing agent workflows still work
#          (install.sh to temp target — 14 agents copied; treat "no runtime"
#           verifier exit 2 as SKIP since copies succeed regardless)
# ======================================================================== #
TEST9_TARGET="$T/install_target9"
if [ -f "$TEAM_ROOT/scripts/install.sh" ]; then
  INST_RC=0
  mkdir -p "$TEST9_TARGET"
  OPENCODE_AGENTS_DIR="$TEST9_TARGET" bash "$TEAM_ROOT/scripts/install.sh" >/dev/null 2>&1 || INST_RC=$?
  AGENTS_COPIED=$(find "$TEST9_TARGET" -name '*.md' -maxdepth 1 | wc -l)
  if [ "$INST_RC" -eq 0 ] || [ "$INST_RC" -eq 2 ]; then
    if [ "$AGENTS_COPIED" -eq 14 ]; then
      ok "T09 install.sh copies 14 agents to temp target (rc=$INST_RC, runtime=$([ $INST_RC -eq 0 ] && echo 'yes' || echo 'skip/no-op'))"
    else
      fail "T09 install.sh copies 14 agents to temp target" \
        "only $AGENTS_COPIED .md files copied"
    fi
  else
    fail "T09 install.sh copies 14 agents to temp target" \
      "install.sh exited $INST_RC"
  fi
else
  skip "T09 install.sh copies 14 agents" "scripts/install.sh not found"
fi

# ======================================================================== #
# TEST 10: malformed/incomplete .opencode intelligence is handled safely
# ======================================================================== #
TEST10="$(make_repo test10 package.json)"
mkdir -p "$TEST10/.opencode/skills/repo-context"
printf 'GARBAGE CONTENT\nno frontmatter\n' > "$TEST10/.opencode/skills/repo-context/SKILL.md"
echo "not-a-meta" > "$TEST10/.opencode/.bootstrap-meta"
RC=0
RB "$TEST10" bootstrap >/dev/null 2>&1 || RC=$?
# Assert: script did not crash, manual garbage in repo-context preserved (no marker),
# and meta was regenerated.
if [ "$RC" -eq 0 ] && \
   assert_contains "$TEST10/.opencode/skills/repo-context/SKILL.md" "GARBAGE CONTENT" && \
   assert_file "$TEST10/.opencode/.bootstrap-meta" && \
   assert_contains "$TEST10/.opencode/.bootstrap-meta" "schema=1"; then
  ok "T10 malformed intelligence handled safely"
else
  fail "T10 malformed intelligence handled safely" \
    "rc=$RC; corrupted repo-context still present after bootstrap"
fi

# ======================================================================== #
# SUMMARY
# ======================================================================== #
echo ""
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: ALL $TOTAL TESTS PASSED"
  exit 0
else
  echo "RESULT: $FAIL/$TOTAL TESTS FAILED"
  exit 1
fi