#!/usr/bin/env bash
# state.sh — JSON machine-state tool for dev_agent_team task trees.
#
# Per-goal task state lives at .tasks/<goal>/tasks.json; global derived
# registries (agents.json, sessions.json) and the append-only event journal
# (events.jsonl) live at the project machine-state root (.tasks/).
#
# Usage:
#   state.sh task create <id> --title T --description D [--priority P] [--depends-on id...]
#   state.sh task assign <id> <agent>
#   state.sh task status <id> <status>
#   state.sh task deps <id> add <dep-id>...
#   state.sh task blocked-detect [<goal>]
#   state.sh task complete|fail|cancel <id>
#   state.sh query pending [<goal>]
#   state.sh query agent <agent> [<goal>]
#   state.sh query status <status> [<goal>]
#   state.sh log tail [-n N]
#   state.sh agents sync
#   state.sh sessions sync
#   state.sh -h|--help|help
#
# Options (may appear anywhere before/among subcommand args):
#   --goal <g> | --goal=<g>   goal name (default: $STATE_GOAL, else the only
#                             .tasks/*/ goal; error if ambiguous)
#   --by <actor>              event 'by' actor (defaults: tool for task create
#                             and blocked-detect; orchestrator elsewhere)
#
# Environment:
#   STATE_ROOT   project machine-state root (default: <repo>/.tasks)
#   STATE_GOAL   default goal when --goal is not given
#   OPENCODE_MEMORY_DIR  memory dir consulted by sessions sync
#                        (default: <repo>/memory)
#
# Exit status: 0 success; 1 detected violation / operational error;
# 2 usage error.
#
# Notes:
#   - statuses: pending | assigned | in_progress | blocked | completed |
#     failed | cancelled  (workflow-architect Model 1; terminal = completed /
#     failed / cancelled — no outgoing transitions; retry is a NEW task).
#   - transitions enforced per Model 2; `task status X blocked` is allowed
#     (agent block report recorded by the Orchestrator); blocking deps are
#     detected by `task blocked-detect`, which considers ONLY tasks in
#     assigned/in_progress (Model 3 — pending is never auto-blocked).
#   - query status blocked reads the current blocked set; run blocked-detect
#     first to refresh it. 'blocked' is accepted by query status like any other
#     state; there is no separate blocked query.
#   - events.jsonl: append-only; one JSON object per line; envelope
#     {ts,event,by,...}; vocabulary: task.created, task.assigned,
#     agent.dispatched, task.status_changed, task.dep_added,
#     session.started|interrupted|completed, report.written (Model 6).
#     assigned -> in_progress appends agent.dispatched AND task.status_changed
#     (Architect Decision 3 ownership table — the task file's "one line per
#     subcommand" is overridden here by the binding decision).
#   - agents.json / sessions.json are DERIVED (agents sync from agents/*.md
#     frontmatter; sessions sync from memory/sessions/*.md Status:/Started:/
#     Last updated: lines). sessions sync only READS Markdown — memory-lifecycle
#     and the pinned Status: parse are never touched, and no session event is
#     fabricated by a regeneration (session lifecycle events belong to the
#     session author at the Markdown boundary, per Architect Decision 3).
#   - flag.json is legacy per-goal planning state (Decision 7): superseded by
#     tasks.json for new goals; existing trees keep it until next re-plan. This
#     tool never reads or writes flag.json.

set -euo pipefail

# FIXME(03): --by is trusted as given; actor authorization (only the
#   Orchestrator may run execution flips) is a documented convention, not
#   enforced here (Architect ownership matrix names the actor).
# FIXME(03): deps remove / un-assign are not implemented — explicitly out of
#   03 scope (workflow-architect residual ambiguities, handed to re-plan).

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
STATE_ROOT="${STATE_ROOT:-$PROJECT_ROOT/.tasks}"
MEMORY_DIR="${OPENCODE_MEMORY_DIR:-$PROJECT_ROOT/memory}"
EVENTS_FILE="$STATE_ROOT/events.jsonl"
AGENTS_STATE="$STATE_ROOT/agents.json"
SESSIONS_STATE="$STATE_ROOT/sessions.json"

GLOBAL_GOAL=""
GLOBAL_BY=""

STATUSES="pending assigned in_progress blocked completed failed cancelled"

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

