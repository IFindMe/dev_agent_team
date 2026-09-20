#!/usr/bin/env bash
set -uo pipefail

# test-install.sh — Verify the installer installs a working runtime and is
# idempotent (parent D9 proofs 1 and 2).
#   1. install works: temp HOME + temp source; run install; assert 14 agents,
#      runtime bin/ executables, skills 13+SKILLS.md, improvements scaffold,
#      manifest, and shell-rc export present.
#   2. install idempotent: second run produces byte-identical agents, single
#      manifest, backup stamps grow, KEEP_BACKUPS honored.
#
# TDD: tests written (and failing) BEFORE the install.sh runtime-tree install.
# They exercise the REAL install.sh in a temp HOME + temp source.
#
# Exit codes: 0 = all pass, 1 = any failure.

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC_SCRIPTS="$TEAM_ROOT/scripts"

PASS=0; FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL  $1 — $2" >&2; }

assert_file(){ [ -f "$1" ] && return 0; return 1; }
assert_dir() { [ -d "$1" ] && return 0; return 1; }

# ======================================================================== #
# Setup: temp source copy + temp HOME + isolated env
# ======================================================================== #
SRC="$T/source"
HOME_T="$T/home"
RUNTIME="$T/runtime"          # OPENCODE_DEV_AGENT_TEAM override
AGENTS_T="$T/agents"          # OPENCODE_AGENTS_DIR override
mkdir -p "$SRC" "$HOME_T"
cp -r "$TEAM_ROOT/agents" "$SRC/agents"
mkdir -p "$SRC/scripts" "$SRC/skills" "$SRC/improvements"
cp -p "$SRC_SCRIPTS"/*.sh "$SRC/scripts/" 2>/dev/null || true
cp -r "$TEAM_ROOT/skills/." "$SRC/skills/" 2>/dev/null || true
cp -r "$TEAM_ROOT/improvements/." "$SRC/improvements/" 2>/dev/null || true
# Guarantee the 14-agent gate passes (install shuts down if <14 at source).
N_SRC_AGENTS="$(( $(ls "$SRC"/agents/*.md 2>/dev/null | wc -l) ))"
if [ "$N_SRC_AGENTS" != "14" ]; then
  echo "FAIL  setup — source agents count $N_SRC_AGENTS (need 14)" >&2
  exit 1
fi

# ======================================================================== #
# TEST T01: install works — 14 agents copied to target
# ======================================================================== #
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$AGENTS_T" \
  OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
N_AG="$(( $(find "$AGENTS_T" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l) ))"
if [ "$N_AG" = "14" ]; then
  ok "T01 14 agents copied to agents target ($N_AG/14)"
else
  fail "T01 14 agents copied to agents target" "got $N_AG/14"
fi

# ======================================================================== #
# TEST T02: runtime bin/ executables installed
# ======================================================================== #
if [ -x "$RUNTIME/bin/memory-lifecycle.sh" ] \
   && [ -x "$RUNTIME/bin/repo-bootstrap.sh" ] \
   && [ -x "$RUNTIME/bin/verify-permission-patterns.sh" ] \
   && [ -x "$RUNTIME/bin/agora.sh" ] \
   && [ -x "$RUNTIME/bin/test-agora.sh" ]; then
  ok "T02 runtime bin/ has executable memory-lifecycle.sh repo-bootstrap.sh verify-permission-patterns.sh agora.sh test-agora.sh"
else
  fail "T02 runtime bin/ executables present" "missing/all non-executable in $RUNTIME/bin"
fi

# ======================================================================== #
# TEST T03: runtime skills 18 dirs + SKILLS.md installed
# ======================================================================== #
N_SK="$(find "$RUNTIME/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if [ "$N_SK" = "18" ] && assert_file "$RUNTIME/skills/SKILLS.md"; then
  ok "T03 runtime skills/ has 18 skill dirs + SKILLS.md"
else
  fail "T03 runtime skills installed" "dirs=$N_SK (want 18), SKILLS.md=$([ -f "$RUNTIME/skills/SKILLS.md" ] && echo present || echo MISSING)"
fi

# ======================================================================== #
# TEST T04: improvements scaffold installed (README + 3 dirs)
# ======================================================================== #
if assert_dir "$RUNTIME/improvements" && assert_dir "$RUNTIME/improvements/pending" \
   && assert_dir "$RUNTIME/improvements/applied" && assert_dir "$RUNTIME/improvements/rejected" \
   && assert_file "$RUNTIME/improvements/README.md"; then
  ok "T04 runtime improvements/ scaffold (README + pending/applied/rejected)"
else
  fail "T04 runtime improvements scaffold" "missing under $RUNTIME/improvements"
fi

# ======================================================================== #
# TEST T05: install-manifest.json written with file list + checksum
# ======================================================================== #
if assert_file "$RUNTIME/install-manifest.json" \
   && grep -q '"installed"' "$RUNTIME/install-manifest.json" \
   && grep -qi 'sha256\|checksum\|"version"' "$RUNTIME/install-manifest.json"; then
  ok "T05 install-manifest.json present with version + installed file list"
else
  fail "T05 install-manifest.json present" "missing or malformed at $RUNTIME/install-manifest.json"
fi

# ======================================================================== #
# TEST T06: shell-rc export of OPENCODE_DEV_AGENT_TEAM present (guarded)
# ======================================================================== #
RC_EXPORT=0
for rc in "$HOME_T/.bashrc" "$HOME_T/.profile"; do
  if [ -f "$rc" ] && grep -q 'OPENCODE_DEV_AGENT_TEAM' "$rc"; then
    RC_EXPORT=1
    break
  fi
done
if [ "$RC_EXPORT" = "1" ]; then
  ok "T06 shell-rc export of OPENCODE_DEV_AGENT_TEAM present (.bashrc or .profile)"
else
  fail "T06 shell-rc export present" "no export line in .bashrc/.profile under $HOME_T"
fi

# ======================================================================== #
# TEST T07: agents installed are byte-identical to source (cmp integrity)
# ======================================================================== #
INT_OK=1
for src in "$SRC"/agents/*.md; do
  name="$(basename "$src")"
  cmp -s "$src" "$AGENTS_T/$name" || { INT_OK=0; echo "    differs: $name" >&2; }
done
if [ "$INT_OK" = "1" ]; then
  ok "T07 installed agent files byte-identical to source (cmp -s)"
else
  fail "T07 installed agent files byte-identical" "one or more diffs"
fi

# ======================================================================== #
# TEST T08: idempotent — second run produces byte-identical agents
# ======================================================================== #
# Snapshot agent bytes after first run.
ADIR1="$T/agents1"; mkdir -p "$ADIR1"; cp -r "$AGENTS_T/." "$ADIR1/" 2>/dev/null
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$AGENTS_T" \
  OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
IDEM_OK=1
for src in "$SRC"/agents/*.md; do
  name="$(basename "$src")"
  if ! cmp -s "$ADIR1/$name" "$AGENTS_T/$name"; then IDEM_OK=0; fi
done
if [ "$IDEM_OK" = "1" ]; then
  ok "T08 second install run produces byte-identical agents"
else
  fail "T08 second install run byte-identical" "agent bytes changed on second run"
fi

# ======================================================================== #
# TEST T09: single manifest (not duplicated on re-run)
# ======================================================================== #
N_MAN="$(find "$RUNTIME" -maxdepth 1 -name 'install-manifest.json' 2>/dev/null | wc -l)"
if [ "$N_MAN" = "1" ] && assert_file "$RUNTIME/install-manifest.json"; then
  ok "T09 exactly one install-manifest.json after re-run"
else
  fail "T09 exactly one manifest after re-run" "found $N_MAN"
fi

# ======================================================================== #
# TEST T10: backup stamps grow on re-run (agent backup dir under target .backup)
# ======================================================================== #
# First run backed up nothing (fresh target) — but the agent backup policy is
# preserved. Re-running over a target with existing agents creates a backup.
# Force a backup by pre-seeding a same-named file, then re-run.
SEED="$T/seed"
mkdir -p "$SEED"
cp "$SRC/agents/orchestrator.md" "$SEED/orchestrator.md"
SEED_AGENTS="$T/agents_seed"
mkdir -p "$SEED_AGENTS"
cp "$SRC/agents/"*.md "$SEED_AGENTS/" 2>/dev/null
# Modify one file to differ from source so backup is meaningful.
printf '# changed\n' > "$SEED_AGENTS/orchestrator.md"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$SEED_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
NBACKUP="$(find "$SEED_AGENTS/.backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if [ "$NBACKUP" -ge 1 ]; then
  ok "T10 agent backup stamp dirs created on overwrite ($NBACKUP backup stamp(s))"
else
  fail "T10 agent backup stamp dirs created" "no .backup/<stamp> under $SEED_AGENTS"
fi

# ======================================================================== #
# TEST T11: runtime tree backup stamps grow on re-run + managed file restored
# ======================================================================== #
# Force a runtime backup: pre-seed a differing managed runtime file into the
# runtime tree, then re-run install. Assert (a) a new .backup/<stamp> dir was
# created for the runtime tree (count strictly increased) and (b) the seeded
# file was replaced with the source content (proving it was actually backed up
# before overwrite rather than merely skipped or crudely clobbered).
NBACKUP_RT_BEFORE="$(find "$RUNTIME/.backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
printf '# CHANGED runtime content\n' > "$RUNTIME/bin/repo-bootstrap.sh"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$AGENTS_T" \
  OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
NBACKUP_RT_AFTER="$(find "$RUNTIME/.backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if [ "$NBACKUP_RT_AFTER" -gt "$NBACKUP_RT_BEFORE" ] \
   && cmp -s "$SRC/scripts/repo-bootstrap.sh" "$RUNTIME/bin/repo-bootstrap.sh"; then
  ok "T11 runtime re-run over seeded differing file adds .backup stamp ($NBACKUP_RT_BEFORE -> $NBACKUP_RT_AFTER) + restores source content"
else
  fail "T11 runtime backup stamp mechanism present" \
    "stamps $NBACKUP_RT_BEFORE -> $NBACKUP_RT_AFTER, source_restored=$([ -f \"$RUNTIME/bin/repo-bootstrap.sh\" ] && cmp -s \"$SRC/scripts/repo-bootstrap.sh\" \"$RUNTIME/bin/repo-bootstrap.sh\" && echo yes || echo no)"
fi

# ======================================================================== #
# TEST T12: KEEP_BACKUPS=5 honored (no more than 5 agent backup stamps)
# ======================================================================== #
# Perform a series of re-installs against a seeded target; after many runs the
# .backup stamp-dir count must not exceed 5.
TGT="$T/ag_keep"
mkdir -p "$TGT"
cp "$SRC/agents/"*.md "$TGT/" 2>/dev/null
for i in 1 2 3 4 5 6 7 8; do
  # vary the orchestrator to force a backup each run (so stamps accumulate)
  printf "# variant $i\n" > "$TGT/orchestrator.md"
  env -i HOME="$HOME_T" \
    OPENCODE_AGENTS_DIR="$TGT" \
    OPENCODE_DEV_AGENT_TEAM="$RUNTIME" \
    bash "$SRC/scripts/install.sh" >/dev/null 2>&1 || true
done
NKEEP="$(find "$TGT/.backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if [ "$NKEEP" -le "5" ]; then
  ok "T12 KEEP_BACKUPS=5 honored (backup stamps = $NKEEP)"
else
  fail "T12 KEEP_BACKUPS=5 honored" "found $NKEEP backup stamps (cap 5)"
fi

# ======================================================================== #
# TEST T13: --uninstall removes manifest-tracked agents from TARGET
#           (14 -> 0) and leaves agent .backup/ in place
# ======================================================================== #
U13_RUNTIME="$T/runtime13"
U13_AGENTS="$T/agents13"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U13_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U13_RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
N_U13_BEFORE="$(find "$U13_AGENTS" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
mkdir -p "$U13_AGENTS/.backup/seed-stamp"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U13_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U13_RUNTIME" \
  bash "$SRC/scripts/install.sh" --uninstall </dev/null >/dev/null 2>&1
N_U13_AFTER="$(find "$U13_AGENTS" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
if [ "$N_U13_BEFORE" = "14" ] && [ "$N_U13_AFTER" = "0" ] \
   && [ -d "$U13_AGENTS/.backup" ]; then
  ok "T13 --uninstall removes manifest-tracked agents (14 -> $N_U13_AFTER), leaves .backup/"
else
  fail "T13 --uninstall removes agents, leaves .backup/" \
    "before=$N_U13_BEFORE after=$N_U13_AFTER backup_present=$([ -d "$U13_AGENTS/.backup" ] && echo yes || echo no)"
fi

# ======================================================================== #
# TEST T14: --uninstall (no purge) preserves improvements/ user data
#           and removes the rest of the runtime tree
# ======================================================================== #
U14_RUNTIME="$T/runtime14"
U14_AGENTS="$T/agents14"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U14_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U14_RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
mkdir -p "$U14_RUNTIME/improvements/pending"
printf '# keep me\n' > "$U14_RUNTIME/improvements/pending/keepme.md"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U14_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U14_RUNTIME" \
  bash "$SRC/scripts/install.sh" --uninstall </dev/null >/dev/null 2>&1
U14_KEEP="$(cat "$U14_RUNTIME/improvements/pending/keepme.md" 2>/dev/null)"
U14_BIN_GONE=0; [ ! -d "$U14_RUNTIME/bin" ] && U14_BIN_GONE=1
U14_SKILLS_GONE=0; [ ! -d "$U14_RUNTIME/skills" ] && U14_SKILLS_GONE=1
U14_MAN_GONE=0; [ ! -f "$U14_RUNTIME/install-manifest.json" ] && U14_MAN_GONE=1
if [ "$U14_KEEP" = "# keep me" ] \
   && [ "$U14_BIN_GONE" = "1" ] && [ "$U14_SKILLS_GONE" = "1" ] && [ "$U14_MAN_GONE" = "1" ]; then
  ok "T14 --uninstall preserves improvements/ user data, removes bin/ skills/ manifest"
else
  fail "T14 --uninstall preserves improvements & removes rest" \
    "keep='$U14_KEEP' bin_gone=$U14_BIN_GONE skills_gone=$U14_SKILLS_GONE man_gone=$U14_MAN_GONE"
fi

# ======================================================================== #
# TEST T15: --uninstall --purge removes the entire runtime root
#           INCLUDING improvements/ user data
# ======================================================================== #
U15_RUNTIME="$T/runtime15"
U15_AGENTS="$T/agents15"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U15_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U15_RUNTIME" \
  bash "$SRC/scripts/install.sh" >/dev/null 2>&1
mkdir -p "$U15_RUNTIME/improvements/pending"
printf '# purge me\n' > "$U15_RUNTIME/improvements/pending/purgeme.md"
env -i HOME="$HOME_T" \
  OPENCODE_AGENTS_DIR="$U15_AGENTS" \
  OPENCODE_DEV_AGENT_TEAM="$U15_RUNTIME" \
  bash "$SRC/scripts/install.sh" --uninstall --purge </dev/null >/dev/null 2>&1
if [ ! -d "$U15_RUNTIME" ]; then
  ok "T15 --uninstall --purge removes entire runtime root incl improvements/"
else
  fail "T15 --uninstall --purge removes entire runtime root" \
    "runtime root still present: $U15_RUNTIME"
fi

# ======================================================================== #
# Summary
# ======================================================================== #
echo
echo "==================== SUMMARY ===================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" = "0" ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES PRESENT"
exit $(( FAIL > 0 ? 1 : 0 ))
