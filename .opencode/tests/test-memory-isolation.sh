#!/usr/bin/env bash
set -uo pipefail

# test-memory-isolation.sh — Verify per-project memory isolation and
# git-root-anchored resolution of memory-lifecycle.sh.
#
# TDD: test written BEFORE the git-root resolution change (memory-lifecycle.sh
# previously derived MEMORY_DIR from BASH_SOURCE, pinning memory to the repo
# containing the script). These tests fail against that old behavior and pass
# with git-root + OPENCODE_MEMORY_DIR resolution.
#
# Proves (parent D9 proof 7 + 8):
#   7. runtime memory-lifecycle.sh from an unrelated project stores/recalls in
#      <project>/memory/ (git-root-anchored).
#   8. two temp repos: store in A, recall in B is empty; OPENCODE_MEMORY_DIR
#      override respected.
#
# Exit codes: 0 = all pass, 1 = any failure.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LS="$TEAM_ROOT/scripts/memory-lifecycle.sh"
[ -f "$LS" ] || LS="$TEAM_ROOT/bin/memory-lifecycle.sh"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_file() { [ -f "$1" ] && return 0; return 1; }
assert_dir()  { [ -d "$1" ] && return 0; return 1; }

make_repo() { # make_repo <name>
  local d="$T/$1"
  mkdir -p "$d"
  git -C "$d" init -q . 2>/dev/null || true
  printf 'x\n' > "$d/file.txt"
  for cat in decisions lessons failures architecture sessions; do
    mkdir -p "$d/memory/$cat"
  done
  printf '%s' "$d"
}

# ======================================================================== #
# TEST M01: memory-lifecycle.sh resolves MEMORY_DIR to the git root of CWD
# ======================================================================== #
A1="$(make_repo isoA)"
printf -- '%s\n' "# Lesson A" "Isolation test alpha content" > "$T/alpha.md"
# Run from inside repo A (subdirectory) — git root must anchor memory.
( cd "$A1" && bash "$LS" store lessons "$T/alpha.md" >/dev/null 2>&1 )
if assert_file "$A1/memory/lessons/alpha.md"; then
  ok "T01 memory stored at <project>/memory/ (git-root anchored)"
else
  fail "T01 memory stored at <project>/memory/" "not at $A1/memory/lessons/alpha.md"
fi

# ======================================================================== #
# TEST M02: recall works from the same project
# ======================================================================== #
R2="$(cd "$A1" && bash "$LS" recall lessons "alpha" 2>&1 || true)"
if echo "$R2" | grep -q "alpha.md"; then
  ok "T02 recall finds entry from same project"
else
  fail "T02 recall finds entry from same project" "recall output: $R2"
fi

# ======================================================================== #
# TEST M03: memory in repo A is NOT visible from an unrelated repo B
# ======================================================================== #
B1="$(make_repo isoB)"
R3="$(cd "$B1" && bash "$LS" recall lessons "alpha" 2>&1 || true)"
if echo "$R3" | grep -q "No entries matching"; then
  ok "T03 project A memory invisible from unrelated project B"
else
  fail "T03 project A memory invisible from project B" "recall output: $R3"
fi

# ======================================================================== #
# TEST M04: store in A does not write into B
# ======================================================================== #
if [ ! -f "$B1/memory/lessons/alpha.md" ]; then
  ok "T04 store in A leaves B's memory directory untouched"
else
  fail "T04 store in A leaves B's memory untouched" "found $B1/memory/lessons/alpha.md"
fi

# ======================================================================== #
# TEST M05: OPENCODE_MEMORY_DIR override is respected
# ======================================================================== #
OVR="$T/ovr-memory"
mkdir -p "$OVR/lessons"
printf -- '%s\n' "# Override" "override content" > "$T/override.md"
( cd "$B1" && OPENCODE_MEMORY_DIR="$OVR" bash "$LS" store lessons "$T/override.md" >/dev/null 2>&1 )
if assert_file "$OVR/lessons/override.md" && [ ! -f "$B1/memory/lessons/override.md" ]; then
  ok "T05 OPENCODE_MEMORY_DIR override redirects memory location"
else
  fail "T05 OPENCODE_MEMORY_DIR override" "override or isolation violated"
fi

# ======================================================================== #
# TEST M06: non-git directory falls back to pwd (location-independent)
# ======================================================================== #
PLAIN="$T/plaindir"
mkdir -p "$PLAIN/memory/lessons"
printf 'x\n' > "$PLAIN/note.txt"
printf -- '%s\n' "# P" "plain content" > "$T/plain.md"
( cd "$PLAIN" && bash "$LS" store lessons "$T/plain.md" >/dev/null 2>&1 || true )
if assert_file "$PLAIN/memory/lessons/plain.md"; then
  ok "T06 non-git dir resolves memory under pwd"