validate_id() { # <id> — safe map key / event value (no paths, no spaces)
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid id: '$1' (alnum, dot, dash, underscore; no spaces/slashes)"
}

validate_goal_name() { # <goal>
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid goal name: '$1'"
}

validate_status() { # <status> → 0 if in the 7-state enum
  case " $STATUSES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Model 2 allowed-transition table (terminal states have no outgoing edge).
transition_allowed() { # <from> <to> → 0 if allowed
  case "$1|$2" in
    pending\|assigned|pending\|completed|pending\|cancelled|assigned\|in_progress|assigned\|blocked|assigned\|completed|assigned\|cancelled|in_progress\|blocked|in_progress\|completed|in_progress\|failed|in_progress\|cancelled|blocked\|in_progress|blocked\|assigned|blocked\|completed|blocked\|failed|blocked\|cancelled)
      return 0 ;;
    *) return 1 ;;
  esac
}

append_event() { # <event> <extra_json|''> <by> — append one JSONL line
  local ev="$1" extra="$2" by="$3" ts
  ts="$(now)"
  mkdir -p "$STATE_ROOT"
  local line
  if [ -n "$extra" ]; then
    line="$(jq -cn --arg ts "$ts" --arg event "$ev" --arg by "$by" --argjson extra "$extra" '{ts:$ts, event:$event, by:$by} + $extra')"
  else
    line="$(jq -cn --arg ts "$ts" --arg event "$ev" --arg by "$by" '{ts:$ts, event:$event, by:$by}')"
  fi
  printf '%s\n' "$line" >> "$EVENTS_FILE"
}

# Atomic jq update of a state file: write tmp in same dir, then mv.
run_jq_update() { # <file> [jq args...]
  local f="$1" shift_done=1 tmp err
  tmp="$(mktemp "${f}.XXXXXX")"
  shift
  if ! err="$(jq "$@" "$f" > "$tmp" 2>&1)"; then
    echo "jq error updating $f: $err" >&2
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$f"
}

# --------------------------------------------------------------------- #
# Goal resolution
# --------------------------------------------------------------------- #

