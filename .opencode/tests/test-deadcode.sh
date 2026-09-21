#!/usr/bin/env bash
# test-deadcode.sh — Test suite for deadcode.sh
#
# Creates test fixtures and verifies detection logic.
# Run: bash scripts/test-deadcode.sh
# Exit: 0 all pass, 1 any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="/tmp/deadcode-test-$$"
DEADCODE="$TEAM_ROOT/scripts/deadcode.sh"

# Test counters
declare -i PASS_COUNT=0 FAIL_COUNT=0 TOTAL=0

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

cleanup() {
    rm -rf "$TEST_DIR"
}

assert_pass() {
    local test_name="$1"
    ((PASS_COUNT++)) || true
    ((TOTAL++)) || true
    echo "  PASS: $test_name"
}

assert_fail() {
    local test_name="$1" detail="${2:-}"
    ((FAIL_COUNT++)) || true
    ((TOTAL++)) || true
    echo "  FAIL: $test_name — $detail"
}

assert_exit_code() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        assert_pass "$test_name"
    else
        assert_fail "$test_name" "expected exit $expected, got $actual"
    fi
}

assert_contains() {
    local test_name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        assert_pass "$test_name"
    else
        assert_fail "$test_name" "output does not contain '$needle'"
    fi
}

assert_not_contains() {
    local test_name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        assert_fail "$test_name" "output should not contain '$needle'"
    else
        assert_pass "$test_name"
    fi
}

# --------------------------------------------------------------------- #
# Setup test fixtures
# --------------------------------------------------------------------- #

setup_fixtures() {
    mkdir -p "$TEST_DIR"/{scripts,skills/test-skill,agents,memory/decisions}
    
    # Create a shell script with a dead function
    cat > "$TEST_DIR/scripts/has_dead_func.sh" << 'EOF'
#!/usr/bin/env bash

dead_function() {
    echo "This function is never called"
}

used_function() {
    echo "This function is called"
}

main() {
    used_function
}

main "$@"
EOF
    chmod +x "$TEST_DIR/scripts/has_dead_func.sh"
    
    # Create another shell script that calls used_function
    cat > "$TEST_DIR/scripts/caller.sh" << 'EOF'
#!/usr/bin/env bash
source has_dead_func.sh
used_function
EOF
    chmod +x "$TEST_DIR/scripts/caller.sh"
    
    # Create a Python file with dead functions
    cat > "$TEST_DIR/scripts/dead_python.py" << 'EOF'
def dead_func():
    """Never imported or called"""
    pass

def used_func():
    """Called by main"""
    return 42

def main():
    used_func()

if __name__ == "__main__":
    main()
EOF
    
    # Create a skill with no references
    cat > "$TEST_DIR/skills/test-skill/SKILL.md" << 'EOF'
---
name: test-skill
description: Test skill for dead code detection
version: "1.0"
owner: toolsmith
---

# Test Skill

This skill is never referenced.
EOF
    
    # Create a skill that IS referenced
    mkdir -p "$TEST_DIR/skills/good-skill"
    cat > "$TEST_DIR/skills/good-skill/SKILL.md" << 'EOF'
---
name: good-skill
description: Well-referenced skill
version: "1.0"
owner: toolsmith
---

# Good Skill
EOF
    
    # Reference good-skill in orchestrator
    cat > "$TEST_DIR/agents/orchestrator.md" << 'EOF'
# Orchestrator

Skills: good-skill, systematic-debugging
EOF
    
    # Create memory with orphaned reference
    cat > "$TEST_DIR/memory/decisions/test-decision.md" << 'EOF'
# Test Decision

See scripts/nonexistent.sh for details.
Also see good-skill/SKILL.md which exists.
EOF
    
    # Create the referenced file
    mkdir -p "$TEST_DIR/memory/good-skill"
    cat > "$TEST_DIR/memory/good-skill/SKILL.md" << 'EOF'
placeholder
EOF
}

# --------------------------------------------------------------------- #
# Tests
# --------------------------------------------------------------------- #

test_help_flag() {
    echo "Test: --help flag"
    local output
    output=$(bash "$DEADCODE" --help 2>&1) || true
    assert_contains "help shows usage" "$output" "Usage:"
}

test_invalid_type() {
    echo "Test: invalid --type"
    local exit_code=0
    bash "$DEADCODE" --type invalid 2>/dev/null || exit_code=$?
    assert_exit_code "invalid type exits 2" 2 "$exit_code"
}

test_invalid_format() {
    echo "Test: invalid --format"
    local exit_code=0
    bash "$DEADCODE" --format xml 2>/dev/null || exit_code=$?
    assert_exit_code "invalid format exits 2" 2 "$exit_code"
}

test_missing_path_value() {
    echo "Test: missing --path value"
    local exit_code=0
    bash "$DEADCODE" --path 2>/dev/null || exit_code=$?
    assert_exit_code "missing path value exits 2" 2 "$exit_code"
}

test_shell_dead_function() {
    echo "Test: shell dead function detection"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell 2>&1) || true
    assert_contains "finds dead_function" "$output" "dead_function"
}

test_shell_used_function() {
    echo "Test: shell used function not reported"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell 2>&1) || true
    # used_function is called by caller.sh, so shouldn't be dead
    assert_not_contains "used_function not reported as dead" "$output" "used_function.*0 callers"
}

test_python_dead_function() {
    echo "Test: python dead function detection"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type python 2>&1) || true
    assert_contains "finds dead_func" "$output" "dead_func"
}

test_json_format() {
    echo "Test: JSON output format"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell --format json 2>&1) || true
    assert_contains "JSON contains timestamp" "$output" '"timestamp"'
    assert_contains "JSON contains candidates" "$output" '"candidates"'
    assert_contains "JSON contains summary" "$output" '"summary"'
}

test_stale_days() {
    echo "Test: --stale-days flag"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell --stale-days 1 2>&1) || true
    # With low stale-days, old functions should be HIGH
    assert_contains "stale-days flag accepted" "$output" "Dead Code Report"
}

test_exclude_pattern() {
    echo "Test: --exclude flag"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell --exclude "has_dead" 2>&1) || true
    assert_not_contains "excludes has_dead_func.sh" "$output" "has_dead_func.sh"
}

test_text_report_header() {
    echo "Test: text report header"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type shell 2>&1) || true
    assert_contains "report has timestamp" "$output" "Dead Code Report:"
    assert_contains "report has scanned count" "$output" "Scanned:"
}

test_memory_orphan() {
    echo "Test: orphaned memory detection"
    local output
    output=$(bash "$DEADCODE" --path "$TEST_DIR" --type memory 2>&1) || true
    assert_contains "finds orphaned scripts/nonexistent.sh" "$output" "scripts/nonexistent.sh"
}

# --------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------- #

trap cleanup EXIT

echo "=== Dead Code Detection Test Suite ==="
echo ""

setup_fixtures

test_help_flag
test_invalid_type
test_invalid_format
test_missing_path_value
test_shell_dead_function
test_shell_used_function
test_python_dead_function
test_json_format
test_stale_days
test_exclude_pattern
test_text_report_header
test_memory_orphan

echo ""
echo "=== Results ==="
echo "Total: $TOTAL"
echo "Pass:  $PASS_COUNT"
echo "Fail:  $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