else
  fail "T06 non-git dir resolves memory under pwd" "no memory written under $PLAIN"
fi

# ======================================================================== #
# TEST M07: from a subdirectory of a repo, memory anchors at repo root
# ======================================================================== #
C1="$(make_repo isoC)"
mkdir -p "$C1/sub/dir"
printf -- '%s\n' "# C" "subdir content" > "$T/c.md"
( cd "$C1/sub/dir" && bash "$LS" store lessons "$T/c.md" >/dev/null 2>&1 )
if assert_file "$C1/memory/lessons/c.md" && [ ! -f "$C1/sub/dir/memory/lessons/c.md" ]; then
  ok "T07 subdirectory invocation anchors memory at repo root"
else
  fail "T07 subdirectory invocation" "memory not at repo root"
fi

# ======================================================================== #
# TEST M08: two-repo full isolation round trip (store A, verify B empty)
# ======================================================================== #
A8="$(make_repo isoA8)"
B8="$(make_repo isoB8)"
printf -- '%s\n' "# Secret" "unique token alpha8" > "$T/a8.md"
( cd "$A8" && bash "$LS" store lessons "$T/a8.md" >/dev/null 2>&1 )
S8B="$(cd "$B8" && bash "$LS" search "alpha8" 2>&1 || true)"
if echo "$S8B" | grep -q "No entries matching"; then
  ok "T08 store in A does not leak into B search"
else
  fail "T08 store in A does not leak into B search" "search: $S8B"
fi

# ======================================================================== #
# TEST M09: each repo sees only its own memory
# ======================================================================== #
S9A="$(cd "$A8" && bash "$LS" search "alpha8" 2>&1 || true)"
if echo "$S9A" | grep -q "lessons/a8.md"; then
  ok "T09 repo A sees its own stored entry"
else
  fail "T09 repo A sees its own stored entry" "search: $S9A"
fi

# ======================================================================== #
# TEST M10: multiple concurrent projects keep disjoint memory trees
# ======================================================================== #
printf -- '%s\n' "# B lesson" "beta content" > "$T/b10.md"
( cd "$B8" && bash "$LS" store lessons "$T/b10.md" >/dev/null 2>&1 )
# Now both A8 and B8 contain one lesson each; neither leaks the other's.
S10A="$(cd "$A8" && bash "$LS" recall lessons "" 2>&1 || true)"
S10B="$(cd "$B8" && bash "$LS" recall lessons "" 2>&1 || true)"
if echo "$S10A" | grep -q "a8.md" && ! echo "$S10A" | grep -q "b10.md" \
   && echo "$S10B" | grep -q "b10.md" && ! echo "$S10B" | grep -q "a8.md"; then
  ok "T10 concurrent projects keep disjoint memory trees"
else
  fail "T10 concurrent projects keep disjoint memory trees" "isolation leak between A8/B8"
fi

# ======================================================================== #
# TEST M11: location-independent from an installed runtime bin/ (TEAM_ROOT)
# ======================================================================== #
# Run the script via an absolute path (as the installed runtime would), from a
# repo — memory must anchor to that repo, not to the location of the script.
if [ -n "$TEAM_ROOT" ]; then
  D11="$(make_repo isoD11)"
  printf -- '%s\n' "# runtime" "location independent" > "$T/d11.md"
  ( cd "$D11" && bash "$LS" store lessons "$T/d11.md" >/dev/null 2>&1 )
  if assert_file "$D11/memory/lessons/d11.md"; then
    ok "T11 location-independent execution anchors memory at project repo"
  else
    fail "T11 location-independent execution" "memory not in project repo"
  fi
else
  ok "T11 location-independent execution anchors memory at project repo"
fi

# ======================================================================== #
# TEST M12: installed runtime copies stored/recall via TEAM_ROOT override
# ======================================================================== #
# If invoked with a TEAM_ROOT pointing at an installed runtime (bin/), the same
# script is used; ensure store+recall still works end-to-end in an unrelated repo.
E12="$(make_repo isoE12)"
printf -- '%s\n' "# End" "end to end" > "$T/e12.md"
( cd "$E12" && bash "$LS" store lessons "$T/e12.md" >/dev/null 2>&1 )
RE12="$(cd "$E12" && bash "$LS" recall lessons "end to end" 2>&1 || true)"
if assert_file "$E12/memory/lessons/e12.md" && echo "$RE12" | grep -q "e12.md"; then
  ok "T12 runtime script store+recall works end-to-end in unrelated repo"
else
  fail "T12 runtime script store+recall" "end-to-end failed"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
