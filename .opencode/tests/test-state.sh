#!/usr/bin/env bash
# test-state.sh — Test suite for scripts/state.sh
# Covers: task CRUD, transitions, blocked-detect, queries, log, agents sync,
#         goal resolution, error paths, deps.
# Run: bash .opencode/tests/test-state.sh
# Exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE="$TEAM_ROOT/scripts/state.sh"
TEST_DIR="/tmp/state-test-$$"

# Test counters
declare -i PASS_COUNT=0 FAIL_COUNT=0 TOTAL=0

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

ok() {
  ((PASS_COUNT++)) || true
  ((TOTAL++)) || true
  echo "PASS  $1"
}

fail() {
  ((FAIL_COUNT++)) || true
  ((TOTAL++)) || true
  echo "FAIL  $1"
  echo "    $2"
}

# Run state.sh with a custom STATE_ROOT and optional STATE_GOAL.
run_state() {
  local goal_flag=""
  if [ -n "${USE_GOAL:-}" ]; then
    goal_flag="--goal=$USE_GOAL"
  fi
  STATE_ROOT="$TEST_DIR/tasks" bash "$STATE" $goal_flag "$@" 2>&1
}

# Create the test goal directory and tasks.json.
setup_goal() {
  mkdir -p "$TEST_DIR/tasks/$TEST_GOAL"
  jq -n --arg g "$TEST_GOAL" '{version:1, goal:$g, tasks:{}}' \
    > "$TEST_DIR/tasks/$TEST_GOAL/tasks.json"
}

# --------------------------------------------------------------------- #
# Test setup
# --------------------------------------------------------------------- #
TEST_GOAL="test_goal_$$"
USE_GOAL="$TEST_GOAL"

echo "=== state.sh Test Suite ==="
echo "Goal: $TEST_GOAL"
echo

# --------------------------------------------------------------------- #
# TEST T01: task create
# --------------------------------------------------------------------- #
setup_goal
OUT="$(run_state task create t01 --title "First task" --description "desc" --priority high)"
if echo "$OUT" | grep -qF "created: $TEST_GOAL/t01 (pending)"; then
  # Verify task exists in tasks.json
  STATUS="$(jq -r '.tasks.t01.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  TITLE="$(jq -r '.tasks.t01.title' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "pending" ] && [ "$TITLE" = "First task" ]; then
    ok "T01 task create — status=pending, title correct"
  else
    fail "T01 task create — wrong fields" "status=$STATUS title=$TITLE"
  fi
else
  fail "T01 task create" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T02: task create with dependencies
# --------------------------------------------------------------------- #
OUT="$(run_state task create t02 --title "Second task" --depends-on t01 t03)"
if echo "$OUT" | grep -qF "created: $TEST_GOAL/t02 (pending)"; then
  DEPS="$(jq -r '.tasks.t02.dependencies | sort | join(",")' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$DEPS" = "t01,t03" ]; then
    ok "T02 task create with deps"
  else
    fail "T02 task create with deps" "deps=$DEPS (expected t01,t03)"
  fi
else
  fail "T02 task create with deps" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T03: task create — self-dependency error
# --------------------------------------------------------------------- #
OUT="$(run_state task create t03 --title "Self dep" --depends-on t03 2>&1 || true)"
if echo "$OUT" | grep -qF "task cannot depend on itself"; then
  ok "T03 task create — self-dependency rejected"
else
  fail "T03 task create — self-dependency" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T04: task create — duplicate id error
# --------------------------------------------------------------------- #
OUT="$(run_state task create t01 --title "Dup" 2>&1 || true)"
if echo "$OUT" | grep -qF "already exists"; then
  ok "T04 task create — duplicate id rejected"
else
  fail "T04 task create — duplicate id" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T05: task create — missing --title error
# --------------------------------------------------------------------- #
OUT="$(run_state task create t05 2>&1 || true)"
if echo "$OUT" | grep -qF -- "--title is required"; then
  ok "T05 task create — missing --title rejected"
else
  fail "T05 task create — missing --title" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T06: task assign
# --------------------------------------------------------------------- #
OUT="$(run_state task assign t01 agent-alpha)"
if echo "$OUT" | grep -qF "assigned: $TEST_GOAL/t01 -> agent-alpha"; then
  STATUS="$(jq -r '.tasks.t01.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  AGENT="$(jq -r '.tasks.t01.assigned_to' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "assigned" ] && [ "$AGENT" = "agent-alpha" ]; then
    ok "T06 task assign"
  else
    fail "T06 task assign — wrong fields" "status=$STATUS agent=$AGENT"
  fi
else
  fail "T06 task assign" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T07: task assign — not pending error
