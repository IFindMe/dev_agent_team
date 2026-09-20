#!/usr/bin/env bash
# test-impact.sh — Test suite for scripts/impact.sh
#
# Creates hermetic memory/tasks/skills fixtures under /tmp and verifies
# the impact tool detects references and classifies risk correctly.
#
# Exit: 0 = all pass, 1 = any failure.

set -uo pipefail

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
IMPACT="$TEAM_ROOT/scripts/impact.sh"
[ -x "$IMPACT" ] || { echo "FAIL  setup — scripts/impact.sh missing/not executable" >&2; exit 1; }

PASS=0; FAIL=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1 — $2" >&2; }

# ---- Build hermetic fixture ----
FIXTURE="$ROOT/repo"
mkdir -p "$FIXTURE/memory/decisions" "$FIXTURE/memory/lessons" "$FIXTURE/memory/failures"
mkdir -p "$FIXTURE/skills/test-skill" "$FIXTURE/agents"
mkdir -p "$FIXTURE/src" "$FIXTURE/.tasks/test-goal"
mkdir -p "$FIXTURE/scripts"

cd "$FIXTURE"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Source files
echo '#!/usr/bin/env bash' > "$FIXTURE/src/foo.sh"
echo 'echo "hello"' >> "$FIXTURE/src/foo.sh"
echo '#!/usr/bin/env bash' > "$FIXTURE/src/bar.sh"
echo 'echo "world"' >> "$FIXTURE/src/bar.sh"
echo '#!/usr/bin/env bash' > "$FIXTURE/scripts/test-foo.sh"
echo '#!/usr/bin/env bash' > "$FIXTURE/scripts/agora.sh"

# Memory decisions referencing foo.sh
cat > "$FIXTURE/memory/decisions/test-decision.md" << 'MEOF'
# Decision: use foo.sh for processing
We decided to use src/foo.sh as the main entry point.
See also src/bar.sh for secondary processing.
MEOF

cat > "$FIXTURE/memory/decisions/other-decision.md" << 'MEOF'
# Decision: architecture
The architecture uses src/bar.sh for batch operations.
MEOF

# Lessons referencing test-foo
cat > "$FIXTURE/memory/lessons/test-lesson.md" << 'MEOF'
# Lesson: test-foo.sh needs isolation
scripts/test-foo.sh must run in an isolated temp directory.
MEOF

# Failures referencing agora
cat > "$FIXTURE/memory/failures/agora-failure.md" << 'MEOF'
# Failure: agora.sh crashed on empty input
scripts/agora.sh failed when given empty contributions.jsonl.
MEOF

# Task with foo.sh in title and description
cat > "$FIXTURE/.tasks/test-goal/tasks.json" << 'TJSON'
{
  "version": 1,
  "goal": "test-goal",
  "tasks": [
    {"id": "01", "title": "Fix foo.sh bug", "status": "pending", "description": "Fix the bug in src/foo.sh"},
    {"id": "02", "title": "Update bar.sh", "status": "in_progress", "description": "Update src/bar.sh for new schema"},
    {"id": "03", "title": "Write docs", "status": "completed", "description": "Write user documentation"}
  ]
}
TJSON

# Task markdown referencing foo
cat > "$FIXTURE/.tasks/test-goal/01-fix-foo.md" << 'MEOF'
# Task 01: Fix foo.sh
Fix the edge case in src/foo.sh line 45.
MEOF

# Skill referencing foo
cat > "$FIXTURE/skills/test-skill/SKILL.md" << 'MEOF'
---
name: test-skill
description: Test skill that references foo.sh
version: "1.0"
owner: Builder
---
# Test Skill
This skill works with src/foo.sh and src/bar.sh.
MEOF

# Agent referencing bar
cat > "$FIXTURE/agents/test-agent.md" << 'MEOF'
---
name: test-agent
description: Test agent
---
# Test Agent
This agent uses src/bar.sh for operations.
MEOF

