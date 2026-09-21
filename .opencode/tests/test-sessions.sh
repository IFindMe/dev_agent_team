#!/usr/bin/env bash
# test-sessions.sh — Integration tests for scripts/sessions.sh
# 12+ assertions covering: register/list/unregister, lock/unlock,
# conflict detection, expire stale sessions, heartbeat refresh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$TEAM_ROOT"
SESSIONS="$TEAM_ROOT/scripts/sessions.sh"
TEST_GOAL="_test_sessions_$$"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
  rm -rf "$REPO_ROOT/.tasks/$TEST_GOAL"
  rm -f "$REPO_ROOT/.tasks/$TEST_GOAL/sessions.json.lock"
}
trap cleanup EXIT

assert() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS [$TOTAL] $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL [$TOTAL] $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS [$TOTAL] $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL [$TOTAL] $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_nonzero() {
  local label="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL [$TOTAL] $label (expected non-zero exit)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS [$TOTAL] $label"
    PASS=$((PASS + 1))
  fi
}

echo "=== Test 1: Register + list ==="
OUT="$("$SESSIONS" register builder --task 01 --goal "$TEST_GOAL" 2>&1)"
assert_contains "register returns OK" "OK" "$OUT"

LIST_OUT="$("$SESSIONS" list --goal "$TEST_GOAL" 2>&1)"
assert_contains "list shows builder" "builder" "$LIST_OUT"
assert_contains "list shows task 01" "01" "$LIST_OUT"

echo "=== Test 2: Register duplicate ==="
assert_exit_nonzero "register duplicate agent fails" \
  "$SESSIONS" register builder --task 02 --goal "$TEST_GOAL"

echo "=== Test 3: Second agent register + list count ==="
"$SESSIONS" register toolsmith --task 03 --goal "$TEST_GOAL" >/dev/null 2>&1
LIST_OUT="$("$SESSIONS" list --goal "$TEST_GOAL" 2>&1)"
COUNT="$(echo "$LIST_OUT" | wc -l | tr -d ' ')"
assert "list shows 2 agents" "2" "$COUNT"

echo "=== Test 4: Unregister + verify gone ==="
"$SESSIONS" unregister toolsmith --goal "$TEST_GOAL" >/dev/null 2>&1
LIST_OUT="$("$SESSIONS" list --goal "$TEST_GOAL" 2>&1)"
COUNT="$(echo "$LIST_OUT" | wc -l | tr -d ' ')"
assert "list shows 1 agent after unregister" "1" "$COUNT"
assert_contains "builder still present" "builder" "$LIST_OUT"

echo "=== Test 5: Lock file ==="
LOCK_OUT="$("$SESSIONS" lock src/foo.sh --by builder --goal "$TEST_GOAL" 2>&1)"
assert_contains "lock returns OK" "OK" "$LOCK_OUT"

echo "=== Test 6: Idempotent re-lock by same agent ==="
LOCK_OUT="$("$SESSIONS" lock src/foo.sh --by builder --goal "$TEST_GOAL" 2>&1)"
assert_contains "idempotent lock OK" "OK" "$LOCK_OUT"

echo "=== Test 7: Conflict detection ==="
# Unregister detective first (registered in test 3)
"$SESSIONS" unregister detective --goal "$TEST_GOAL" >/dev/null 2>&1
"$SESSIONS" register detective --task 04 --goal "$TEST_GOAL" >/dev/null 2>&1
LOCK_OUT="$("$SESSIONS" lock src/foo.sh --by detective --goal "$TEST_GOAL" 2>&1 || true)"
assert_contains "lock conflict detected" "CONFLICT" "$LOCK_OUT"

echo "=== Test 8: Unlock ==="
UNLOCK_OUT="$("$SESSIONS" unlock src/foo.sh --by builder --goal "$TEST_GOAL" 2>&1)"
assert_contains "unlock returns OK" "OK" "$UNLOCK_OUT"

echo "=== Test 9: Conflicts command shows nothing when no conflict ==="
"$SESSIONS" register devops --task 05 --goal "$TEST_GOAL" >/dev/null 2>&1
"$SESSIONS" lock src/bar.sh --by devops --goal "$TEST_GOAL" >/dev/null 2>&1
CONFLICT_OUT="$("$SESSIONS" conflicts --goal "$TEST_GOAL" 2>&1)"
assert_contains "no conflicts when files differ" "No conflicts" "$CONFLICT_OUT"

echo "=== Test 10: Heartbeat refresh ==="
HB_OUT="$("$SESSIONS" heartbeat builder --goal "$TEST_GOAL" 2>&1)"
assert_contains "heartbeat returns OK" "OK" "$HB_OUT"

echo "=== Test 11: Expire stale sessions ==="
# Create a session with an ancient heartbeat by manipulating JSON directly
"$SESSIONS" register expire_me --task 99 --goal "$TEST_GOAL" >/dev/null 2>&1
F="$REPO_ROOT/.tasks/$TEST_GOAL/sessions.json"
jq --arg old "2020-01-01T00:00:00Z" \
  '.sessions |= map(if .agent == "expire_me" then .last_heartbeat = $old else . end)' \
  "$F" > "$F.tmp" && mv "$F.tmp" "$F"

EXPIRE_OUT="$("$SESSIONS" expire --goal "$TEST_GOAL" --stale-minutes 30 2>&1 || true)"
assert_contains "expire removes stale session" "Expired" "$EXPIRE_OUT"

LIST_OUT="$("$SESSIONS" list --goal "$TEST_GOAL" 2>&1)"
EXISTS="$(echo "$LIST_OUT" | grep -c expire_me || true)"
TOTAL=$((TOTAL + 1))
if [[ "$EXISTS" -eq 0 ]]; then
  echo "  PASS [$TOTAL] expire_me removed from list"
  PASS=$((PASS + 1))
else
  echo "  FAIL [$TOTAL] expire_me still in list"
  FAIL=$((FAIL + 1))
fi

echo "=== Test 12: Unregister cleans up locks ==="
"$SESSIONS" register lockclean --task 10 --goal "$TEST_GOAL" >/dev/null 2>&1
"$SESSIONS" lock src/clean.sh --by lockclean --goal "$TEST_GOAL" >/dev/null 2>&1
"$SESSIONS" unregister lockclean --goal "$TEST_GOAL" >/dev/null 2>&1
F="$REPO_ROOT/.tasks/$TEST_GOAL/sessions.json"
LOCKS_FOR_CLEAN="$(jq '[.locks[] | select(.locked_by == "lockclean")] | length' "$F")"
assert "locks removed after unregister" "0" "$LOCKS_FOR_CLEAN"

echo "=== Test 13: List across all goals ==="
"$SESSIONS" register global_test --task 99 --goal "${TEST_GOAL}_other" >/dev/null 2>&1
ALL_LIST="$("$SESSIONS" list 2>&1)"
assert_contains "global list shows builder" "builder" "$ALL_LIST"
assert_contains "global list shows global_test" "global_test" "$ALL_LIST"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