# --------------------------------------------------------------------- #
OUT="$(run_state task assign t01 agent-beta 2>&1 || true)"
if echo "$OUT" | grep -qF "transition assigned -> assigned is not allowed"; then
  ok "T07 task assign — non-pending rejected"
else
  fail "T07 task assign — non-pending" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T08: task status — assigned -> in_progress
# --------------------------------------------------------------------- #
OUT="$(run_state task status t01 in_progress)"
if echo "$OUT" | grep -qF "assigned -> in_progress"; then
  STATUS="$(jq -r '.tasks.t01.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  STARTED="$(jq -r '.tasks.t01.started_at' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "in_progress" ] && [ "$STARTED" != "null" ]; then
    ok "T08 task status assigned->in_progress"
  else
    fail "T08 task status — wrong fields" "status=$STATUS started=$STARTED"
  fi
else
  fail "T08 task status assigned->in_progress" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T09: task status — in_progress -> completed
# --------------------------------------------------------------------- #
OUT="$(run_state task status t01 completed)"
if echo "$OUT" | grep -qF "in_progress -> completed"; then
  STATUS="$(jq -r '.tasks.t01.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  COMPLETED="$(jq -r '.tasks.t01.completed_at' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "completed" ] && [ "$COMPLETED" != "null" ]; then
    ok "T09 task status in_progress->completed"
  else
    fail "T09 task status — wrong fields" "status=$STATUS completed=$COMPLETED"
  fi
else
  fail "T09 task status in_progress->completed" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T10: task status — terminal state blocks outgoing
# --------------------------------------------------------------------- #
OUT="$(run_state task status t01 pending 2>&1 || true)"
if echo "$OUT" | grep -qF "illegal transition"; then
  ok "T10 task status — terminal state blocks outgoing"
else
  fail "T10 task status — terminal state" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T11: task status — pending -> in_progress blocked (no assign)
# --------------------------------------------------------------------- #
run_state task create t11 --title "No assign" >/dev/null 2>&1
OUT="$(run_state task status t11 in_progress 2>&1 || true)"
if echo "$OUT" | grep -qF "illegal transition"; then
  ok "T11 task status — pending->in_progress without assign blocked"
else
  fail "T11 task status — pending->in_progress without assign" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T12: task status — completed without assign blocked
# --------------------------------------------------------------------- #
run_state task create t12 --title "No assign complete" >/dev/null 2>&1
OUT="$(run_state task status t12 completed 2>&1 || true)"
if echo "$OUT" | grep -qF "no assigned_to set"; then
  ok "T12 task status — completed without assign blocked"
else
  fail "T12 task status — completed without assign" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T13: task fail
# --------------------------------------------------------------------- #
run_state task create t13 --title "To fail" >/dev/null 2>&1
run_state task assign t13 agent-alpha >/dev/null 2>&1
run_state task status t13 in_progress >/dev/null 2>&1
OUT="$(run_state task fail t13)"
if echo "$OUT" | grep -qF "in_progress -> failed"; then
  STATUS="$(jq -r '.tasks.t13.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "failed" ]; then
    ok "T13 task fail"
  else
    fail "T13 task fail — wrong status" "status=$STATUS"
  fi
else
  fail "T13 task fail" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T14: task cancel
# --------------------------------------------------------------------- #
run_state task create t14 --title "To cancel" >/dev/null 2>&1
OUT="$(run_state task cancel t14)"
if echo "$OUT" | grep -qF "pending -> cancelled"; then
  STATUS="$(jq -r '.tasks.t14.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "cancelled" ]; then
    ok "T14 task cancel"
  else
    fail "T14 task cancel — wrong status" "status=$STATUS"
  fi
else
  fail "T14 task cancel" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T15: invalid transition — cancelled -> in_progress
# --------------------------------------------------------------------- #
OUT="$(run_state task status t14 in_progress 2>&1 || true)"
if echo "$OUT" | grep -qF "illegal transition"; then
  ok "T15 invalid transition — cancelled->in_progress rejected"
else
  fail "T15 invalid transition — cancelled->in_progress" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T16: task deps add
# --------------------------------------------------------------------- #
run_state task create t16 --title "Deps test" >/dev/null 2>&1
OUT="$(run_state task deps t16 add t01 t02)"
if echo "$OUT" | grep -qF "added 2 new dependency"; then
  DEPS="$(jq -r '.tasks.t16.dependencies | sort | join(",")' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$DEPS" = "t01,t02" ]; then
    ok "T16 task deps add"
  else
    fail "T16 task deps add — wrong deps" "deps=$DEPS"
  fi
else
  fail "T16 task deps add" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T17: task deps add — no-op for existing
