#!/usr/bin/env bash
# agora.sh — append-only contribution DAG CLI for dev_agent_team (Agora Phase 1).
#
# The shared DAG lives at agora/contributions.jsonl: one JSON object per line,
# immutable, content-addressed. Git history of that file IS the transport
# (light path only — no bundle, no service). Views are DERIVED; the JSONL
# file is the source of truth.
#
# Usage:
#   agora.sh publish --type <type> --title <title> [--body-ref <ref>]
#                    [--tags <csv>] [--parents <csv>] [--ts <ts>] [--by <actor>]
#   agora.sh log [--type <type>] [-n <N>]
#   agora.sh show <id-prefix>
#   agora.sh analyze <view>
#   agora.sh verify
#   agora.sh -h|--help|help
#
# Views: leaders | most-built-on | leaves | underexplored | unverified |
#        contested | open-hypotheses | clusters
#
# Options (may appear anywhere before/among subcommand args):
#   --agora-dir <d> | --agora-dir=<d>  DAG dir (default: $AGORA_DIR, else
#                                      <repo>/agora)
#   --by <actor> | --by=<actor>        'created_by' actor for publish
#                                      (default: $AGORA_BY, else `id -un`)
#
# Environment:
#   AGORA_DIR   DAG directory (default: <repo>/agora)
#   AGORA_BY    default actor when --by is not given
#
# Exit status: 0 success; 1 detected violation / operational error;
# 2 usage error.
#
# Notes:
#   - append-only: there are NO edit/delete subcommands. A contribution is
#     never modified; it is superseded only by a NEW contribution whose
#     parents[] cites it.
#   - id = sha256 (hex) of the canonical payload line:
#       jq -cS '{parents,type,title,body_ref,tags,created_by,ts}'
#     `verify` recomputes every id — any mutation of a committed line fails.
#   - type enum: setup | result | insight | hypothesis | report |
#     verification | endorsed. `wip` is REJECTED (in-progress pointers live
#     in .tasks/tasks.json status only, never in the DAG).
#   - type=verification MUST carry exactly one weight tag: +20 (accept),
#     +10 (weak-accept), or -20 (refute). endorsed carries weight 0.
#   - concurrent appends: publish takes an flock(1) lock on
#     <agora-dir>/.publish.lock when flock exists (single printf append is
#     otherwise atomic for short lines). Cross-machine conflicts resolve by
#     git pull --rebase retry; the Orchestrator serializes parallel publishes.
#   - jq is required. python3/sqlite are NOT used (jq-only by design in
#     Phase 1; a derived index.db remains a future optimization, not a
#     requirement). sqlite3 CLI must NOT be required.
#   - TUNABLE scoring constants live in exactly one block below (search
#     TUNABLE). Scores are READ-ONLY in Phase 1: advisory only, no
#     enforcement, no routing changes.

set -euo pipefail

# --------------------------------------------------------------------- #
# TUNABLE scoring constants (Phase 1 provisional — read-only, advisory).
# Change ONLY here. Revisit trigger: pilot duplication-rate data (D4).
# --------------------------------------------------------------------- #
AGORA_W_VERIFY_STRONG=20    # TUNABLE: verification tag +20 (accept)
AGORA_W_VERIFY_WEAK=10      # TUNABLE: verification tag +10 (weak-accept)
AGORA_W_REFUTE=-20          # TUNABLE: verification tag -20 (refute)
AGORA_W_DEFAULT=1           # TUNABLE: any non-verification, non-endorsed child
AGORA_W_ENDORSED=0          # TUNABLE: endorsed carries no quality weight
AGORA_UCB_C=2.0             # TUNABLE: exploration constant in U(v)

TYPES="setup result insight hypothesis report verification endorsed"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
AGORA_DIR_DEFAULT="${AGORA_DIR:-$PROJECT_ROOT/agora}"
GLOBAL_AGORA_DIR="$AGORA_DIR_DEFAULT"
GLOBAL_BY=""

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

die() { echo "ERROR: $*" >&2; exit 1; }

usage() { # [exit-code] — prints the header comment block (lines after #!)
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-2}"
}

usage_err() { echo "ERROR: $*" >&2; usage; }

