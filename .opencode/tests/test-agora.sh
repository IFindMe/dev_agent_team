#!/usr/bin/env bash
# test-agora.sh — Phase 1 gate suite for scripts/agora.sh (Agora Git-DAG).
#
# Proves the Phase 1 contract per
#   AgentsReport/architect/2026-09-19_agora-mapping.md:208-209 and
#   .tasks/agora-phase1/04-tester-strategy.md:
#   (a) publish→log→show round-trip works;
#   (b) verify catches mutated lines, dangling parents, bad types, and
#       `wip` is rejected (publish-time AND verify-time);
#   (c) all 8 analyze views run on a hermetic 3-node fixture graph (+ a
#       7-node probe graph that exercises the views legitimately empty on
#       the small fixture). NO assertion pins live-seed values: the repo
#       seed is append-only by design and MAY grow via `publish` at any
#       time (post-gate 3→5 growth broke the old seed-pinned T15/T17 —
#       valid DAG use, not a tool defect).
#
# Strategy (skills/tdd + skills/test-analysis): behavior-level integration
# tests through the CLI only — no function sourcing, no implementation
# coupling. Every test CAN fail (asserts exit codes 0/1/2 per the tool's
# contract plus content checks on ids, scores, and view membership).
# Deterministic: fixed --ts/--by actors, fresh isolated AGORA_DIR per group.
#
# Isolation: each group gets a fresh dir under one mktemp root (trap-cleaned).
# The repo's agora/ is only EVER read (a copy is integrity-checked); the G5
# guard proves the suite performed no in-place repo mutation while
# tolerating legitimate append-only growth. agora.sh itself is read-only
# under test (never modified by this suite).
#
# Exit codes: 0 = all pass, 1 = any failure.

set -uo pipefail

TEAM_ROOT="${TEAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AGORA="$TEAM_ROOT/scripts/agora.sh"
SEED="$TEAM_ROOT/agora/contributions.jsonl"