# Initial commit
git add -A
git commit -q -m "initial"

# Change to foo.sh
echo '#!/usr/bin/env bash' > "$FIXTURE/src/foo.sh"
echo 'echo "hello world"' >> "$FIXTURE/src/foo.sh"
git add src/foo.sh
git commit -q -m "change foo.sh"

# Copy impact.sh into fixture
cp "$IMPACT" "$FIXTURE/scripts/impact.sh"
chmod +x "$FIXTURE/scripts/impact.sh"

# ====================================================================== #
# T01: Default diff detects changed files
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh 2>&1)"
if echo "$OUTPUT" | grep -q "Changed files: 1"; then
  ok "T01 default diff detects 1 changed file"
else
  fail "T01 default diff detects changed files" "$(echo "$OUTPUT" | head -3)"
fi

# ====================================================================== #
# T02: --files flag works
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh src/bar.sh" 2>&1)"
if echo "$OUTPUT" | grep -q "Changed files: 2"; then
  ok "T02 --files flag detects 2 files"
else
  fail "T02 --files flag" "$(echo "$OUTPUT" | head -3)"
fi

# ====================================================================== #
# T03: --section decisions only checks decisions
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --section decisions 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Decisions"; then
  ok "T03 --section decisions shows decisions section"
else
  fail "T03 --section decisions" "$(echo "$OUTPUT" | head -5)"
fi
if echo "$OUTPUT" | grep -q "Impact on Lessons"; then
  fail "T03 --section decisions should NOT show lessons" "lessons section leaked"
else
  ok "T03 --section decisions excludes other sections"
fi

# ====================================================================== #
# T04: --section lessons only checks lessons
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "scripts/test-foo.sh" --section lessons 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Lessons"; then
  ok "T04 --section lessons shows lessons section"
else
  fail "T04 --section lessons" "$(echo "$OUTPUT" | head -5)"
fi

# ====================================================================== #
# T05: --section tasks only checks tasks
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --section tasks 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Tasks"; then
  ok "T05 --section tasks shows tasks section"
else
  fail "T05 --section tasks" "$(echo "$OUTPUT" | head -5)"
fi

# ====================================================================== #
# T06: --section failures only checks failures
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "scripts/agora.sh" --section failures 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Memory Failures"; then
  ok "T06 --section failures shows failures section"
else
  fail "T06 --section failures" "$(echo "$OUTPUT" | head -5)"
fi

# ====================================================================== #
# T07: --section skills only checks skills
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --section skills 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Skills"; then
  ok "T07 --section skills shows skills section"
else
  fail "T07 --section skills" "$(echo "$OUTPUT" | head -5)"
fi

# ====================================================================== #
# T08: --section agents only checks agents
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/bar.sh" --section agents 2>&1)"
if echo "$OUTPUT" | grep -q "Impact on Agents"; then
  ok "T08 --section agents shows agents section"
else
  fail "T08 --section agents" "$(echo "$OUTPUT" | head -5)"
fi

# ====================================================================== #
# T09: Risk classification — in_progress task = HIGH
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/bar.sh" --section tasks 2>&1)"
if echo "$OUTPUT" | grep -q "\[HIGH\].*bar.sh" && echo "$OUTPUT" | grep -q "in_progress"; then
  ok "T09 in_progress task classified as HIGH"
else
  fail "T09 in_progress task = HIGH" "$(echo "$OUTPUT" | grep -i bar)"
fi

# ====================================================================== #
# T10: Risk classification — pending task = MEDIUM
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --section tasks 2>&1)"
if echo "$OUTPUT" | grep -q "\[MEDIUM\].*foo.sh" && echo "$OUTPUT" | grep -q "pending"; then
  ok "T10 pending task classified as MEDIUM"
else
  fail "T10 pending task = MEDIUM" "$(echo "$OUTPUT" | grep -i foo)"