expect_argc() { # <expected> <got> <description> — usage error on mismatch
  if [ "$1" -ne "$2" ]; then
    echo "ERROR: $3 takes exactly $1 argument(s) (got $2)" >&2
    exit 2
  fi
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

default_actor() {
  if [ -n "${AGORA_BY:-}" ]; then printf '%s' "$AGORA_BY"; else id -un 2>/dev/null || printf 'unknown'; fi
}

log_file() { printf '%s/contributions.jsonl' "$GLOBAL_AGORA_DIR"; }

require_log() { # error if the DAG file is missing (all read commands need it)
  [ -f "$(log_file)" ] || die "no DAG file: $(log_file) (nothing published yet)"
}

valid_type() { # <type> → 0 if in enum
  case " $TYPES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# csv_to_json_array <csv> — "" → [], else ["a","b"] (trims surrounding spaces)
csv_to_json_array() {
  jq -cn --arg csv "$1" '
    if ($csv | gsub("\\s";"")) == "" then []
    else ($csv | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(. != "")))
    end'
}

# canonical_payload <parents-json> <type> <title> <body_ref> <tags-json> <by> <ts>
canonical_payload() {
  jq -cn -S \
    --argjson parents "$1" --arg type "$2" --arg title "$3" \
    --arg body_ref "$4" --argjson tags "$5" --arg by "$6" --arg ts "$7" \
    '{parents:$parents, type:$type, title:$title, body_ref:$body_ref,
      tags:$tags, created_by:$by, ts:$ts}'
}

# --------------------------------------------------------------------- #
# publish
# --------------------------------------------------------------------- #

cmd_publish() {
  local type="" title="" body_ref="" tags_csv="" parents_csv="" ts="" by=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="${2:-}"; shift 2 ;;
      --type=*) type="${1#--type=}"; shift ;;
      --title) title="${2:-}"; shift 2 ;;
      --title=*) title="${1#--title=}"; shift ;;
      --body-ref) body_ref="${2:-}"; shift 2 ;;
      --body-ref=*) body_ref="${1#--body-ref=}"; shift ;;
      --tags) tags_csv="${2:-}"; shift 2 ;;
      --tags=*) tags_csv="${1#--tags=}"; shift ;;
      --parents) parents_csv="${2:-}"; shift 2 ;;
      --parents=*) parents_csv="${1#--parents=}"; shift ;;
      --ts) ts="${2:-}"; shift 2 ;;
      --ts=*) ts="${1#--ts=}"; shift ;;
      --by) by="${2:-}"; shift 2 ;;
      --by=*) by="${1#--by=}"; shift ;;
      -h|--help) usage 0 ;;
      *) usage_err "unknown publish flag: $1" ;;
    esac
  done
  [ -n "$type" ] || usage_err "publish requires --type"
  [ -n "$title" ] || usage_err "publish requires --title"
  valid_type "$type" || die "invalid --type: '$type' (one of: $TYPES; note: 'wip' is rejected — in-progress state lives in .tasks/tasks.json, never in the DAG)"
  by="${by:-${GLOBAL_BY:-$(default_actor)}}"
  ts="${ts:-$(now)}"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || die "invalid --ts: '$ts' (expected UTC ISO-8601: YYYY-MM-DDTHH:MM:SSZ)"

  local parents_json tags_json
  parents_json="$(csv_to_json_array "$parents_csv")"
  tags_json="$(csv_to_json_array "$tags_csv")"

  if [ "$type" = "verification" ]; then
    local nw
    nw="$(printf '%s' "$tags_json" | jq '[.[] | select(. == "+20" or . == "+10" or . == "-20")] | length')"
    [ "$nw" = "1" ] || die "type=verification requires exactly one weight tag (+20, +10, or -20) in --tags (got: $tags_csv)"
  fi

  mkdir -p "$GLOBAL_AGORA_DIR"
  local log
  log="$(log_file)"
  touch "$log"

  # Parents-integrity at publish time: every parent must already exist.
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [[ "$p" =~ ^[0-9a-f]{64}$ ]] || die "invalid parent id (not 64-hex sha256): '$p'"
    jq -e --arg id "$p" 'select(.id == $id)' "$log" >/dev/null 2>&1 \
      || die "dangling parent: '$p' not found in $(log_file)"
  done < <(printf '%s' "$parents_json" | jq -r '.[]')

  local payload id line
  payload="$(canonical_payload "$parents_json" "$type" "$title" "$body_ref" "$tags_json" "$by" "$ts")"
  id="$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)"
  if jq -e --arg id "$id" 'select(.id == $id)' "$log" >/dev/null 2>&1; then
    echo "EXISTS: identical contribution already published: $id" >&2
    printf '%s\n' "$id"
    return 0
  fi
  line="$(printf '%s' "$payload" | jq -cS --arg id "$id" '. + {id:$id}')"

  # Atomic append under lock when flock(1) exists; else single short-line
  # append (atomic on POSIX for small writes). No edit path exists anywhere.
  if command -v flock >/dev/null 2>&1; then
    flock -x "$GLOBAL_AGORA_DIR/.publish.lock" -c \
      "printf '%s\n' \"\$AGORA_LINE\" >> \"\$AGORA_LOG\"" \
      AGORA_LINE="$line" AGORA_LOG="$log" 2>/dev/null \
    || printf '%s\n' "$line" >> "$log"
  else
    printf '%s\n' "$line" >> "$log"
  fi
  printf '%s\n' "$id"
}

