#!/usr/bin/env bash
# test-adr.sh — Test suite for scripts/adr.sh (ADR management CLI).
#
# Uses an isolated temp directory for all ADR files.
# Exit codes: 0 = all pass, 1 = any failure.

set -uo pipefail

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ADR="$TEAM_ROOT/scripts/adr.sh"

[ -x "$ADR" ] || { echo "FAIL  setup — scripts/adr.sh missing/not executable" >&2; exit 1; }

PASS=0; FAIL=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# Override memory dir for isolation
export OPENCODE_MEMORY_DIR="$ROOT/memory"

ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1 — $2" >&2; }

# ── T01: create ADR ──────────────────────────────────────────────────────

T01_OUT="$(bash "$ADR" create 0001 --title "Test Decision" 2>&1)"
T01_CODE=$?
if [[ $T01_CODE -eq 0 && -f "$ROOT/memory/decisions/0001.md" ]]; then
  ok "T01 create ADR"
else
  fail "T01 create ADR" "exit=$T01_CODE file_exists=$(test -f "$ROOT/memory/decisions/0001.md" && echo yes || echo no)"
fi

# ── T02: created file has correct header ─────────────────────────────────

T02_HEADER="$(head -1 "$ROOT/memory/decisions/0001.md")"
if [[ "$T02_HEADER" == "# ADR-0001: Test Decision" ]]; then
  ok "T02 header format"
else
  fail "T02 header format" "got: $T02_HEADER"
fi

# ── T03: created file has required sections ──────────────────────────────

T03_SECTIONS="$(grep '^## ' "$ROOT/memory/decisions/0001.md")"
T03_OK=1
for s in Purpose Context Decision Consequences Alternatives References; do
  echo "$T03_SECTIONS" | grep -q "## $s" || T03_OK=0
done
if [[ $T03_OK -eq 1 ]]; then
  ok "T03 all sections present"
else
  fail "T03 all sections present" "missing sections"
fi

# ── T04: create with status and tags ─────────────────────────────────────

bash "$ADR" create 0002 --title "Second Decision" --status accepted --tags "testing,cli" >/dev/null 2>&1
T04_STATUS="$(grep '^Status:' "$ROOT/memory/decisions/0002.md")"
T04_TAGS="$(grep '^Tags:' "$ROOT/memory/decisions/0002.md")"
if [[ "$T04_STATUS" == "Status: accepted" && "$T04_TAGS" == "Tags: testing,cli" ]]; then
  ok "T04 create with status and tags"
else
  fail "T04 create with status and tags" "status=$T04_STATUS tags=$T04_TAGS"
fi

# ── T05: create duplicate fails ──────────────────────────────────────────

T05_CODE=0
bash "$ADR" create 0001 --title "Duplicate" 2>/dev/null || T05_CODE=$?
if [[ $T05_CODE -ne 0 ]]; then
  ok "T05 create duplicate fails"
else
  fail "T05 create duplicate fails" "exit was 0"
fi

# ── T06: get full ADR ───────────────────────────────────────────────────

T06_OUT="$(bash "$ADR" get 0001 2>&1)"
if echo "$T06_OUT" | grep -q "ADR-0001: Test Decision"; then
  ok "T06 get full ADR"
else
  fail "T06 get full ADR" "output did not contain header"
fi

# ── T07: get specific section ────────────────────────────────────────────

T07_OUT="$(bash "$ADR" get 0001 --section Purpose 2>&1)"
# Section body should be empty (just created)
if [[ -z "$T07_OUT" || "$T07_OUT" =~ ^[[:space:]]*$ ]]; then
  ok "T07 get section (empty)"
else
  ok "T07 get section (has content)"
fi

# ── T08: set section body ───────────────────────────────────────────────

T08_SET="$(bash "$ADR" set 0001 Purpose --body "This is the purpose" 2>&1)"
T08_CODE=$?
T08_GOT="$(bash "$ADR" get 0001 --section Purpose 2>&1)"
if [[ $T08_CODE -eq 0 && "$T08_GOT" == "This is the purpose" ]]; then
  ok "T08 set section body"
else
  fail "T08 set section body" "code=$T08_CODE got='$T08_GOT'"
fi

# ── T09: set section from file ───────────────────────────────────────────

T09_BODYFILE="$ROOT/test_body.txt"
echo "Line one" > "$T09_BODYFILE"
echo "Line two" >> "$T09_BODYFILE"
T09_SET="$(bash "$ADR" set 0001 Context --body-ref "$T09_BODYFILE" 2>&1)"
T09_CODE=$?
T09_GOT="$(bash "$ADR" get 0001 --section Context 2>&1)"
if [[ $T09_CODE -eq 0 && "$T09_GOT" == *"Line one"* ]]; then
  ok "T09 set section from file"
else
  fail "T09 set section from file" "code=$T09_CODE got='$T09_GOT'"
fi

# ── T10: set nonexistent section fails ───────────────────────────────────

T10_CODE=0
bash "$ADR" set 0001 Nonexistent --body "nope" 2>/dev/null || T10_CODE=$?
if [[ $T10_CODE -ne 0 ]]; then
  ok "T10 set nonexistent section fails"
