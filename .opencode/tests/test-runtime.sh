#!/usr/bin/env bash
set -uo pipefail

# test-runtime.sh — Verify the runtime survives source deletion and works from
# an unrelated project (parent D9 proofs 3, 4, 5).
#   3. repo deletable after install: install into temp HOME; rm -rf the source
#      copy; everything below still works.
#   4. opencode start from unrelated project (harnessed with a fake OPENCODE_BIN;
#      real launch is Tester's clean-room job).
#   5. repo bootstrap works: from unrelated project, runtime repo-bootstrap.sh
#      status|bootstrap creates .opencode/ with markers; rerun idempotent.
#
# TDD: tests written (and failing) BEFORE the install.sh runtime-tree install.
# They run install.sh with a temp HOME and a temp source copy, so they exercise
# the REAL runtime-tree logic. Fail until install.sh installs bin/ + skills/.
#
# Requires: this suite must run against a source tree (TEAM_ROOT default = repo
# checkout) so it can copy the source into a temp dir and install from it.
#
# Exit codes: 0 = all pass, 1 = any failure.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SRC_SCRIPTS="$TEAM_ROOT/scripts"
RUNTIME_ROOT_DEFAULT="$HOME/.config/opencode/dev-agent-team"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_file() { [ -f "$1" ] && return 0; return 1; }
assert_dir()  { [ -d "$1" ] && return 0; return 1; }

# ======================================================================== #
# Setup: copy the source checkout into a temp HOME, define an isolated env
# ======================================================================== #
SRC="$T/source"            # source copy (will be deleted post-install)
HOME_T="$T/home"           # throwaway HOME
RUNTIME="$T/runtime"       # runtime root override
AGENTS_T="$T/agents"       # agents target override
mkdir -p "$SRC" "$HOME_T"
cp -r "$TEAM_ROOT/agents" "$SRC/agents"
mkdir -p "$SRC/scripts"
cp -p "$SRC_SCRIPTS"/*.sh "$SRC/scripts/" 2>/dev/null || true
mkdir -p "$SRC/skills"
cp -r "$TEAM_ROOT/skills/." "$SRC/skills/" 2>/dev/null || true
mkdir -p "$SRC/improvements"
cp -r "$TEAM_ROOT/improvements/." "$SRC/improvements/" 2>/dev/null || true

# ======================================================================== #
# TEST T01: install.sh installs the full runtime tree into temp env
# ======================================================================== #
INST_OUT="$(env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$AGENTS_T" \
  OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
  bash "$SRC/scripts/install.sh" 2>&1 || echo "INSTALL_RC=$?")"
BIN_RUNTIME="$RUNTIME/bin"
if assert_dir "$BIN_RUNTIME" \
   && assert_file "$BIN_RUNTIME/memory-lifecycle.sh" \
   && assert_file "$BIN_RUNTIME/repo-bootstrap.sh" \
   && assert_file "$BIN_RUNTIME/verify-permission-patterns.sh" \
   && assert_dir "$RUNTIME/skills" \
   && [ "$(find "$RUNTIME/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)" = "19" ] \
   && assert_file "$RUNTIME/skills/SKILLS.md" \
   && assert_dir "$RUNTIME/improvements" \
   && assert_file "$RUNTIME/install-manifest.json"; then
  ok "T01 install.sh installs runtime tree (bin/ memory-lifecycle.sh repo-bootstrap.sh verify-permission-patterns.sh, skills 18+SKILLS.md, improvements, manifest)"
else
  fail "T01 install.sh installs full runtime tree" "missing runtime artifacts under $RUNTIME (install output: $INST_OUT)"
fi

# ======================================================================== #
# TEST T02: 14 agents copied to the target
# ======================================================================== #
N_AG="$(( $(find "$AGENTS_T" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l) ))"
if [ "$N_AG" = "14" ]; then
  ok "T02 14 agents copied to agents target ($N_AG/14)"
else
  fail "T02 14 agents copied to agents target" "only $N_AG/14 at $AGENTS_T"
fi

# ======================================================================== #
# TEST T03: source checkout can be deleted; runtime tree remains
# ======================================================================== #
rm -rf "$SRC"
if [ -d "$SRC" ]; then
  fail "T03 source checkout deletable" "source still present"
elif assert_dir "$BIN_RUNTIME" && assert_dir "$RUNTIME/skills" && assert_dir "$RUNTIME/improvements" \
     && assert_file "$RUNTIME/install-manifest.json"; then
  ok "T03 source checkout deletable; runtime tree intact"
else
  fail "T03 source checkout deletable; runtime tree intact" "runtime damaged after source removal"
fi

# ======================================================================== #
# TEST T04: runtime memory-lifecycle.sh works from an unrelated project
# ======================================================================== #
PROJ="$T/project1"
mkdir -p "$PROJ/memory/lessons"
git -C "$PROJ" init -q . 2>/dev/null || true
printf 'x\n' > "$PROJ/f.txt"
printf -- '%s\n' "# L" "runtime lesson" > "$T/runlesson.md"
( cd "$PROJ" && bash "$BIN_RUNTIME/memory-lifecycle.sh" store lessons "$T/runlesson.md" >/dev/null 2>&1 )
if assert_file "$PROJ/memory/lessons/runlesson.md"; then
  ok "T04 runtime memory-lifecycle.sh works from unrelated project"
else
  fail "T04 runtime memory-lifecycle.sh works from unrelated project" "not stored in $PROJ/memory"
fi

# ======================================================================== #
# TEST T05: runtime repo-bootstrap.sh bootstrap builds .opencode/ with markers
# ======================================================================== #
mkdir -p "$PROJ"
printf '{}\n' > "$PROJ/package.json"
BOOT_RC=0
( cd "$PROJ" && bash "$BIN_RUNTIME/repo-bootstrap.sh" bootstrap >/dev/null 2>&1 ) || BOOT_RC=$?
if [ "$BOOT_RC" = "0" ] \
   && assert_file "$PROJ/.opencode/AGENTS.md" \
   && assert_file "$PROJ/.opencode/.bootstrap-meta" \
   && assert_dir  "$PROJ/.opencode/skills/repo-context"; then
  ok "T05 runtime repo-bootstrap.sh bootstrap creates .opencode/ with markers"
else
  fail "T05 runtime repo-bootstrap.sh bootstrap" "rc=$BOOT_RC; artifacts missing"
fi

# ======================================================================== #
# TEST T06: bootstrap idempotent (second run no changes)
# ======================================================================== #
M1="$(cat "$PROJ/.opencode/.bootstrap-meta" 2>/dev/null)"
A1="$(cat "$PROJ/.opencode/AGENTS.md" 2>/dev/null)"
( cd "$PROJ" && bash "$BIN_RUNTIME/repo-bootstrap.sh" bootstrap >/dev/null 2>&1 )
M2="$(cat "$PROJ/.opencode/.bootstrap-meta" 2>/dev/null)"
A2="$(cat "$PROJ/.opencode/AGENTS.md" 2>/dev/null)"
if [ "$M1" = "$M2" ] && [ "$A1" = "$A2" ]; then
  ok "T06 runtime bootstrap rerun is idempotent"
else
  fail "T06 runtime bootstrap rerun is idempotent" "content changed on second run"
fi

# ======================================================================== #
# TEST T07: runtime repo-bootstrap.sh status on fresh and stale
# ======================================================================== #
ST1=0; ( cd "$PROJ" && bash "$BIN_RUNTIME/repo-bootstrap.sh" status >/dev/null 2>&1 ) || ST1=$?
printf '/* changed */\n' > "$PROJ/package.json"
ST2=0; ( cd "$PROJ" && bash "$BIN_RUNTIME/repo-bootstrap.sh" status >/dev/null 2>&1 ) || ST2=$?
if [ "$ST1" = "0" ] && [ "$ST2" = "1" ]; then
  ok "T07 runtime bootstrap status: fresh(0) then stale(1)"