# --------------------------------------------------------------------- #
# log
# --------------------------------------------------------------------- #

cmd_log() {
  local type="" n=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="${2:-}"; shift 2 ;;
      --type=*) type="${1#--type=}"; shift ;;
      -n) n="${2:-}"; shift 2 ;;
      -n*) n="${1#-n}"; shift ;;
      -h|--help) usage 0 ;;
      *) usage_err "unknown log flag: $1" ;;
    esac
  done
  require_log
  if [ -n "$type" ]; then
    valid_type "$type" || die "invalid --type: '$type' (one of: $TYPES)"
  fi
  if [ -n "$n" ]; then
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ] || usage_err "log -n requires a positive integer (got '$n')"
  fi
  local src
  if [ -n "$n" ]; then src="$(tail -n "$n" "$(log_file)")"; else src="$(cat "$(log_file)")"; fi
  if [ -n "$type" ]; then
    printf '%s\n' "$src" | jq -c --arg t "$type" 'select(.type == $t)'
  else
    printf '%s\n' "$src" | jq -c '.'
  fi
}

# --------------------------------------------------------------------- #
# show
# --------------------------------------------------------------------- #

cmd_show() {
  [ $# -ge 1 ] || usage_err "show requires an id prefix argument"
  local prefix="$1"; shift
  [ $# -eq 0 ] || usage_err "show takes exactly 1 argument"
  require_log
  local matches
  matches="$(jq -c --arg p "$prefix" 'select(.id | startswith($p))' "$(log_file)")"
  [ -n "$matches" ] || die "no contribution with id prefix: '$prefix'"
  local count
  count="$(printf '%s\n' "$matches" | wc -l)"
  [ "$count" -eq 1 ] || die "ambiguous id prefix '$prefix' ($count matches — give a longer prefix)"
  printf '%s\n' "$matches" | jq '.'
}

# --------------------------------------------------------------------- #
# analyze — 8 read-only views (jq over the JSONL source of truth)
# --------------------------------------------------------------------- #

# Shared jq prelude: weight fn + children/S/UCB enrichment.
# $all = whole DAG array. Each node gains: children (ids), n, S, ucb.
ANALYZE_PRELUDE='
  def w: if .type == "verification"
    then (if (.tags | index("+20")) then $ws
          elif (.tags | index("+10")) then $ww
          elif (.tags | index("-20")) then $wr else 0 end)
    elif .type == "endorsed" then $we else $wd end;
  ($all | length) as $N
  | . as $u
  | ($u.id) as $uid
  | ([$all[] | select(.parents | index($uid))]) as $kids
  | ([$kids[] | select(.created_by != $u.created_by)]) as $cited
  | (([$cited[] | w] | add // 0)) as $S
  | ((($kids | length) + 1)) as $n
  | {node: $u, kids: $kids, S: $S, n: $n,
     ucb: (($S / $n) + $C * ((($N + 1 | log) / $n) | sqrt))}'

cmd_analyze() {
  [ $# -ge 1 ] || usage_err "analyze requires a view (leaders|most-built-on|leaves|underexplored|unverified|contested|open-hypotheses|clusters)"
  local view="$1"; shift
  [ $# -eq 0 ] || usage_err "analyze takes exactly 1 view argument"
  require_log
  local all
  all="$(jq -s '.' "$(log_file)")"
  case "$view" in
    leaders)
      printf '%s' "$all" | jq -c -S \
        --argjson ws "$AGORA_W_VERIFY_STRONG" --argjson ww "$AGORA_W_VERIFY_WEAK" \
        --argjson wr "$AGORA_W_REFUTE" --argjson wd "$AGORA_W_DEFAULT" \
        --argjson we "$AGORA_W_ENDORSED" --argjson C "$AGORA_UCB_C" \
        --argjson all "$all"        '
        [.[] | '"$ANALYZE_PRELUDE"' | {id: .node.id, title: .node.title,
            type: .node.type, S: .S, n: .n, ucb: .ucb}]
        | sort_by(-.S, -.ucb) | .[]'
      ;;
    most-built-on)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | {id: $u.id, title: $u.title,
             children: ([$all[] | select(.parents | index($uid))]) | length}]
        | sort_by(-.children) | .[]'
      ;;
    leaves)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | select(([$all[] | select(.parents | index($uid))]) | length == 0)
          | {id: .id, title: .title, type: .type, ts: .ts}] | .[]'
      ;;
    underexplored)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | {id: $u.id, title: $u.title, ts: $u.ts,
             children: ([$all[] | select(.parents | index($uid))]) | length}
          | select(.children <= 1)]
        | sort_by(.ts) | .[]'
      ;;
    unverified)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | select(.type != "verification")
          | select(([$all[] | select(.parents | index($uid))
                      | select(.type == "verification")]) | length == 0)
          | {id: .id, title: .title, type: .type, ts: .ts}] | .[]'
      ;;
    contested)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | ([$all[] | select(.parents | index($uid))
               | select(.type == "verification" and (.tags | index("-20")))])
            as $refs
          | select($refs | length > 0)
          | {id: .id, title: .title, refuted_by: [$refs[].id]}] | .[]'
      ;;
    open-hypotheses)
      printf '%s' "$all" | jq -c -S --argjson all "$all" '
        [.[] | . as $u | ($u.id) as $uid
          | select(.type == "hypothesis")
          | select(([$all[] | select(.parents | index($uid))
                      | select(.type == "verification")]) | length == 0)
          | {id: .id, title: .title, ts: .ts}] | .[]'
      ;;
    clusters)
      printf '%s' "$all" | jq -c -S '
        ([.[].tags[]] | unique) as $tags
        | [$tags[] as $t
          | {tag: $t, count: ([.[] | select(.tags | index($t))] | length),
             members: ([.[] | select(.tags | index($t)) | .id])}]
        | sort_by(-.count) | .[]'
      ;;
    *) usage_err "unknown analyze view: '$view' (one of: leaders|most-built-on|leaves|underexplored|unverified|contested|open-hypotheses|clusters)" ;;
  esac
}

