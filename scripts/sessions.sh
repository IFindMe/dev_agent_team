#!/usr/bin/env bash
# sessions.sh — Standalone session coordinator for multi-agent work.
# Manages per-goal session registries, file-level locks, heartbeats,
# conflict detection, and stale-session cleanup.
# Storage: .tasks/<goal>/sessions.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── helpers ──────────────────────────────────────────────────────────

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_goal_dir() {
  local goal="$1"
  local dir="$REPO_ROOT/.tasks/$goal"
  mkdir -p "$dir"
}

sessions_file() {
  local goal="$1"
  echo "$REPO_ROOT/.tasks/$goal/sessions.json"
}

# Initialise empty sessions.json if missing or empty
init_sessions() {
  local goal="$1"
  local f
  f="$(sessions_file "$goal")"
  if [[ ! -s "$f" ]]; then
    echo '{"sessions":[],"locks":[]}' > "$f"
  fi
}

# Read sessions.json atomically via jq
read_sessions() {
  local goal="$1"
  init_sessions "$goal"
  cat "$(sessions_file "$goal")"
}

# Write sessions.json atomically
write_sessions() {
  local goal="$1"
  local content="$2"
  local f
  f="$(sessions_file "$goal")"
  echo "$content" > "$f"
}

# JSON-file locking via flock (simple, reliable)
lock_json() {
  local goal="$1"
  local f
  f="$(sessions_file "$goal")"
  exec 9>"$f.lock"
  flock 9
}

unlock_json() {
  exec 9>&- 2>/dev/null || true
}