# --------------------------------------------------------------------- #
OUT="$(run_state task deps t16 add t01)"
if echo "$OUT" | grep -qF "no new dependencies"; then
  ok "T17 task deps add — existing dep is no-op"
else
  fail "T17 task deps add — existing dep" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T18: task deps add — self-dependency error
# --------------------------------------------------------------------- #
OUT="$(run_state task deps t16 add t16 2>&1 || true)"
if echo "$OUT" | grep -qF "task cannot depend on itself"; then
  ok "T18 task deps add — self-dependency rejected"
else
  fail "T18 task deps add — self-dependency" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T19: blocked-detect — no blocked tasks
# --------------------------------------------------------------------- #
OUT="$(run_state task blocked-detect)"
if echo "$OUT" | grep -qF "no tasks newly blocked"; then
  ok "T19 blocked-detect — no blocked tasks"
else
  fail "T19 blocked-detect — no blocked" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T20: blocked-detect — detects blocked task
# --------------------------------------------------------------------- #
# t02 depends on t03 which doesn't exist → t02 should be detected as blocked
# But t02 is pending, and Model 3 says pending is never auto-blocked.
# Let's create t20 with deps on incomplete tasks and assign it.
run_state task create t20 --title "Blockable" --depends-on t99 >/dev/null 2>&1
run_state task assign t20 agent-alpha >/dev/null 2>&1
OUT="$(run_state task blocked-detect)"
if echo "$OUT" | grep -qF "blocked:"; then
  STATUS="$(jq -r '.tasks.t20.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "blocked" ]; then
    ok "T20 blocked-detect — detects blocked task"
  else
    fail "T20 blocked-detect — status not blocked" "status=$STATUS"
  fi
else
  fail "T20 blocked-detect — not detected" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T21: blocked -> in_progress (allowed transition)
# --------------------------------------------------------------------- #
# blocked -> in_progress is in the transition table
OUT="$(run_state task status t20 in_progress 2>&1 || true)"
if echo "$OUT" | grep -qF "blocked -> in_progress"; then
  STATUS="$(jq -r '.tasks.t20.status' "$TEST_DIR/tasks/$TEST_GOAL/tasks.json")"
  if [ "$STATUS" = "in_progress" ]; then
    ok "T21 blocked -> in_progress transition"
  else
    fail "T21 blocked -> in_progress — wrong status" "status=$STATUS"
  fi
else
  fail "T21 blocked -> in_progress" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T22: query pending
# --------------------------------------------------------------------- #
OUT="$(run_state query pending)"
if echo "$OUT" | grep -qF "ID"; then
  PENDING_COUNT="$(echo "$OUT" | grep -c "t02\|t05\|t11\|t12\|t16\|t20" || true)"
  if [ "$PENDING_COUNT" -ge 1 ]; then
    ok "T22 query pending"
  else
    fail "T22 query pending — no pending tasks found" "$OUT"
  fi
else
  fail "T22 query pending" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T23: query agent
# --------------------------------------------------------------------- #
OUT="$(run_state query agent agent-alpha)"
if echo "$OUT" | grep -qF "ID"; then
  ok "T23 query agent"
else
  fail "T23 query agent" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T24: query status
# --------------------------------------------------------------------- #
OUT="$(run_state query status completed)"
if echo "$OUT" | grep -qF "t01"; then
  ok "T24 query status"
else
  fail "T24 query status" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T25: log tail — empty events
# --------------------------------------------------------------------- #
# Events file should exist from previous operations
if [ -f "$TEST_DIR/tasks/events.jsonl" ]; then
  OUT="$(STATE_ROOT="$TEST_DIR/tasks" bash "$STATE" log tail -n 5)"
  if echo "$OUT" | grep -qF "task.created"; then
    ok "T25 log tail — shows events"
  else
    fail "T25 log tail — no events" "$OUT"
  fi
else
  fail "T25 log tail — events file missing" ""
fi

# --------------------------------------------------------------------- #
# TEST T26: goal resolution — single goal auto-selected
# --------------------------------------------------------------------- #
# We're already using a single goal, so resolve_goal should work without --goal
OUT="$(STATE_ROOT="$TEST_DIR/tasks" bash "$STATE" query pending "$TEST_GOAL" 2>&1)"
if [ $? -eq 0 ]; then
  ok "T26 goal resolution — single goal"
else
  fail "T26 goal resolution — single goal" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T27: goal resolution — no goals error