# --------------------------------------------------------------------- #
# verify — schema + id/no-mutation + parents-integrity (+ duplicate check)
# --------------------------------------------------------------------- #

cmd_verify() {
  [ $# -eq 0 ] || usage_err "verify takes no arguments"
  require_log
  local log fails=0 lineno=0 line
  log="$(log_file)"
  declare -A SEEN_IDS=()

  # Pass 1: per-line schema + id recompute; collect ids for integrity pass.
  declare -a IDS=()
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] || continue
    printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1 \
      || { echo "VERIFY FAIL $log:$lineno: not a JSON object" >&2; fails=$((fails + 1)); continue; }

    local bad
    bad="$(printf '%s' "$line" | jq -r '
      def err(m): m;
      .type as $t | .tags as $tg
      | [ (if (.id | type) != "string" or (.id | test("^[0-9a-f]{64}$") | not)
          then err("bad id (must be 64-hex sha256)") else empty end),
        (if (.parents | type) != "array"
          or ([.parents[] | select((type != "string")
            or (test("^[0-9a-f]{64}$") | not))] | length > 0)
          then err("bad parents[] (must be array of 64-hex ids)") else empty end),
        (if (["setup","result","insight","hypothesis","report",
              "verification","endorsed"] | index($t) | not)
          then err("bad type (enum: setup|result|insight|hypothesis|report|verification|endorsed; wip rejected)") else empty end),
        (if (.title | type) != "string" or (.title | length) == 0
          then err("bad title (must be non-empty string)") else empty end),
        (if (.body_ref | type) != "string"
          then err("bad body_ref (must be string)") else empty end),
        (if (.tags | type) != "array"
          or ([.tags[] | select(type != "string")] | length > 0)
          then err("bad tags[] (must be array of strings)") else empty end),
        (if (.created_by | type) != "string" or (.created_by | length) == 0
          then err("bad created_by (must be non-empty string)") else empty end),
        (if (.ts | type) != "string"
          or (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") | not)
          then err("bad ts (must be UTC ISO-8601 YYYY-MM-DDTHH:MM:SSZ)") else empty end),
        (if .type == "verification"
          and ([.tags[] | select(. == "+20" or . == "+10" or . == "-20")] | length != 1)
          then err("verification needs exactly one weight tag (+20|+10|-20)") else empty end)
      ] | join("; ")')"
    if [ -n "$bad" ]; then
      echo "VERIFY FAIL $log:$lineno: schema: $bad" >&2; fails=$((fails + 1)); continue
    fi

    # No-mutation: id must equal sha256 of canonical payload.
    local payload expect_id got_id
    payload="$(printf '%s' "$line" | jq -cS \
      '{parents,type,title,body_ref,tags,created_by,ts}')"
    expect_id="$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)"
    got_id="$(printf '%s' "$line" | jq -r '.id')"
    if [ "$expect_id" != "$got_id" ]; then
      echo "VERIFY FAIL $log:$lineno: id mismatch (line mutated? recomputed $expect_id)" >&2
      fails=$((fails + 1)); continue
    fi
    if [ -n "${SEEN_IDS[$got_id]:-}" ]; then
      echo "VERIFY FAIL $log:$lineno: duplicate id $got_id (first at line ${SEEN_IDS[$got_id]})" >&2
      fails=$((fails + 1)); continue
    fi
    SEEN_IDS[$got_id]="$lineno"
    IDS+=("$got_id")
  done < "$log"

  # Pass 2: parents-integrity — every parent id must exist in the file.
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] || continue
    printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1 || continue
    local p
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ -z "${SEEN_IDS[$p]:-}" ]; then
        echo "VERIFY FAIL $log:$lineno: dangling parent '$p' (not in DAG)" >&2
        fails=$((fails + 1))
      fi
    done < <(printf '%s' "$line" | jq -r '.parents[]? // empty')
  done < "$log"

  if [ "$fails" -gt 0 ]; then
    echo "VERIFY FAIL: $fails violation(s) in $log" >&2
    return 1
  fi
  echo "VERIFY OK: ${#IDS[@]} contributions in $log"
}