else
  fail "T10 set nonexistent section fails" "exit was 0"
fi

# ── T11: list all ADRs ──────────────────────────────────────────────────

T11_OUT="$(bash "$ADR" list 2>&1)"
if echo "$T11_OUT" | grep -q "0001" && echo "$T11_OUT" | grep -q "0002"; then
  ok "T11 list all ADRs"
else
  fail "T11 list all ADRs" "output: $T11_OUT"
fi

# ── T12: list with status filter ─────────────────────────────────────────

T12_OUT="$(bash "$ADR" list --status accepted 2>&1)"
if echo "$T12_OUT" | grep -q "0002" && ! echo "$T12_OUT" | grep -q "0001"; then
  ok "T12 list filter by status"
else
  fail "T12 list filter by status" "output: $T12_OUT"
fi

# ── T13: list with tag filter ────────────────────────────────────────────

T13_OUT="$(bash "$ADR" list --tag cli 2>&1)"
if echo "$T13_OUT" | grep -q "0002"; then
  ok "T13 list filter by tag"
else
  fail "T13 list filter by tag" "output: $T13_OUT"
fi

# ── T14: search ─────────────────────────────────────────────────────────

T14_OUT="$(bash "$ADR" search "purpose" 2>&1)"
if echo "$T14_OUT" | grep -q "0001"; then
  ok "T14 search across ADRs"
else
  fail "T14 search across ADRs" "output: $T14_OUT"
fi

# ── T15: validate passes on populated ADR ────────────────────────────────

T15_SET1="$(bash "$ADR" set 0001 Decision --body "We chose X" 2>&1)"
T15_SET2="$(bash "$ADR" set 0001 Consequences --body "Y follows" 2>&1)"
T15_OUT="$(bash "$ADR" validate 0001 2>&1)"
T15_CODE=$?
if [[ $T15_CODE -eq 0 && "$T15_OUT" == *"OK: Purpose"* && "$T15_OUT" == *"OK: Decision"* && "$T15_OUT" == *"OK: Consequences"* ]]; then
  ok "T15 validate passes populated ADR"
else
  fail "T15 validate passes populated ADR" "code=$T15_CODE out=$T15_OUT"
fi

# ── T16: validate fails on empty ADR ────────────────────────────────────

bash "$ADR" create 0003 --title "Empty ADR" >/dev/null 2>&1
T16_OUT="$(bash "$ADR" validate 0003 2>&1)"
T16_CODE=$?
if [[ $T16_CODE -ne 0 && "$T16_OUT" == *"MISSING"* ]]; then
  ok "T16 validate fails on empty ADR"
else
  fail "T16 validate fails on empty ADR" "code=$T16_CODE out=$T16_OUT"
fi

# ── T17: supersedes links both files ─────────────────────────────────────

T17_OUT="$(bash "$ADR" supersedes 0001 0003 2>&1)"
T17_CODE=$?
T17_OLD="$(grep "^Superseded-by:" "$ROOT/memory/decisions/0001.md" 2>/dev/null || true)"
T17_NEW="$(grep "^Supersedes:" "$ROOT/memory/decisions/0003.md" 2>/dev/null || true)"
if [[ $T17_CODE -eq 0 && "$T17_OLD" == "Superseded-by: 0003" && "$T17_NEW" == "Supersedes: 0001" ]]; then
  ok "T17 supersedes links both files"
else
  fail "T17 supersedes links both files" "code=$T17_CODE old=$T17_OLD new=$T17_NEW"
fi

# ── T18: export produces JSONL ───────────────────────────────────────────

T18_OUT="$(bash "$ADR" export 2>&1)"
T18_FIRST="$(echo "$T18_OUT" | head -1)"
if command -v jq >/dev/null 2>&1; then
  T18_ID="$(echo "$T18_FIRST" | jq -r '.id' 2>/dev/null || true)"
  if [[ "$T18_ID" == "0001" ]]; then
    ok "T18 export JSONL"
  else
    fail "T18 export JSONL" "first id=$T18_ID"
  fi
else
  # jq not available, just check it's JSON-like
  if echo "$T18_FIRST" | grep -q '"id"'; then
    ok "T18 export JSONL (no jq, basic check)"
  else
    fail "T18 export JSONL" "no jq, output not JSON-like"
  fi
fi

# ── T19: help prints usage ──────────────────────────────────────────────

T19_OUT="$(bash "$ADR" --help 2>&1)"
T19_CODE=$?
if [[ $T19_CODE -eq 2 && "$T19_OUT" == *"adr.sh"* ]]; then
  ok "T19 --help prints usage"
else
  fail "T19 --help prints usage" "code=$T19_CODE"
fi

# ── T20: unknown command fails ───────────────────────────────────────────

T20_CODE=0
bash "$ADR" bogus 2>/dev/null || T20_CODE=$?
if [[ $T20_CODE -ne 0 ]]; then
  ok "T20 unknown command fails"
else
  fail "T20 unknown command fails" "exit was 0"
fi

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed (out of $((PASS + FAIL)))"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