# Priority: --goal flag > $STATE_GOAL > the ONLY .tasks/*/ goal. Ambiguous
# (or none) is an error with a message naming the candidates.
resolve_goal() {
  local goal="${GLOBAL_GOAL:-${STATE_GOAL:-}}"
  if [ -n "$goal" ]; then
    validate_goal_name "$goal"
    echo "$goal"
    return 0
  fi
  mkdir -p "$STATE_ROOT"
  local -a dirs=() names=() d
  shopt -s nullglob
  dirs=( "$STATE_ROOT"/*/ )
  shopt -u nullglob
  if [ "${#dirs[@]}" = "0" ]; then
    die "no goals exist under $STATE_ROOT (create one: state.sh task create <id> --goal <name> --title ...)"
  elif [ "${#dirs[@]}" = "1" ]; then
    echo "$(basename "${dirs[0]}")"
  else
    for d in "${dirs[@]}"; do names+=("$(basename "$d")"); done
    echo "ERROR: multiple goals found: ${names[*]}; use --goal <name> or STATE_GOAL" >&2
    exit 2
  fi
}

ensure_goal_state() { # <goal> — mkdir + seed tasks.json on first use
  mkdir -p "$STATE_ROOT/$1"
  local f="$STATE_ROOT/$1/tasks.json"
  if [ ! -f "$f" ]; then
    jq -n --arg g "$1" '{version:1, goal:$g, tasks:{}}' > "$f"
  fi
}

# Resolve goal for a mutating command and guarantee tasks.json exists.
require_goal_state() {
  local goal
  goal="$(resolve_goal)"
  ensure_goal_state "$goal"
  echo "$goal"
}

# Resolve goal for a query: trailing positional goal must already exist.
query_goal() { # [<goal>]
  local g="${1:-}"
  if [ -n "$g" ]; then
    validate_goal_name "$g"
    [ -d "$STATE_ROOT/$g" ] || die "unknown goal: '$g' (no $STATE_ROOT/$g/)"
    echo "$g"
  else
    resolve_goal
  fi
}

task_exists() { # <goal> <id> → 0 if present
  local f="$STATE_ROOT/$1/tasks.json"
  jq -e --arg id "$2" '.tasks | has($id)' "$f" >/dev/null 2>&1
}

require_task() { # <goal> <id>
  local f="$STATE_ROOT/$1/tasks.json"
  if ! jq -e --arg id "$2" '.tasks | has($id)' "$f" >/dev/null 2>&1; then
    die "task '$2' not found in goal '$1'"
  fi
}

# assigned_to validation against the derived roster (Architect Decision 2b).
# Lenient by design: agents.json is derived + gitignored + may be stale, so an
# unknown name is a WARNING, not a hard failure (the sanctioned demo trace
# assigns 'agent-a').
validate_agent() { # <agent>
  local a="$1"
  if [ -f "$AGENTS_STATE" ]; then
    if ! jq -e --arg a "$a" '[.agents[].name] | index($a) != null' "$AGENTS_STATE" >/dev/null 2>&1; then
      echo "WARNING: '$a' not found in $AGENTS_STATE (derived roster; run 'state.sh agents sync' if agents/*.md changed)." >&2
    fi
  else
    echo "WARNING: $AGENTS_STATE absent; run 'state.sh agents sync'. Assignment recorded without roster validation." >&2
  fi
}

# --------------------------------------------------------------------- #
# task subcommands
# --------------------------------------------------------------------- #

cmd_task_create() {
  local id="${1:-}"
  [ -n "$id" ] || die "task create requires an id"
  validate_id "$id"
  shift
  local title="" description="" priority="normal"
  local -a deps=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift 2 ;;
      --title=*) title="${1#--title=}"; shift ;;
      --description) description="${2:-}"; shift 2 ;;
      --description=*) description="${1#--description=}"; shift ;;
      --priority) priority="${2:-}"; shift 2 ;;
      --priority=*) priority="${1#--priority=}"; shift ;;
      --depends-on) shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do deps+=("$1"); shift; done ;;
      *) die "task create: unexpected argument: $1" ;;
    esac
  done
  [ -n "$title" ] || die "task create: --title is required"
  local d
  for d in "${deps[@]+"${deps[@]}"}"; do
    validate_id "$d"
    [ "$d" != "$id" ] || die "task cannot depend on itself: $id"
  done
  local goal f
  goal="$(require_goal_state)"
  f="$STATE_ROOT/$goal/tasks.json"
  if task_exists "$goal" "$id"; then
    die "task '$id' already exists in goal '$goal'"
  fi
  local now deps_json
  now="$(now)"
  deps_json="$(jq -cn '$ARGS.positional' --args "${deps[@]+"${deps[@]}"}")"
  run_jq_update "$f" \
    --arg id "$id" --arg title "$title" --arg desc "$description" --arg prio "$priority" \
    --argjson deps "$deps_json" --arg now "$now" \
    '.tasks[$id] = {title:$title, description:$desc, status:"pending", priority:$prio,
                    assigned_to:null, dependencies:$deps, created_at:$now, updated_at:$now,
                    started_at:null, completed_at:null}'
  local extra
  extra="$(jq -cn --arg id "$id" --arg t "$title" '{task_id:$id, title:$t}')"
  append_event task.created "$extra" "${GLOBAL_BY:-tool}"
  echo "created: $goal/$id (pending)"
}

cmd_task_assign() {
  local id="${1:-}" agent="${2:-}"
  [ -n "$id" ] || die "task assign requires an id"
  [ -n "$agent" ] || die "task assign requires an agent"
  expect_argc 2 $# "task assign <id> <agent>"
  validate_id "$id"
  local goal f status
  goal="$(require_goal_state)"
  f="$STATE_ROOT/$goal/tasks.json"
  require_task "$goal" "$id"
  status="$(jq -r --arg id "$id" '.tasks[$id].status' "$f")"
  if [ "$status" != "pending" ]; then
    die "cannot assign '$id': transition $status -> assigned is not allowed (only pending -> assigned; use blocked -> assigned to re-assign a blocked task)"
  fi
  validate_agent "$agent"
  local now
  now="$(now)"
  run_jq_update "$f" --arg id "$id" --arg agent "$agent" --arg now "$now" \
    '.tasks[$id].status = "assigned" | .tasks[$id].assigned_to = $agent | .tasks[$id].updated_at = $now'
  local extra
  extra="$(jq -cn --arg id "$id" --arg a "$agent" '{task_id:$id, agent:$a}')"
  append_event task.assigned "$extra" "${GLOBAL_BY:-orchestrator}"
  echo "assigned: $goal/$id -> $agent"
}

cmd_task_status() {
  local id="${1:-}" to="${2:-}"
  [ -n "$id" ] || die "task status requires an id"
  validate_status "$to" || die "invalid status: '$to' (valid: $STATUSES)"
  expect_argc 2 $# "task status <id> <status>"
  validate_id "$id"
  local goal f from assigned_to now extra agent extra_dispatch
  goal="$(require_goal_state)"
  f="$STATE_ROOT/$goal/tasks.json"
  require_task "$goal" "$id"
  from="$(jq -r --arg id "$id" '.tasks[$id].status' "$f")"
  transition_allowed "$from" "$to" || die "illegal transition: $from -> $to (see task-01 Model 2 transition table; terminal states have no outgoing transitions)"
  assigned_to="$(jq -r --arg id "$id" '.tasks[$id].assigned_to // ""' "$f")"
  if [ "$to" = "completed" ] && [ -z "$assigned_to" ]; then
    die "cannot complete '$id': no assigned_to set (guard: every completed task names a responsible party)"
  fi
  if [ "$to" = "in_progress" ] && [ -z "$assigned_to" ]; then
    die "cannot start '$id': no assigned_to set (run 'task assign' first)"
  fi
  now="$(now)"
  run_jq_update "$f" --arg id "$id" --arg to "$to" --arg now "$now" \
    '.tasks[$id].status = $to |
     .tasks[$id].updated_at = $now |
     (if $to == "in_progress" and (.tasks[$id].started_at == null) then .tasks[$id].started_at = $now else . end) |
     (if $to == "completed" and (.tasks[$id].completed_at == null) then .tasks[$id].completed_at = $now else . end)'
  extra="$(jq -cn --arg id "$id" --arg from "$from" --arg to "$to" '{task_id:$id, from:$from, to:$to}')"
  if [ "$from" = "assigned" ] && [ "$to" = "in_progress" ]; then
    # Architect Decision 3 dispatch flip: agent.dispatched AND task.status_changed.
    agent="$(jq -r --arg id "$id" '.tasks[$id].assigned_to' "$f")"
    extra_dispatch="$(jq -cn --arg id "$id" --arg a "$agent" '{task_id:$id, agent:$a}')"
    append_event agent.dispatched "$extra_dispatch" "${GLOBAL_BY:-orchestrator}"
  fi
  append_event task.status_changed "$extra" "${GLOBAL_BY:-orchestrator}"
  echo "status: $goal/$id $from -> $to"
}

cmd_task_deps() {
  local id="${1:-}" op="${2:-}"
  [ -n "$id" ] || die "task deps requires an id"
  [ "$op" = "add" ] || die "task deps: only 'add' is supported (got '${op:-<missing>}')"
  shift 2
  [ $# -ge 1 ] || die "task deps add requires at least one dep id"
  validate_id "$id"
  local d
  local -a newdeps=()
  for d in "$@"; do
    validate_id "$d"
    [ "$d" != "$id" ] || die "task cannot depend on itself: $id -> $id"
    newdeps+=("$d")
  done
  local goal f now new_json added_json missing_json n
  goal="$(require_goal_state)"
  f="$STATE_ROOT/$goal/tasks.json"
  require_task "$goal" "$id"
  new_json="$(jq -cn '$ARGS.positional' --args "${newdeps[@]}")"
  added_json="$(jq -c --arg id "$id" --argjson new "$new_json" \
    '. as $root | [ $new[] | select(($root.tasks[$id].dependencies // [] | index(.)) == null) ]' "$f")"
  missing_json="$(jq -c --argjson new "$new_json" \
    '. as $root | [ $new[] | select($root.tasks[.]? == null) ]' "$f")"
  if [ "$(jq -r 'length' <<<"$added_json")" = "0" ]; then
    echo "deps: $goal/$id no new dependencies (all already present)"
    return 0
  fi
  for d in $(jq -r '.[]' <<<"$missing_json"); do
    echo "WARNING: dep id '$d' has no task record in $goal/tasks.json (blocks until re-plan adds it; Model 3 schema violation)" >&2
  done
  now="$(now)"
  run_jq_update "$f" --arg id "$id" --argjson new "$new_json" --arg now "$now" \
    '.tasks[$id].dependencies = (([.tasks[$id].dependencies[]] + $new) | unique) | .tasks[$id].updated_at = $now'
  n="$(jq -r 'length' <<<"$added_json")"
  for d in $(jq -r '.[]' <<<"$added_json"); do
    local extra
    extra="$(jq -cn --arg id "$id" --arg d "$d" '{task_id:$id, dep_id:$d}')"
    append_event task.dep_added "$extra" "${GLOBAL_BY:-orchestrator}"
  done
  echo "deps: $goal/$id added $n new dependency/dependencies"
}

cmd_task_blocked_detect() {
  local goal f now hits found
  goal="$(require_goal_state)"
  f="$STATE_ROOT/$goal/tasks.json"
  if [ ! -f "$f" ] || [ "$(jq -r '.tasks | length' "$f")" = "0" ]; then
    echo "blocked-detect: no tasks in goal '$goal'"
    return 0
  fi
  now="$(now)"
  # Model 3: only tasks in assigned/in_progress are evaluated; a task is
  # blocked iff any dependency id is missing or not 'completed'.
  hits="$(jq -r '
    . as $root
    | [ .tasks | to_entries[]
        | select(.value.status == "assigned" or .value.status == "in_progress") ]
      | map( .key as $tid
             | ($root.tasks[$tid].dependencies // []) as $deps
             | select(any($deps[]; ($root.tasks[.]? == null) or ($root.tasks[.].status != "completed")))
             | [ $tid, $root.tasks[$tid].status,
                 ([ $deps[] | select(($root.tasks[.]? == null) or ($root.tasks[.].status != "completed")) ] | join(",")) ] )
      | map(@tsv)[]
  ' "$f")"
  found=0
  if [ -n "$hits" ]; then
    local tid from reasons extra
    while IFS=$'\t' read -r tid from reasons; do
      found=1
      run_jq_update "$f" --arg id "$tid" --arg now "$now" \
        '.tasks[$id].status = "blocked" | .tasks[$id].updated_at = $now'
      extra="$(jq -cn --arg id "$tid" --arg from "$from" --arg reason "$reasons" '{task_id:$id, from:$from, to:"blocked", reason:$reason}')"
      append_event task.status_changed "$extra" "tool"
      echo "blocked: $goal/$tid ($from -> blocked; dep(s) not completed: $reasons)"
    done <<<"$hits"
  fi
  [ "$found" = "1" ] || echo "blocked-detect: no tasks newly blocked in goal '$goal'"
}

cmd_task_complete() { expect_argc 1 $# "task complete <id>"; cmd_task_status "$1" completed; }
cmd_task_fail()     { expect_argc 1 $# "task fail <id>";     cmd_task_status "$1" failed; }
cmd_task_cancel()   { expect_argc 1 $# "task cancel <id>";   cmd_task_status "$1" cancelled; }

# --------------------------------------------------------------------- #
# query subcommands
# --------------------------------------------------------------------- #

cmd_query() {
  local kind="${1:-}"
  [ -n "$kind" ] || usage_err "query requires a kind (pending|agent|status)"
  shift
  case "$kind" in
    pending)
      cmd_query_pending "$@"
      ;;
    agent)
      local agent="${1:-}"
      [ -n "$agent" ] || usage_err "query agent requires an agent"
      shift
      cmd_query_agent "$agent" "$@"
      ;;
    status)
      local st="${1:-}"
      validate_status "$st" || die "query status: invalid status '$st' (valid: $STATUSES)"
      shift
      cmd_query_status "$st" "$@"
      ;;
    *) usage_err "unknown query kind: $kind" ;;
  esac
}

cmd_query_pending() {
  local goal f
  [ $# -le 1 ] || usage_err "query pending: unexpected argument: $2"
  goal="$(query_goal "${1:-}")"
  f="$STATE_ROOT/$goal/tasks.json"
  [ -f "$f" ] || die "goal '$goal' has no tasks.json yet (create tasks first)"
  # Model 1 note: pending is never auto-blocked by unresolved deps — pending
  # tasks are the ready-to-assign queue as-is.
  printf 'ID\tSTATUS\tDEPS\tTITLE\n'
  jq -r '.tasks | to_entries[] | select(.value.status == "pending") |
    [.key, .value.status, (.value.dependencies // [] | join(",")), .value.title] | @tsv' "$f"
}

cmd_query_agent() {
  local agent="$1" goal f
  [ $# -le 2 ] || usage_err "query agent: unexpected argument: $3"
  goal="$(query_goal "${2:-}")"
  f="$STATE_ROOT/$goal/tasks.json"
  [ -f "$f" ] || die "goal '$goal' has no tasks.json yet (create tasks first)"
  printf 'ID\tSTATUS\tDEPS\tTITLE\n'
  jq -r --arg a "$agent" '.tasks | to_entries[] | select(.value.assigned_to == $a) |
    [.key, .value.status, (.value.dependencies // [] | join(",")), .value.title] | @tsv' "$f"
}

cmd_query_status() {
  local st="$1" goal f
  [ $# -le 2 ] || usage_err "query status: unexpected argument: $3"
  goal="$(query_goal "${2:-}")"
  f="$STATE_ROOT/$goal/tasks.json"
  [ -f "$f" ] || die "goal '$goal' has no tasks.json yet (create tasks first)"
  # 'blocked' is accepted here like any other state; run blocked-detect first
  # to refresh the blocked set before querying it.
  printf 'ID\tSTATUS\tDEPS\tTITLE\n'
  jq -r --arg s "$st" '.tasks | to_entries[] | select(.value.status == $s) |
    [.key, .value.status, (.value.dependencies // [] | join(",")), .value.title] | @tsv' "$f"
}

# --------------------------------------------------------------------- #
# log subcommand
# --------------------------------------------------------------------- #

cmd_log_tail() {
  local n=10 arg
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) n="${2:-}"; shift 2 ;;
      -n[0-9]*) n="${1#-n}"; shift ;;
      *) usage_err "log tail: unexpected argument: $1" ;;
    esac
  done
  [[ "$n" =~ ^[0-9]+$ ]] || die "log tail: -n requires a non-negative integer (got '$n')"
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "No events yet: $EVENTS_FILE"
    return 0
  fi
  # Every line must parse as JSON (task verification: jq -e per line).
  local line_no=0 line
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
      die "events.jsonl line $line_no is not valid JSON: $line"
    fi
  done < "$EVENTS_FILE"
  tail -n "$n" "$EVENTS_FILE"
}

# --------------------------------------------------------------------- #
# Derived registries
# --------------------------------------------------------------------- #

cmd_agents_sync() {
  local dir="$PROJECT_ROOT/agents"
  [ -d "$dir" ] || die "agents dir missing: $dir"
  local gen f bname name mode
  gen="$(now)"
  local -a entries=()
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    bname="$(basename "$f")"
    name="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1 && /^name:[[:space:]]*/{sub(/^name:[[:space:]]*/,""); print; exit}' "$f")"
    mode="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1 && /^mode:[[:space:]]*/{sub(/^mode:[[:space:]]*/,""); print; exit}' "$f")"
    [ -n "$name" ] || name="${bname%.md}"
    [ -n "$mode" ] || mode="subagent"
    entries+=("$(jq -cn --arg n "$name" --arg m "$mode" --arg fn "agents/$bname" '{name:$n, mode:$m, file:$fn}')")
  done
  local agents_json total primary sub
  if [ "${#entries[@]}" -gt 0 ]; then
    agents_json="$(printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.name)')"
  else
    agents_json="[]"
  fi
  mkdir -p "$STATE_ROOT"
  jq -n --arg gen "$gen" --argjson agents "$agents_json" '{version:1, generated_at:$gen, agents:$agents}' > "$AGENTS_STATE"
  total="$(jq '.agents | length' "$AGENTS_STATE")"
  primary="$(jq '[.agents[] | select(.mode == "primary")] | length' "$AGENTS_STATE")"
  sub=$((total - primary))
  echo "agents sync: $total agents (primary=$primary, subagent=$sub) -> $AGENTS_STATE (derived; source of truth agents/*.md)"
}

session_entry() { # <file> <basename> — derive one sessions.json entry from Markdown
  local f="$1" bname="$2" id title status started last
  id="${bname%.md}"
  title="$(grep -m1 "^# " "$f" 2>/dev/null | sed 's/^# //' || true)"
  status="$(grep -m1 "^Status:" "$f" 2>/dev/null | sed 's/^Status: *//' || true)"
  [ -n "$status" ] || status="unknown"
  started="$(grep -m1 "^Started:" "$f" 2>/dev/null | sed 's/^Started: *//' || true)"
  last="$(grep -m1 "^Last updated:" "$f" 2>/dev/null | sed 's/^Last updated: *//' || true)"
  jq -cn --arg id "$id" --arg title "$title" --arg status "$status" --arg started "$started" --arg last "$last" --arg fname "memory/sessions/$bname" \
    '{id:$id, title:$title, status:$status, started:$started, last_updated:$last, file:$fname}'
}

cmd_sessions_sync() {
  local dir="$MEMORY_DIR/sessions"
  [ -d "$dir" ] || die "sessions dir missing: $dir (expected memory/sessions)"
  local gen f bname
  gen="$(now)"
  local -a entries=()
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    bname="$(basename "$f")"
    [ "$bname" = "README.md" ] && continue
    entries+=("$(session_entry "$f" "$bname")")
  done
  local sess_json count
  if [ "${#entries[@]}" -gt 0 ]; then
    sess_json="$(printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.id)')"
  else
    sess_json="[]"
  fi
  mkdir -p "$STATE_ROOT"
  jq -n --arg gen "$gen" --argjson sessions "$sess_json" '{version:1, generated_at:$gen, sessions:$sessions}' > "$SESSIONS_STATE"
  count="$(jq '.sessions | length' "$SESSIONS_STATE")"
  echo "sessions sync: $count session(s) -> $SESSIONS_STATE (Markdown stays source of truth; memory-lifecycle.sh sessions untouched)"
}

# --------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------- #

main() {
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH (required — Architect Decision 5: jq 1.7)"

  # Global option pass: consume --goal/--by anywhere; leave everything else.
  local expect="" arg
  local -a rest=()
  for arg in "$@"; do
    if [ -n "$expect" ]; then
      case "$expect" in
        goal) GLOBAL_GOAL="$arg" ;;
        by) GLOBAL_BY="$arg" ;;
      esac
      expect=""
      continue
    fi
    case "$arg" in
      --goal=*) GLOBAL_GOAL="${arg#--goal=}" ;;
      --by=*) GLOBAL_BY="${arg#--by=}" ;;
      --goal) expect="goal" ;;
      --by) expect="by" ;;
      *) rest+=("$arg") ;;
    esac
  done
  [ -z "$expect" ] || die "--goal/--by requires a value"
  set -- "${rest[@]}"

  local cmd="${1:-}"
  [ -n "$cmd" ] || usage
  shift

  case "$cmd" in
    -h|--help|help) usage 0 ;;
    task)
      local sub="${1:-}"
      [ -n "$sub" ] || usage_err "task requires a subcommand (create|assign|status|deps|blocked-detect|complete|fail|cancel)"
      shift
      case "$sub" in
        create) cmd_task_create "$@" ;;
        assign) cmd_task_assign "$@" ;;
        status) cmd_task_status "$@" ;;
        deps) cmd_task_deps "$@" ;;
        blocked-detect) cmd_task_blocked_detect "$@" ;;
        complete) cmd_task_complete "$@" ;;
        fail) cmd_task_fail "$@" ;;
        cancel) cmd_task_cancel "$@" ;;
        *) usage_err "unknown task subcommand: $sub" ;;
      esac
      ;;
    query) cmd_query "$@" ;;
    log)
      local sub="${1:-}"
      [ "$sub" = "tail" ] || usage_err "log requires 'tail'"
      shift
      cmd_log_tail "$@"
      ;;
    agents)
      local sub="${1:-}"
      [ "$sub" = "sync" ] || usage_err "agents requires 'sync'"
      cmd_agents_sync
      ;;
    sessions)
      local sub="${1:-}"
      [ "$sub" = "sync" ] || usage_err "sessions requires 'sync'"
      cmd_sessions_sync
      ;;
    *) usage_err "unknown command: $cmd" ;;
  esac
}

main "$@"