fi

# ====================================================================== #
# T11: Risk classification — lessons are LOW by default
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "scripts/test-foo.sh" --section lessons 2>&1)"
if echo "$OUTPUT" | grep -q "\[LOW\].*test-lesson"; then
  ok "T11 lessons classified as LOW by default"
else
  fail "T11 lessons = LOW" "$(echo "$OUTPUT" | grep -i lesson)"
fi

# ====================================================================== #
# T12: --format json produces valid JSON
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --format json 2>&1)"
if echo "$OUTPUT" | jq -e . >/dev/null 2>&1; then
  ok "T12 --format json produces valid JSON"
else
  fail "T12 --format json" "invalid JSON output"
fi

# ====================================================================== #
# T13: JSON output has expected keys
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --format json 2>&1)"
if echo "$OUTPUT" | jq -e '.timestamp' >/dev/null 2>&1 \
   && echo "$OUTPUT" | jq -e '.changed_files' >/dev/null 2>&1 \
   && echo "$OUTPUT" | jq -e '.summary.total' >/dev/null 2>&1; then
  ok "T13 JSON has timestamp, changed_files, summary.total"
else
  fail "T13 JSON structure" "missing expected keys"
fi

# ====================================================================== #
# T14: No changed files = no report
# ====================================================================== #
# Create a clean fixture with no diff
CLEAN="$ROOT/clean"
mkdir -p "$CLEAN/memory/decisions" "$CLEAN/scripts"
cd "$CLEAN"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "nothing" > "$CLEAN/file.txt"
git add -A && git commit -q -m "init"
cp "$IMPACT" "$CLEAN/scripts/impact.sh"
chmod +x "$CLEAN/scripts/impact.sh"
OUTPUT="$(cd "$CLEAN" && bash scripts/impact.sh 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] && echo "$OUTPUT" | grep -q "No changed files"; then
  ok "T14 no diff = 'No changed files' message"
else
  fail "T14 no diff" "exit=$RC output=$(echo "$OUTPUT" | head -2)"
fi

# ====================================================================== #
# T15: --help exits 0
# ====================================================================== #
if cd "$FIXTURE" && bash scripts/impact.sh --help >/dev/null 2>&1; then
  ok "T15 --help exits 0"
else
  fail "T15 --help" "non-zero exit"
fi

# ====================================================================== #
# T16: Unknown flag exits 2
# ====================================================================== #
cd "$FIXTURE" && bash scripts/impact.sh --bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "T16 unknown flag exits 2" \
  || fail "T16 unknown flag exits 2" "wrong exit code $?"

# ====================================================================== #
# T17: Total count matches individual risk counts
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh src/bar.sh" --format json 2>&1)"
CRIT=$(echo "$OUTPUT" | jq '.summary.critical')
HIGH=$(echo "$OUTPUT" | jq '.summary.high')
MED=$(echo "$OUTPUT" | jq '.summary.medium')
LOW=$(echo "$OUTPUT" | jq '.summary.low')
TOTAL=$(echo "$OUTPUT" | jq '.summary.total')
EXPECTED=$((CRIT + HIGH + MED + LOW))
if [ "$TOTAL" -eq "$EXPECTED" ]; then
  ok "T17 total = critical+high+medium+low ($TOTAL = $EXPECTED)"
else
  fail "T17 total consistency" "total=$TOTAL sum=$EXPECTED"
fi

# ====================================================================== #
# T18: --verbose includes line numbers
# ====================================================================== #
OUTPUT="$(cd "$FIXTURE" && bash scripts/impact.sh --files "src/foo.sh" --section decisions --verbose 2>&1)"
if echo "$OUTPUT" | grep -q "line [0-9]"; then
  ok "T18 --verbose shows line numbers"
else
  fail "T18 --verbose line numbers" "$(echo "$OUTPUT" | head -5)"
fi

# ---- summary ----
echo "----"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