# --------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------- #

main() {
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH (required — jq 1.7)"

  # Global option pass: consume --agora-dir/--by anywhere; leave the rest.
  local expect="" arg
  local -a rest=()
  for arg in "$@"; do
    if [ -n "$expect" ]; then
      case "$expect" in
        agoradir) GLOBAL_AGORA_DIR="$arg" ;;
        by) GLOBAL_BY="$arg" ;;
      esac
      expect=""
      continue
    fi
    case "$arg" in
      --agora-dir=*) GLOBAL_AGORA_DIR="${arg#--agora-dir=}" ;;
      --by=*) GLOBAL_BY="${arg#--by=}" ;;
      --agora-dir) expect="agoradir" ;;
      --by) expect="by" ;;
      *) rest+=("$arg") ;;
    esac
  done
  [ -z "$expect" ] || die "--agora-dir/--by requires a value"
  set -- "${rest[@]}"

  local cmd="${1:-}"
  [ -n "$cmd" ] || usage
  shift

  case "$cmd" in
    -h|--help|help) usage 0 ;;
    publish) cmd_publish "$@" ;;
    log) cmd_log "$@" ;;
    show) cmd_show "$@" ;;
    analyze) cmd_analyze "$@" ;;
    verify) cmd_verify "$@" ;;
    *) usage_err "unknown command: $cmd (publish|log|show|analyze|verify)" ;;
  esac
}

main "$@"