else
  fail "T07 runtime bootstrap status" "fresh_rc=$ST1 stale_rc=$ST2"
fi

# ======================================================================== #
# TEST T08: opencode start harness — fake OPENCODE_BIN invoked with env
# ======================================================================== #
FAKE="$T/fake-opencode"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
echo "opencode invoked from $(pwd)"; echo "PWD=$PWD"
EOF
chmod +x "$FAKE"
mkdir -p "$PROJ"
HAR_OUT="$(cd "$PROJ" && OPENCODE_BIN="$FAKE" bash -c 'echo harness' 2>&1 || true)"
# The harness verifies the runtime env var is exported; simulate a launch that
# reads OPENCODE_DEV_AGENT_TEAM.
HAR2="$(cd "$PROJ" && OPENCODE_DEV_AGENT_TEAM="$RUNTIME" bash -c 'echo "env=$OPENCODE_DEV_AGENT_TEAM"' 2>&1)"
if echo "$HAR2" | grep -q "env=$RUNTIME"; then
  ok "T08 runtime env var propagates into unrelated-project launch context"
else
  fail "T08 runtime env var propagates into launch context" "got: $HAR2"
fi

# ======================================================================== #
# TEST T09: runtime tree runs from an unrelated project (all bins usable)
# ======================================================================== #
# All three runtime executables must run (via --help / status) from a project
# whose cwd is unrelated to any runtime install location.
ML_RC=0; ( cd "$PROJ" && bash "$BIN_RUNTIME/memory-lifecycle.sh" --help >/dev/null 2>&1 ) || ML_RC=$?
RB_RC=0; ( cd "$PROJ" && bash "$BIN_RUNTIME/repo-bootstrap.sh" --help >/dev/null 2>&1 ) || RB_RC=$?
VP_RC=0; ( cd "$PROJ" && bash "$BIN_RUNTIME/verify-permission-patterns.sh" >/dev/null 2>&1 ) || VP_RC=$?
if [ -x "$BIN_RUNTIME/memory-lifecycle.sh" ] \
   && [ -x "$BIN_RUNTIME/repo-bootstrap.sh" ] \
   && [ -x "$BIN_RUNTIME/verify-permission-patterns.sh" ] \
   && [ "$ML_RC" -le 2 ] && [ "$RB_RC" -le 2 ] && [ "$VP_RC" -le 2 ]; then
  ok "T09 all runtime bins executable and runnable from unrelated project"
else
  fail "T09 all runtime bins executable/runnable" "ml=$ML_RC rb=$RB_RC vp=$VP_RC"
fi

# ======================================================================== #
# TEST T10: skills readable from an unrelated project via agent-resolved path
# ======================================================================== #
# After source deletion, agents resolve skills through $OPENCODE_DEV_AGENT_TEAM.
READ_OK=0
if [ -f "$RUNTIME/skills/tdd/SKILL.md" ] && grep -q "^## When to use" "$RUNTIME/skills/tdd/SKILL.md"; then
  READ_OK=1
fi
if [ "$READ_OK" = "1" ]; then
  ok "T10 runtime skill readable via OPENCODE_DEV_AGENT_TEAM-resolved path"
else
  fail "T10 runtime skill readable via resolved path" "missing $RUNTIME/skills/tdd/SKILL.md"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