usage() {
  cat <<'EOF'
Usage: sessions.sh <command> [args]

Commands:
  register <agent> --task <id> --goal <goal>   Register an active session
  list [--goal <goal>]                         List active sessions
  lock <file> --by <agent> --goal <goal>       Acquire file-level work lock
  unlock <file> --by <agent>                   Release file lock
  conflicts [--goal <goal>]                    Detect overlapping file edits
  heartbeat <agent> [--goal <goal>]            Refresh lease (update timestamp)
  expire [--goal <goal>] [--stale-minutes N]   Clean stale sessions (default 30)
  unregister <agent> [--goal <goal>]           Remove session
EOF
  exit 1
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ── subcommands ──────────────────────────────────────────────────────

cmd_register() {
  local agent="" task_id="" goal=""
  [[ $# -ge 1 ]] || usage
  agent="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) task_id="$2"; shift 2 ;;
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "$agent" ]] || die "Agent name required"
  [[ -n "$task_id" ]] || die "--task required"
  [[ -n "$goal" ]] || die "--goal required"

  ensure_goal_dir "$goal"
  lock_json "$goal"
  trap 'unlock_json "$goal"' RETURN

  local now
  now="$(now_iso)"
  local current
  current="$(read_sessions "$goal")"

  # Check if agent already registered in this goal
  local exists
  exists="$(echo "$current" | jq -r --arg a "$agent" '[.sessions[] | select(.agent == $a)] | length')"
  if [[ "$exists" -gt 0 ]]; then
    die "Agent '$agent' already registered in goal '$goal'. Unregister first."
  fi

  local updated
  updated="$(echo "$current" | jq \
    --arg agent "$agent" \
    --arg task_id "$task_id" \
    --arg goal "$goal" \
    --arg now "$now" \
    '.sessions += [{"agent":$agent,"task_id":$task_id,"goal":$goal,"registered_at":$now,"last_heartbeat":$now,"files_locked":[]}]')"

  write_sessions "$goal" "$updated"
  echo "OK: registered agent=$agent task=$task_id goal=$goal"
}

cmd_list() {
  local goal=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  if [[ -n "$goal" ]]; then
    local current
    current="$(read_sessions "$goal")"
    echo "$current" | jq -r '.sessions[] | "\(.agent)\t\(.task_id)\t\(.last_heartbeat)\t\(.files_locked | join(","))"'
  else
    # List across all goals
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      jq -r --arg g "$g" '.sessions[] | "\($g)\t\(.agent)\t\(.task_id)\t\(.last_heartbeat)"' "$d"
    done
  fi
}

cmd_lock() {
  local file="" agent="" goal=""
  [[ $# -ge 1 ]] || usage
  file="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by) agent="$2"; shift 2 ;;
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "$agent" ]] || die "--by required"
  [[ -n "$goal" ]] || die "--goal required"

  ensure_goal_dir "$goal"
  lock_json "$goal"
  trap 'unlock_json "$goal"' RETURN

  local current
  current="$(read_sessions "$goal")"

  # Check if file is already locked by a DIFFERENT agent
  local existing_holder
  existing_holder="$(echo "$current" | jq -r --arg f "$file" '[.locks[] | select(.file == $f)][0].locked_by // empty')"
  if [[ -n "$existing_holder" && "$existing_holder" != "$agent" ]]; then
    echo "CONFLICT: file '$file' already locked by '$existing_holder'"
    return 1
  fi

  # If already locked by same agent, idempotent success
  if [[ -n "$existing_holder" && "$existing_holder" == "$agent" ]]; then
    echo "OK: file '$file' already locked by '$agent'"
    return 0
  fi

  local now
  now="$(now_iso)"
  local updated
  updated="$(echo "$current" | jq \
    --arg file "$file" \
    --arg agent "$agent" \
    --arg goal "$goal" \
    --arg now "$now" \
    '.locks += [{"file":$file,"locked_by":$agent,"goal":$goal,"locked_at":$now}]' | jq \
    --arg agent "$agent" \
    --arg file "$file" \
    '.sessions |= map(if .agent == $agent then .files_locked += [$file] else . end)')"

  write_sessions "$goal" "$updated"
  echo "OK: locked '$file' for '$agent'"
}

cmd_unlock() {
  local file="" agent="" goal=""
  [[ $# -ge 1 ]] || usage
  file="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by) agent="$2"; shift 2 ;;
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "$agent" ]] || die "--by required"

  # If no --goal given, search all goals
  if [[ -z "$goal" ]]; then
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      if jq -e --arg f "$file" --arg a "$agent" '[.locks[] | select(.file == $f and .locked_by == $a)] | length > 0' "$d" >/dev/null 2>&1; then
        goal="$g"
        break
      fi
    done
  fi
  [[ -n "$goal" ]] || die "No lock found for file='$file' by '$agent'"

  lock_json "$goal"
  trap 'unlock_json "$goal"' RETURN

  local current
  current="$(read_sessions "$goal")"
  local updated
  updated="$(echo "$current" | jq \
    --arg file "$file" \
    --arg agent "$agent" \
    '.locks = [.locks[] | select(.file != $file or .locked_by != $agent)]' | jq \
    --arg agent "$agent" \
    --arg file "$file" \
    '.sessions |= map(if .agent == $agent then .files_locked = [.files_locked[] | select(. != $file)] else . end)')"

  write_sessions "$goal" "$updated"
  echo "OK: unlocked '$file' for '$agent'"
}

cmd_conflicts() {
  local goal=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  if [[ -n "$goal" ]]; then
    local current
    current="$(read_sessions "$goal")"
    local conflicts
    conflicts="$(echo "$current" | jq '[.locks as $all | $all[] as $l | $all[] | select(.file == $l.file and .locked_by != $l.locked_by) | {file: .file, a1: .locked_by, a2: $l.locked_by}] | unique_by(.file) | [.[] | {file: .file, agents: [.a1, .a2] | unique}]')"
    local count
    count="$(echo "$conflicts" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
      echo "No conflicts"
    else
      echo "$conflicts" | jq -r '.[] | "CONFLICT: \(.file) locked by \(.agents | join(" and "))"'
    fi
  else
    local found=0
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      local current
      current="$(cat "$d")"
      local conflicts
      conflicts="$(echo "$current" | jq '[.locks as $all | $all[] as $l | $all[] | select(.file == $l.file and .locked_by != $l.locked_by) | {file: .file, a1: .locked_by, a2: $l.locked_by}] | unique_by(.file) | [.[] | {file: .file, agents: [.a1, .a2] | unique}]')"
      local count
      count="$(echo "$conflicts" | jq 'length')"
      if [[ "$count" -gt 0 ]]; then
        found=1
        echo "$conflicts" | jq -r --arg g "$g" '.[] | "[$g] CONFLICT: \(.file) locked by \(.agents | join(" and "))"'
      fi
    done
    [[ "$found" -eq 0 ]] && echo "No conflicts"
  fi
}

cmd_heartbeat() {
  local agent="" goal=""
  [[ $# -ge 1 ]] || usage
  agent="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # If no --goal, find which goal the agent belongs to
  if [[ -z "$goal" ]]; then
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      if jq -e --arg a "$agent" '[.sessions[] | select(.agent == $a)] | length > 0' "$d" >/dev/null 2>&1; then
        goal="$g"
        break
      fi
    done
  fi
  [[ -n "$goal" ]] || die "No session found for agent '$agent'"

  lock_json "$goal"
  trap 'unlock_json "$goal"' RETURN

  local current
  current="$(read_sessions "$goal")"
  local now
  now="$(now_iso)"
  local updated
  updated="$(echo "$current" | jq \
    --arg agent "$agent" \
    --arg now "$now" \
    '.sessions |= map(if .agent == $agent then .last_heartbeat = $now else . end)')"

  write_sessions "$goal" "$updated"
  echo "OK: heartbeat refreshed for '$agent'"
}

cmd_expire() {
  local goal="" stale_minutes=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      --stale-minutes) stale_minutes="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  local now_epoch
  now_epoch="$(date +%s)"
  local cutoff_epoch=$(( now_epoch - stale_minutes * 60 ))

  expire_in_goal() {
    local g="$1"
    local f
    f="$(sessions_file "$g")"
    [[ -f "$f" ]] || return 0

    lock_json "$g"
    trap 'unlock_json "$g"' RETURN

    local current
    current="$(read_sessions "$g")"
    local updated
    updated="$(echo "$current" | jq \
      --argjson cutoff "$cutoff_epoch" \
      'def to_epoch: split("T")[0] + " " + (split("T")[1] | split("Z")[0]) | strptime("%Y-%m-%d %H:%M:%S") | mktime;
       .sessions = [.sessions[] | select(.last_heartbeat | to_epoch >= $cutoff)] | (.sessions | map(.agent)) as $active | .locks = [.locks[] | select(.locked_by as $holder | ($active | index($holder)) != null)]')"

    local before_count after_count
    before_count="$(echo "$current" | jq '.sessions | length')"
    after_count="$(echo "$updated" | jq '.sessions | length')"
    local removed=$(( before_count - after_count ))
    if [[ "$removed" -gt 0 ]]; then
      write_sessions "$g" "$updated"
      echo "Expired $removed stale session(s) in goal '$g'"
    else
      echo "No stale sessions in goal '$g'"
    fi
  }

  if [[ -n "$goal" ]]; then
    expire_in_goal "$goal"
  else
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      expire_in_goal "$g"
    done
  fi
}

cmd_unregister() {
  local agent="" goal=""
  [[ $# -ge 1 ]] || usage
  agent="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # If no --goal, find which goal the agent belongs to
  if [[ -z "$goal" ]]; then
    for d in "$REPO_ROOT"/.tasks/*/sessions.json; do
      [[ -f "$d" ]] || continue
      local g
      g="$(basename "$(dirname "$d")")"
      if jq -e --arg a "$agent" '[.sessions[] | select(.agent == $a)] | length > 0' "$d" >/dev/null 2>&1; then
        goal="$g"
        break
      fi
    done
  fi
  [[ -n "$goal" ]] || die "No session found for agent '$agent'"

  lock_json "$goal"
  trap 'unlock_json "$goal"' RETURN

  local current
  current="$(read_sessions "$goal")"
  # Remove session and any locks held by this agent
  local updated
  updated="$(echo "$current" | jq \
    --arg agent "$agent" \
    '.sessions = [.sessions[] | select(.agent != $agent)] |
     .locks = [.locks[] | select(.locked_by != $agent)]')"

  write_sessions "$goal" "$updated"
  echo "OK: unregistered '$agent' from goal '$goal'"
}

# ── main dispatch ────────────────────────────────────────────────────

[[ $# -ge 1 ]] || usage
cmd="$1"; shift

case "$cmd" in
  register)   cmd_register "$@" ;;
  list)       cmd_list "$@" ;;
  lock)       cmd_lock "$@" ;;
  unlock)     cmd_unlock "$@" ;;
  conflicts)  cmd_conflicts "$@" ;;
  heartbeat)  cmd_heartbeat "$@" ;;
  expire)     cmd_expire "$@" ;;
  unregister) cmd_unregister "$@" ;;
  *)          usage ;;
esac