[ -x "$AGORA" ] || { echo "FAIL  setup — scripts/agora.sh missing/not executable" >&2; exit 1; }
[ -f "$SEED" ] || { echo "FAIL  setup — agora/contributions.jsonl seed missing" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL  setup — jq not on PATH" >&2; exit 1; }

# Growth-tolerant repo-guard state: the live seed MAY grow via `publish`
# (append-only DAG, D1). We pin the APPEND-ONLY PREFIX (line count + sha of
# the first N lines), NOT the whole-file sha: legitimate appends preserve
# the prefix and pass; any in-place mutation/truncation breaks it and fails.
SEED_LINES_BEFORE="$(wc -l < "$SEED")"
SEED_HEAD_SHA="$(head -n "$SEED_LINES_BEFORE" "$SEED" | sha256sum | cut -d' ' -f1)"

PASS=0; FAIL=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1 — $2" >&2; }

# is_hex64 <s> — 64-hex sha256 shape check
is_hex64() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

FAKE_PARENT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# craft_line <dir> <parents-json> <type> <title> <tags-json> <by> <ts>
# Appends a CORRECTLY-ADDRESSED line (valid id) with caller-chosen fields, so
# verify's schema/parents checks — not the id check — are what fire.
craft_line() {
  local payload id line
  payload="$(jq -cn -S --argjson parents "$2" --arg type "$3" \
    --arg title "$4" --arg body_ref "" --argjson tags "$5" \
    --arg by "$6" --arg ts "$7" \
    '{parents:$parents,type:$type,title:$title,body_ref:$body_ref,tags:$tags,created_by:$by,ts:$ts}')"
  id="$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)"
  line="$(printf '%s' "$payload" | jq -cS --arg id "$id" '. + {id:$id}')"
  printf '%s\n' "$line" >> "$1/contributions.jsonl"
  printf '%s' "$id"
}

# ====================================================================== #
# G1: publish→log→show round-trip (+ verify OK on a clean log)
# ====================================================================== #
D1="$ROOT/g1"; mkdir -p "$D1"
ID1="$(AGORA_DIR="$D1" bash "$AGORA" publish --type result --title "Round-trip probe" \
  --tags probe,roundtrip --by tester --ts "2026-09-19T13:00:00Z" 2>"$D1/pub.err")"
ST=$?
if [ "$ST" -eq 0 ] && is_hex64 "$ID1"; then
  ok "T01 publish exits 0 and returns 64-hex id"
else
  fail "T01 publish returns 64-hex id" "exit=$ST id='$ID1' err=$(cat "$D1/pub.err")"
fi

if AGORA_DIR="$D1" bash "$AGORA" log 2>/dev/null | grep -q "$ID1"; then
  ok "T02 log contains the published id"
else
  fail "T02 log contains the published id" "id $ID1 absent from log"
fi

if AGORA_DIR="$D1" bash "$AGORA" show "${ID1:0:7}" 2>/dev/null | grep -q "Round-trip probe"; then
  ok "T03 show <7-char prefix> returns the contribution"
else
  fail "T03 show <7-char prefix> returns the contribution" "title not found via prefix"
fi

if AGORA_DIR="$D1" bash "$AGORA" verify >"$D1/verify.out" 2>&1; then
  ok "T04 verify exits 0 on the clean round-trip log"
else
  fail "T04 verify exits 0 on clean log" "$(cat "$D1/verify.out")"
fi

if AGORA_DIR="$D1" bash "$AGORA" show deadbeef 2>/dev/null; then
  fail "T05 show unknown prefix exits 1" "unexpectedly succeeded"
else
  [ $? -eq 1 ] && ok "T05 show unknown prefix exits 1" \
    || fail "T05 show unknown prefix exits 1" "wrong exit code $?"
fi

# ====================================================================== #
# G2: integrity negatives (publish-time rejections + verify-time catches)
# ====================================================================== #
D2="$ROOT/g2"; mkdir -p "$D2"

if AGORA_DIR="$D2" bash "$AGORA" publish --type wip --title "WIP must not land" \
    --by tester 2>/dev/null; then
  fail "T06 publish rejects type=wip" "wip was accepted into the DAG"
else
  [ $? -eq 1 ] && ok "T06 publish rejects type=wip (exit 1)" \
    || fail "T06 publish rejects type=wip" "wrong exit code $?"
fi

if AGORA_DIR="$D2" bash "$AGORA" publish --type verification --title "Unweighted verdict" \
    --tags probe --by tester --ts "2026-09-19T13:01:00Z" 2>/dev/null; then
  fail "T07 publish rejects verification without exactly one weight tag" "accepted"
else
  [ $? -eq 1 ] && ok "T07 publish rejects unweighted verification (exit 1)" \
    || fail "T07 publish rejects unweighted verification" "wrong exit code $?"
fi

if AGORA_DIR="$D2" bash "$AGORA" publish --type result --title "Orphan" \
    --parents "$FAKE_PARENT" --by tester --ts "2026-09-19T13:02:00Z" 2>/dev/null; then
  fail "T08 publish rejects dangling parent" "orphan was accepted"
else
  [ $? -eq 1 ] && ok "T08 publish rejects dangling parent (exit 1)" \
    || fail "T08 publish rejects dangling parent" "wrong exit code $?"
fi

# T09: mutated line — publish a good row, then tamper the title in place.
D29="$ROOT/g2-mut"; mkdir -p "$D29"
AGORA_DIR="$D29" bash "$AGORA" publish --type result --title "Original Title" \
  --by tester --ts "2026-09-19T13:03:00Z" >/dev/null 2>&1
sed -i 's/Original Title/MUTATED Title/' "$D29/contributions.jsonl"
if AGORA_DIR="$D29" bash "$AGORA" verify >"$D29/v.out" 2>&1; then
  fail "T09 verify catches mutated line" "tampered log verified OK"
else
  [ $? -eq 1 ] && grep -q "id mismatch" "$D29/v.out" \
    && ok "T09 verify catches mutated line (exit 1, id mismatch)" \
    || fail "T09 verify catches mutated line" "$(cat "$D29/v.out")"
fi

# T10: dangling parent at verify time — valid id, nonexistent parent.
D210="$ROOT/g2-dangle"; mkdir -p "$D210"
AGORA_DIR="$D210" bash "$AGORA" publish --type setup --title "Anchor" \
  --by tester --ts "2026-09-19T13:04:00Z" >/dev/null 2>&1
craft_line "$D210" "[\"$FAKE_PARENT\"]" "result" "Dangling child" "[]" \
  "tester" "2026-09-19T13:05:00Z" >/dev/null
if AGORA_DIR="$D210" bash "$AGORA" verify >"$D210/v.out" 2>&1; then
  fail "T10 verify catches dangling parent" "orphan log verified OK"
else
  [ $? -eq 1 ] && grep -q "dangling parent" "$D210/v.out" \
    && ok "T10 verify catches dangling parent (exit 1)" \
    || fail "T10 verify catches dangling parent" "$(cat "$D210/v.out")"
fi

# T11: bad type at verify time — valid id, type=wip (never a DAG member).
D211="$ROOT/g2-badtype"; mkdir -p "$D211"
AGORA_DIR="$D211" bash "$AGORA" publish --type setup --title "Anchor" \
  --by tester --ts "2026-09-19T13:06:00Z" >/dev/null 2>&1
craft_line "$D211" "[]" "wip" "WIP smuggled in" "[]" \
  "tester" "2026-09-19T13:07:00Z" >/dev/null
if AGORA_DIR="$D211" bash "$AGORA" verify >"$D211/v.out" 2>&1; then
  fail "T11 verify catches bad type (wip)" "wip line verified OK"
else
  [ $? -eq 1 ] && grep -q "bad type" "$D211/v.out" \
    && ok "T11 verify catches bad type wip (exit 1)" \
    || fail "T11 verify catches bad type wip" "$(cat "$D211/v.out")"
fi

# T12: usage errors exit 2 (contract: 0 ok / 1 violation / 2 usage).
AGORA_DIR="$D2" bash "$AGORA" publish --type result >/dev/null 2>&1
[ $? -eq 2 ] && ok "T12a publish missing --title exits 2" \
  || fail "T12a publish missing --title exits 2" "wrong exit code $?"
AGORA_DIR="$D2" bash "$AGORA" analyze bogus-view >/dev/null 2>&1
[ $? -eq 2 ] && ok "T12b analyze unknown view exits 2" \
  || fail "T12b analyze unknown view exits 2" "wrong exit code $?"

# ====================================================================== #
# G3: all 8 views on a HERMETIC 3-node fixture graph (never the live seed)
#
# Why hermetic: the live seed is append-only and grows via `publish`
# (3→5 post-gate broke the old seed-pinned T15/T17 — valid DAG use, not a
# tool defect). So G3 builds its own seed-SHAPED graph in an isolated /tmp
# AGORA_DIR (G4 technique: fixed --ts/--by publishes) and pins the
# FIXTURE's values. Live-seed growth cannot move these assertions.
#
# Fixture shape (mirrors the original 3-node gate seed):
#   F1 fix-base (setup, parents=[]) <- F2 fix-mid (result, [F1])
#                                    <- F3 fix-tip (result, [F1,F2])
# Distinct actors (fix-a/b/c) so every child is cited (default weight 1):
#   S(F1)=2, S(F2)=1, S(F3)=0 — pinned, deterministic, no live ids.
# ====================================================================== #
D3="$ROOT/g3"; mkdir -p "$D3"
Q() { AGORA_DIR="$D3" bash "$AGORA" publish "$@" 2>"$D3/pub.err"; }
F1="$(Q --type setup --title "fix-base" --tags fix,base --by fix-a --ts "2026-09-19T15:00:00Z")"
F2="$(Q --type result --title "fix-mid" --parents "$F1" --tags fix,mid --by fix-b --ts "2026-09-19T15:01:00Z")"
F3="$(Q --type result --title "fix-tip" --parents "$F1,$F2" --tags fix,tip --by fix-c --ts "2026-09-19T15:02:00Z")"

AGORA_DIR="$D3" bash "$AGORA" verify >/dev/null 2>&1 \
  && ok "T13 fixture log verifies clean" \
  || fail "T13 fixture log verifies clean" "verify failed on fixture graph: $(cat "$D3/pub.err")"

VIEWS="leaders most-built-on leaves underexplored unverified contested open-hypotheses clusters"
for v in $VIEWS; do
  if AGORA_DIR="$D3" bash "$AGORA" analyze "$v" >"$D3/view-$v.out" 2>"$D3/view-$v.err"; then
    ok "T14 view '$v' exits 0 on fixture graph"
  else
    fail "T14 view '$v' exits 0 on fixture graph" "$(cat "$D3/view-$v.err")"
  fi
done

# Fixture shape: F1 (2 children, S=2) <- F2 (1 child, S=1) <- F3 (S=0).
TOP_ID="$(head -n1 "$D3/view-leaders.out" | jq -r .id)"
TOP_S="$(head -n1 "$D3/view-leaders.out" | jq -r .S)"
if [ "$TOP_ID" = "$F1" ] \
   && [ "$TOP_S" = "2" ]; then
  ok "T15 leaders ranks fixture root first with S=2"
else
  fail "T15 leaders ranks fixture root first with S=2" "id=$TOP_ID S=$TOP_S (want id=$F1 S=2)"
fi

MBO_TOP="$(head -n1 "$D3/view-most-built-on.out" | jq -r '.id,.children' | tr '\n' ' ')"
[ "$MBO_TOP" = "$F1 2 " ] \
  && ok "T16 most-built-on ranks fixture root first with 2 children" \
  || fail "T16 most-built-on ranks fixture root first" "got: $MBO_TOP (want: $F1 2)"

if grep -q "$F3" "$D3/view-leaves.out" && ! grep -q "$F1" "$D3/view-leaves.out" \
   && ! grep -q "$F2" "$D3/view-leaves.out"; then
  ok "T17 leaves contains the fixture tip only"
else
  fail "T17 leaves contains the fixture tip only" "got: $(jq -r .id "$D3/view-leaves.out" | tr '\n' ' ')"
fi

if [ ! -s "$D3/view-contested.out" ] && [ ! -s "$D3/view-open-hypotheses.out" ]; then
  ok "T18 contested + open-hypotheses correctly empty on fixture (exit 0 already shown)"
else
  fail "T18 contested/open-hypotheses empty on fixture" "fixture has no refutes/hypotheses yet"
fi

[ "$(wc -l < "$D3/view-unverified.out")" -eq 3 ] \
  && ok "T19 unverified lists all 3 fixture rows (no verification children yet)" \
  || fail "T19 unverified lists all 3 fixture rows" "lines=$(wc -l < "$D3/view-unverified.out")"

if grep -q '"tag":"fix"' "$D3/view-clusters.out" \
   && [ "$(jq -r 'select(.tag == "fix") | .count' "$D3/view-clusters.out")" = "3" ]; then
  ok "T20 clusters groups fixture under tag 'fix' (count 3)"
else
  fail "T20 clusters groups fixture under tag 'fix'" "$(cat "$D3/view-clusters.out")"
fi

# ====================================================================== #
# G4: 7-node probe graph — views that are empty on seed must fire here
#   base <- mid <- {hyp-open <- leaf, hyp-shown <- ver-accept, ver-refute}
# ====================================================================== #
D4="$ROOT/g4"; mkdir -p "$D4"
P() { AGORA_DIR="$D4" bash "$AGORA" publish "$@" 2>"$D4/pub.err"; }
P1="$(P --type setup --title "probe-base" --tags probe,base --by probe-a --ts "2026-09-19T14:00:00Z")"
P2="$(P --type result --title "probe-mid" --parents "$P1" --tags probe,mid --by probe-b --ts "2026-09-19T14:01:00Z")"
P3="$(P --type hypothesis --title "probe-hyp-open" --parents "$P2" --tags probe,hyp --by probe-c --ts "2026-09-19T14:02:00Z")"
P4="$(P --type hypothesis --title "probe-hyp-shown" --parents "$P2" --tags probe,hyp --by probe-d --ts "2026-09-19T14:03:00Z")"
P5="$(P --type verification --title "probe-ver-accept" --parents "$P4" --tags +20,probe --by probe-e --ts "2026-09-19T14:04:00Z")"
P6="$(P --type verification --title "probe-ver-refute" --parents "$P2" --tags -20,probe --by probe-f --ts "2026-09-19T14:05:00Z")"
P7="$(P --type result --title "probe-leaf" --parents "$P3" --tags probe,leaf --by probe-g --ts "2026-09-19T14:06:00Z")"
if [ "$(AGORA_DIR="$D4" bash "$AGORA" log 2>/dev/null | wc -l)" -eq 7 ]; then
  ok "T21 probe graph publishes 7 chained rows"
else
  fail "T21 probe graph publishes 7 rows" "$(cat "$D4/pub.err")"
fi

AGORA_DIR="$D4" bash "$AGORA" verify >/dev/null 2>&1 \
  && ok "T22 verify OK on probe graph" \
  || fail "T22 verify OK on probe graph" "verify failed"
for v in $VIEWS; do
  AGORA_DIR="$D4" bash "$AGORA" analyze "$v" >"$D4/p-$v.out" 2>"$D4/p-$v.err" \
    && ok "T23 view '$v' exits 0 on probe graph" \
    || fail "T23 view '$v' exits 0 on probe graph" "$(cat "$D4/p-$v.err")"
done

CONTESTED_ID="$(jq -r .id "$D4/p-contested.out")"
if [ "$CONTESTED_ID" = "$P2" ] && jq -e --arg r "$P6" '.refuted_by | index($r)' "$D4/p-contested.out" >/dev/null; then
  ok "T24 contested flags probe-mid refuted_by probe-ver-refute"
else
  fail "T24 contested flags probe-mid" "got id=$CONTESTED_ID $(cat "$D4/p-contested.out")"
fi

OPEN_H="$(jq -r .id "$D4/p-open-hypotheses.out")"
if [ "$OPEN_H" = "$P3" ] && ! grep -q "$P4" "$D4/p-open-hypotheses.out"; then
  ok "T25 open-hypotheses lists hyp-open only (hyp-shown verified, excluded)"
else
  fail "T25 open-hypotheses lists hyp-open only" "got: $OPEN_H"
fi

if ! grep -q "$P4" "$D4/p-unverified.out" && ! grep -q "$P5" "$D4/p-unverified.out" \
   && grep -q "$P3" "$D4/p-unverified.out"; then
  ok "T26 unverified excludes verified hyp + verifications, keeps hyp-open"
else
  fail "T26 unverified membership" "$(jq -r .id "$D4/p-unverified.out" | tr '\n' ' ')"
fi

if grep -q "$P5" "$D4/p-leaves.out" && grep -q "$P6" "$D4/p-leaves.out" \
   && grep -q "$P7" "$D4/p-leaves.out" && ! grep -q "$P2" "$D4/p-leaves.out"; then
  ok "T27 leaves = ver-accept, ver-refute, leaf (mid has children, excluded)"
else
  fail "T27 leaves membership" "$(jq -r .id "$D4/p-leaves.out" | tr '\n' ' ')"
fi

MBO_P="$(head -n1 "$D4/p-most-built-on.out" | jq -r .id)"
[ "$MBO_P" = "$P2" ] \
  && ok "T28 most-built-on ranks probe-mid first (3 children)" \
  || fail "T28 most-built-on ranks probe-mid first" "got: $MBO_P"

AGORA_DIR="$D4" bash "$AGORA" log --type hypothesis 2>/dev/null | wc -l | grep -q 2 \
  && AGORA_DIR="$D4" bash "$AGORA" show "$P5" 2>/dev/null | grep -q "probe-ver-accept" \
  && ok "T29 log --type filter + show full-id work on probe graph" \
  || fail "T29 log --type filter + show full-id" "filter or full-id lookup failed"

# ====================================================================== #
# G5: live-seed integrity + no-repo-mutation guard (growth-tolerant)
#
# The live seed MAY grow via `publish` (append-only DAG, D1) — so this is
# NOT a whole-file sha-pin (a sha-pin false-fails on legitimate appends
# and conflates integrity with identity). T30 instead asserts:
#   (a) the live seed verifies OK on a read-only copy (schema +
#       recomputed content-addressed ids + parents-integrity);
#   (b) every line is valid JSON (JSONL validity);
#   (c) the append-only prefix present at suite start is intact
#       (no in-place mutation/truncation by this suite; pure appends pass).
# ====================================================================== #
D5="$ROOT/g5"; mkdir -p "$D5"
cp "$SEED" "$D5/contributions.jsonl"
T30_OK=1; T30_WHY=""
AGORA_DIR="$D5" bash "$AGORA" verify >"$D5/verify.out" 2>&1 \
  || { T30_OK=0; T30_WHY="verify: $(cat "$D5/verify.out")"; }
jq -e . "$D5/contributions.jsonl" >/dev/null 2>&1 \
  || T30_WHY="${T30_WHY:+$T30_WHY; }jsonl: invalid JSON line present"
[ -n "$T30_WHY" ] && T30_OK=0
CUR_LINES="$(wc -l < "$SEED")"
if [ "$CUR_LINES" -lt "$SEED_LINES_BEFORE" ] || \
   [ "$(head -n "$SEED_LINES_BEFORE" "$SEED" | sha256sum | cut -d' ' -f1)" != "$SEED_HEAD_SHA" ]; then
  T30_OK=0
  T30_WHY="${T30_WHY:+$T30_WHY; }mutation: live prefix changed since suite start (in-place edit or truncation)"
fi
if [ "$T30_OK" -eq 1 ]; then
  ok "T30 live seed integrity OK (verify clean, JSONL valid, append-only prefix intact — growth tolerated)"
else
  fail "T30 live seed integrity" "$T30_WHY"
fi

echo "----"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
