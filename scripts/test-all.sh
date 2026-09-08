#!/usr/bin/env bash
#
# test-all.sh — Run every test suite in the repo and report a combined result.
#
#   bash scripts/test-all.sh
#
# Exit code: 0 if all suites pass, non-zero if any suite fails.
# Optional: pass --verbose to show each suite's full output on failure.

set -uo pipefail
TEAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

SUITES=(test-agent-architecture test-memory-system test-repo-bootstrap test-integration)

BOLD=""
RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m"
  RESET="\033[0m"
fi

pass=0; fail=0
printf "${BOLD}=== Agent Team: full test run ===${RESET}\n\n"

for s in "${SUITES[@]}"; do
  script="$TEAM_ROOT/scripts/$s.sh"
  if [ ! -f "$script" ]; then
    printf "  %-28s ${BOLD}MISSING${RESET}\n" "$s"
    fail=$((fail + 1))
    continue
  fi
  out="$(bash "$script" 2>&1)"
  rc=$?

  # Count individual PASS/FAIL lines (uniform format: "PASS  T01 ..." / "PASS  I01 ...";
  # excludes the summary lines that also start with "PASS:"/"FAIL:").
  npass="$(printf '%s\n' "$out" | grep -cE '^PASS  [TI]' || true)"
  nfail="$(printf '%s\n' "$out" | grep -cE '^FAIL  [TI]' || true)"

  if [ "$rc" = "0" ]; then
    printf "  %-28s ${BOLD}PASS${RESET}  (%s checks)\n" "$s" "$npass"
    pass=$((pass + 1))
  else
    printf "  %-28s ${BOLD}FAIL${RESET}  (%s check(s) failed)\n" "$s" "$nfail"
    fail=$((fail + 1))
    if [ "$VERBOSE" = "1" ]; then
      printf '\n--- %s output ---\n%s\n--------------------------\n' "$s" "$out"
    fi
  fi
done

printf '\n%s=== RESULT ===%s\n' "$BOLD" "$RESET"
printf 'suites passed: %d   suites failed: %d   (total %d suites)\n' \
  "$pass" "$fail" "${#SUITES[@]}"

if [ "$fail" = "0" ]; then
  printf 'ALL SUITES PASS\n'
  exit 0
else
  printf 'FAILURES PRESENT\n'
  exit 1
fi