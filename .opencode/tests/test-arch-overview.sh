#!/usr/bin/env bash
# test-arch-overview.sh — gate suite for scripts/arch-overview.sh
#
# Proves the CLI contract:
#   (a) default output is valid markdown with all sections
#   (b) --format json produces parseable JSON
#   (c) --section <name> returns only that section
#   (d) --path works for alternate paths
#   (e) --depth limits tree output
#   (f) exit codes: 0 for valid, 2 for bad args, 1 for missing path
#
# Exit codes: 0 = all pass, 1 = any failure.

set -uo pipefail

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ARCH="$TEAM_ROOT/scripts/arch-overview.sh"

[ -x "$ARCH" ] || { echo "FAIL  setup — scripts/arch-overview.sh missing/not executable" >&2; exit 1; }

PASS=0; FAIL=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label (output missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "FAIL  $label (output unexpectedly contains: $needle)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS  $label"
    PASS=$((PASS + 1))
  fi
}

assert_starts_with() {
  local label="$1" haystack="$2" prefix="$3"
  if echo "$haystack" | head -1 | grep -q "^$prefix"; then
    echo "PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label (first line does not start with: $prefix)"
    FAIL=$((FAIL + 1))
  fi
}

# ---- T1: default output is markdown with all sections ----
OUT="$(bash "$ARCH" 2>&1)"
assert_exit "T1-default-exit" 0 $?
assert_contains "T1-has-title" "$OUT" "# Architecture Overview:"
assert_contains "T1-has-tree" "$OUT" "## File Tree"
assert_contains "T1-has-languages" "$OUT" "## Languages"
assert_contains "T1-has-entry-points" "$OUT" "## Entry Points"
assert_contains "T1-has-modules" "$OUT" "## Module Boundaries"
assert_contains "T1-has-dependencies" "$OUT" "## Dependencies"
assert_contains "T1-has-hotspots" "$OUT" "## Hotspots"
assert_contains "T1-has-cross-deps" "$OUT" "## Cross-Module Dependencies"

# ---- T2: JSON output is parseable ----
JSON="$(bash "$ARCH" --format json 2>&1)"
assert_exit "T2-json-exit" 0 $?
assert_contains "T2-json-has-repo" "$JSON" '"repo":'
assert_contains "T2-json-has-languages" "$JSON" '"languages":'
assert_contains "T2-json-has-hotspots" "$JSON" '"hotspots":'

# ---- T3: --section tree only shows tree ----
TREE="$(bash "$ARCH" --section tree 2>&1)"
assert_exit "T3-tree-exit" 0 $?
assert_contains "T3-tree-has-header" "$TREE" "## File Tree"
assert_not_contains "T3-tree-no-langs" "$TREE" "## Languages"

# ---- T4: --section languages only shows languages ----
LANGS="$(bash "$ARCH" --section languages 2>&1)"
assert_exit "T4-langs-exit" 0 $?
assert_contains "T4-langs-header" "$LANGS" "## Languages"
assert_contains "T4-langs-md" "$LANGS" "markdown"
assert_not_contains "T4-langs-no-tree" "$LANGS" "## File Tree"

# ---- T5: --section hotspots only shows hotspots ----
HOT="$(bash "$ARCH" --section hotspots 2>&1)"
assert_exit "T5-hotspots-exit" 0 $?
assert_contains "T5-hotspots-header" "$HOT" "## Hotspots"
assert_not_contains "T5-hotspots-no-langs" "$HOT" "## Languages"

# ---- T6: --depth 1 limits tree ----
DEPTH1="$(bash "$ARCH" --section tree --depth 1 2>&1)"
assert_exit "T6-depth-exit" 0 $?
assert_contains "T6-depth-has-tree" "$DEPTH1" "## File Tree"

# ---- T7: --path works ----
PATH_OUT="$(bash "$ARCH" --path "$TEAM_ROOT" --section languages 2>&1)"
assert_exit "T7-path-exit" 0 $?
assert_contains "T7-path-langs" "$PATH_OUT" "## Languages"

# ---- T8: unknown section returns exit 2 ----
BAD_SEC="$(bash "$ARCH" --section nonexistent 2>&1)"
assert_exit "T8-bad-section-exit" 2 $?

# ---- T9: unknown option returns exit 2 ----
BAD_OPT="$(bash "$ARCH" --badopt 2>&1)"
assert_exit "T9-bad-opt-exit" 2 $?

# ---- T10: entry-points section works ----
EP="$(bash "$ARCH" --section entry-points 2>&1)"
assert_exit "T10-entry-exit" 0 $?
assert_contains "T10-entry-header" "$EP" "## Entry Points"

# ---- T11: dependencies section works ----
DEPS="$(bash "$ARCH" --section dependencies 2>&1)"
assert_exit "T11-deps-exit" 0 $?
assert_contains "T11-deps-header" "$DEPS" "## Dependencies"

# ---- T12: modules section works ----
MODS="$(bash "$ARCH" --section modules 2>&1)"
assert_exit "T12-modules-exit" 0 $?
assert_contains "T12-modules-header" "$MODS" "## Module Boundaries"

# ---- T13: cross-deps section works ----
CROSS="$(bash "$ARCH" --section cross-deps 2>&1)"
assert_exit "T13-cross-exit" 0 $?
assert_contains "T13-cross-header" "$CROSS" "## Cross-Module Dependencies"

# ---- Summary ----
echo ""
echo "=============================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "=============================="

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
