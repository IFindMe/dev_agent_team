#!/usr/bin/env bash
set -uo pipefail

# test-local-install.sh — Verify --local flag installs to .opencode/ in current directory.
#
# Tests:
#   T01: --local installs agents to .opencode/agents/
#   T02: --local installs runtime to .opencode/dev-agent-team/
#   T03: --local does NOT modify shell-rc
#   T04: --local manifest records correct paths
#   T05: --local uninstall removes local install
#   T06: --local is idempotent (second run works)
#
# Exit codes: 0 = all pass, 1 = any failure.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SRC_SCRIPTS="$TEAM_ROOT/scripts"

PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_file(){ [ -f "$1" ] && return 0; return 1; }
assert_dir() { [ -d "$1" ] && return 0; return 1; }

# ======================================================================== #
# Setup: temp working directory (simulates a user project)
# ======================================================================== #
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Copy source files to temp dir (simulates having install.sh in a project)
WORK="$T/myproject"
mkdir -p "$WORK/scripts" "$WORK/agents" "$WORK/skills" "$WORK/improvements"
cp -p "$SRC_SCRIPTS"/*.sh "$WORK/scripts/" 2>/dev/null || true
cp -p "$TEAM_ROOT"/agents/*.md "$WORK/agents/" 2>/dev/null || true
cp -r "$TEAM_ROOT/skills/." "$WORK/skills/" 2>/dev/null || true
cp -r "$TEAM_ROOT/improvements/." "$WORK/improvements/" 2>/dev/null || true

# Save original shell-rc state
RC_BEFORE=""
[ -f "$HOME/.bashrc" ] && RC_BEFORE="$(md5sum "$HOME/.bashrc" | awk '{print $1}')"
[ -z "$RC_BEFORE" ] && [ -f "$HOME/.profile" ] && RC_BEFORE="$(md5sum "$HOME/.profile" | awk '{print $1}')"

# ======================================================================== #
# T01: --local installs agents to .opencode/agents/
# ======================================================================== #
cd "$WORK"
env -i HOME="$HOME" PATH="$PATH" bash "$WORK/scripts/install.sh" --local >/dev/null 2>&1
if [ -d "$WORK/.opencode/agents" ]; then
  N_AGENTS="$(ls "$WORK/.opencode/agents/"*.md 2>/dev/null | wc -l)"
  if [ "$N_AGENTS" = "14" ]; then
    ok "T01 --local installs 14 agents to .opencode/agents/"
  else
    fail "T01 --local installs agents" "count=$N_AGENTS (want 14)"
  fi
else
  fail "T01 --local installs agents" ".opencode/agents/ not found"
fi

# ======================================================================== #
# T02: --local installs runtime to .opencode/dev-agent-team/
# ======================================================================== #
if [ -d "$WORK/.opencode/dev-agent-team" ]; then
  RT_OK=1
  [ -x "$WORK/.opencode/dev-agent-team/bin/memory-lifecycle.sh" ] || { RT_OK=0; fail "T02 runtime" "missing bin/memory-lifecycle.sh"; }
  [ -d "$WORK/.opencode/dev-agent-team/skills" ] || { RT_OK=0; fail "T02 runtime" "missing skills/"; }
  [ -f "$WORK/.opencode/dev-agent-team/install-manifest.json" ] || { RT_OK=0; fail "T02 runtime" "missing manifest"; }
  [ "$RT_OK" = "1" ] && ok "T02 --local installs runtime to .opencode/dev-agent-team/"
else
  fail "T02 --local installs runtime" ".opencode/dev-agent-team/ not found"
fi

# ======================================================================== #
# T03: --local does NOT modify shell-rc
# ======================================================================== #
RC_AFTER=""
[ -f "$HOME/.bashrc" ] && RC_AFTER="$(md5sum "$HOME/.bashrc" | awk '{print $1}')"
[ -z "$RC_AFTER" ] && [ -f "$HOME/.profile" ] && RC_AFTER="$(md5sum "$HOME/.profile" | awk '{print $1}')"
if [ "$RC_BEFORE" = "$RC_AFTER" ]; then
  ok "T03 --local does NOT modify shell-rc"
else
  fail "T03 --local does NOT modify shell-rc" "shell-rc changed"
fi

# ======================================================================== #
# T04: --local manifest records correct paths
# ======================================================================== #
if [ -f "$WORK/.opencode/dev-agent-team/install-manifest.json" ]; then
  if grep -q ".opencode/agents" "$WORK/.opencode/dev-agent-team/install-manifest.json"; then
    ok "T04 --local manifest records .opencode/agents path"
  else
    fail "T04 --local manifest records correct path" "manifest does not reference .opencode/agents"
  fi
else
  fail "T04 --local manifest records correct path" "manifest not found"
fi

# ======================================================================== #
# T05: --local uninstall removes local install
# ======================================================================== #
env -i HOME="$HOME" PATH="$PATH" bash "$WORK/scripts/install.sh" --uninstall --local <<< "y" >/dev/null 2>&1
if [ ! -d "$WORK/.opencode/dev-agent-team/bin" ] || [ -z "$(ls "$WORK/.opencode/dev-agent-team/bin/" 2>/dev/null)" ]; then
  ok "T05 --local uninstall removes local install"
else
  fail "T05 --local uninstall removes local install" ".opencode/dev-agent-team/bin/ still exists"
fi

# ======================================================================== #
# T06: --local is idempotent (second run works)
# ======================================================================== #
env -i HOME="$HOME" PATH="$PATH" bash "$WORK/scripts/install.sh" --local >/dev/null 2>&1
env -i HOME="$HOME" PATH="$PATH" bash "$WORK/scripts/install.sh" --local >/dev/null 2>&1
N_AGENTS="$(ls "$WORK/.opencode/agents/"*.md 2>/dev/null | wc -l)"
if [ "$N_AGENTS" = "14" ]; then
  ok "T06 --local is idempotent (14 agents after 2 runs)"
else
  fail "T06 --local is idempotent" "count=$N_AGENTS (want 14)"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo ""
echo "Results: $PASS passed, $FAIL failed (out of $((PASS+FAIL)))"
[ "$FAIL" = "0" ] && echo "ALL TESTS PASSED" && exit 0
echo "FAILURES PRESENT" && exit 1