# --------------------------------------------------------------------- #
EMPTY_DIR="$TEST_DIR/empty-tasks"
mkdir -p "$EMPTY_DIR"
OUT="$(STATE_ROOT="$EMPTY_DIR" bash "$STATE" query pending 2>&1 || true)"
if echo "$OUT" | grep -qF "no goals exist"; then
  ok "T27 goal resolution — no goals error"
else
  fail "T27 goal resolution — no goals" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T28: goal resolution — multiple goals error
# --------------------------------------------------------------------- #
MULTI_DIR="$TEST_DIR/multi-tasks"
mkdir -p "$MULTI_DIR/goalA" "$MULTI_DIR/goalB"
echo '{}' > "$MULTI_DIR/goalA/tasks.json"
echo '{}' > "$MULTI_DIR/goalB/tasks.json"
OUT="$(STATE_ROOT="$MULTI_DIR" bash "$STATE" query pending 2>&1 || true)"
if echo "$OUT" | grep -qF "multiple goals found"; then
  ok "T28 goal resolution — multiple goals error"
else
  fail "T28 goal resolution — multiple goals" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T29: invalid status
# --------------------------------------------------------------------- #
OUT="$(run_state task status t01 invalid_status 2>&1 || true)"
if echo "$OUT" | grep -qF "invalid status"; then
  ok "T29 invalid status rejected"
else
  fail "T29 invalid status" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T30: invalid id
# --------------------------------------------------------------------- #
OUT="$(run_state task create "bad/id" --title "Bad" 2>&1 || true)"
if echo "$OUT" | grep -qF "invalid id"; then
  ok "T30 invalid id rejected"
else
  fail "T30 invalid id" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T31: task not found
# --------------------------------------------------------------------- #
OUT="$(run_state task assign nonexistent agent-alpha 2>&1 || true)"
if echo "$OUT" | grep -qF "not found"; then
  ok "T31 task not found error"
else
  fail "T31 task not found" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T32: --by flag
# --------------------------------------------------------------------- #
run_state task create t32 --title "By test" >/dev/null 2>&1
BY_EVENT="$(jq -r 'select(.event == "task.created") | .by' "$TEST_DIR/tasks/events.jsonl" | tail -1)"
if [ "$BY_EVENT" = "tool" ]; then
  ok "T32 --by flag (default: tool)"
else
  fail "T32 --by flag" "by=$BY_EVENT (expected tool)"
fi

# --------------------------------------------------------------------- #
# TEST T33: events.jsonl — all events are valid JSON
# --------------------------------------------------------------------- #
INVALID_LINES=0
LINE_NO=0
while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))
  if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
    INVALID_LINES=$((INVALID_LINES + 1))
  fi
done < "$TEST_DIR/tasks/events.jsonl"
if [ "$INVALID_LINES" = "0" ]; then
  ok "T33 events.jsonl — all lines valid JSON"
else
  fail "T33 events.jsonl — invalid lines" "count=$INVALID_LINES"
fi

# --------------------------------------------------------------------- #
# TEST T34: task create — invalid id with special chars
# --------------------------------------------------------------------- #
OUT="$(run_state task create "bad id" --title "Space" 2>&1 || true)"
if echo "$OUT" | grep -qF "invalid id"; then
  ok "T34 invalid id with space rejected"
else
  fail "T34 invalid id with space" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T35: task status — missing args
# --------------------------------------------------------------------- #
OUT="$(run_state task status 2>&1 || true)"
if echo "$OUT" | grep -qF "requires an id"; then
  ok "T35 task status — missing args error"
else
  fail "T35 task status — missing args" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T36: query invalid kind
# --------------------------------------------------------------------- #
OUT="$(run_state query invalid 2>&1 || true)"
if echo "$OUT" | grep -qF "unknown query kind"; then
  ok "T36 query invalid kind error"
else
  fail "T36 query invalid kind" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T37: log tail — missing args
# --------------------------------------------------------------------- #
OUT="$(STATE_ROOT="$TEST_DIR/tasks" bash "$STATE" log tail -n abc 2>&1 || true)"
if echo "$OUT" | grep -qF "requires a non-negative integer"; then
  ok "T37 log tail — invalid -n"
else
  fail "T37 log tail — invalid -n" "$OUT"
fi

# --------------------------------------------------------------------- #
# TEST T38: task deps — missing args
# --------------------------------------------------------------------- #
OUT="$(run_state task deps t01 2>&1 || true)"
if echo "$OUT" | grep -qF "only 'add' is supported"; then
  ok "T38 task deps — missing op error"
else
  fail "T38 task deps — missing op" "$OUT"
fi

# --------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------- #
echo
echo "=== Results ==="
echo "Total: $TOTAL"
echo "Pass:  $PASS_COUNT"
echo "Fail:  $FAIL_COUNT"
echo

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
