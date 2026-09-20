#!/usr/bin/env bash
# impact.sh — Map code changes to affected decisions, lessons, tasks, skills,
# and agents. Adapted from CBM BFS blast-radius + risk levels.
#
# Usage:
#   impact.sh                     # diff HEAD~1
#   impact.sh --files "f1 f2"     # explicit file list
#   impact.sh --commit <sha>      # diff against specific commit
#   impact.sh --format json       # JSON output
#   impact.sh --section decisions # only check decisions
#   impact.sh --verbose           # show line numbers
#
# Risk levels:
#   critical  breaks an approved gate or active task assignment
#   high      directly referenced by an active task or in-progress work
#   medium    mentions the changed file or pattern
#   low       tangential reference (same directory, related topic)
#
# Exit: 0 = report produced; 1 = error.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

# ---- defaults ----
COMMIT=""
FILES=""
FORMAT="text"
SECTION=""
VERBOSE=0

# ---- parse args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --files)    FILES="${2:-}"; shift 2 ;;
    --files=*)  FILES="${1#--files=}"; shift ;;
    --commit)   COMMIT="${2:-}"; shift 2 ;;
    --commit=*) COMMIT="${1#--commit=}"; shift ;;
    --format)   FORMAT="${2:-}"; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    --section)  SECTION="${2:-}"; shift 2 ;;
    --section=*) SECTION="${1#--section=}"; shift ;;
    --verbose)  VERBOSE=1; shift ;;
    -h|--help)
      awk 'NR==1{next}/^#/{sub(/^# ?/,"");print;next}{exit}' "$0"
      exit 0 ;;
    *) echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ---- get changed files ----
get_changed_files() {
  if [ -n "$FILES" ]; then
    printf '%s\n' $FILES
  elif [ -n "$COMMIT" ]; then
    git diff --name-only "$COMMIT" HEAD 2>/dev/null
  else
    git diff --name-only HEAD~1 HEAD 2>/dev/null || true
  fi
}

CHANGED=$(get_changed_files)
if [ -z "$CHANGED" ]; then
  echo "No changed files detected." >&2
  exit 0
fi
CHANGED_COUNT=$(printf '%s\n' "$CHANGED" | wc -l)

# ---- build grep patterns from changed file basenames ----
build_patterns() {
  printf '%s\n' "$CHANGED" | while IFS= read -r f; do
    basename "$f"
    basename "$f" | sed 's/\.[^.]*$//'
  done | sort -u
}
PATTERNS=$(build_patterns)

# Build a single grep -E pattern for efficiency
GREP_PATTERN=$(printf '%s\n' "$PATTERNS" | paste -sd'|' -)

# ---- state ----
declare -A COUNTS=([critical]=0 [high]=0 [medium]=0 [low]=0)
TOTAL=0
declare -a SECTION_RESULTS=()  # "section_name|output_line" pairs

add_result() {
  local section="$1" line="$2"
  SECTION_RESULTS+=("${section}|${line}")
}

# ---- check decisions ----
check_decisions() {
  local dir="$PROJECT_ROOT/memory/decisions"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      local lineno=$(echo "$match" | cut -d: -f1)
      local text=$(echo "$match" | cut -d: -f2-)
      local risk="medium"
      if echo "$text" | grep -qiE 'gate|approval|assigned|in_progress|active.task'; then
        risk="high"
      fi
      COUNTS[$risk]=$((COUNTS[$risk] + 1))
      TOTAL=$((TOTAL + 1))
      local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
      local fname=$(basename "$f")
      local detail
      if [ "$VERBOSE" -eq 1 ]; then
        detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
      else
        detail="references $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
      fi
      add_result "decisions" "  $label $fname — $detail"
    done < <(grep -n -iE "$GREP_PATTERN" "$f" 2>/dev/null || true)
  done
}

# ---- check lessons ----
check_lessons() {
  local dir="$PROJECT_ROOT/memory/lessons"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      local lineno=$(echo "$match" | cut -d: -f1)
      local text=$(echo "$match" | cut -d: -f2-)
      local risk="low"
      if echo "$text" | grep -qF '/'; then
        risk="medium"
      fi
      COUNTS[$risk]=$((COUNTS[$risk] + 1))
      TOTAL=$((TOTAL + 1))
      local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
      local fname=$(basename "$f")
      local detail
      if [ "$VERBOSE" -eq 1 ]; then
        detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
      else
        detail="mentions $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
      fi
      add_result "lessons" "  $label $fname — $detail"
    done < <(grep -n -iE "$GREP_PATTERN" "$f" 2>/dev/null || true)
  done
}

# ---- check failures ----
check_failures() {
  local dir="$PROJECT_ROOT/memory/failures"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      local lineno=$(echo "$match" | cut -d: -f1)
      local text=$(echo "$match" | cut -d: -f2-)
      local risk="medium"
      if echo "$text" | grep -qF '/'; then
        risk="high"
      fi
      COUNTS[$risk]=$((COUNTS[$risk] + 1))
      TOTAL=$((TOTAL + 1))
      local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
      local fname=$(basename "$f")
      local detail
      if [ "$VERBOSE" -eq 1 ]; then
        detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
      else
        detail="references $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
      fi
      add_result "failures" "  $label $fname — $detail"
    done < <(grep -n -iE "$GREP_PATTERN" "$f" 2>/dev/null || true)
  done
}

# ---- check tasks ----
check_tasks() {
  local tasks_root="$PROJECT_ROOT/.tasks"
  [ -d "$tasks_root" ] || return 0
  for goal_dir in "$tasks_root"/*/; do
    [ -d "$goal_dir" ] || continue
    local goal=$(basename "$goal_dir")
    local tasks_json="$goal_dir/tasks.json"
    if [ -f "$tasks_json" ]; then
      local ntasks
      ntasks=$(jq '.tasks | length' "$tasks_json" 2>/dev/null || echo 0)
      local i=0
      while [ "$i" -lt "$ntasks" ]; do
        local task_id=$(jq -r ".tasks[$i].id" "$tasks_json" 2>/dev/null)
        local task_status=$(jq -r ".tasks[$i].status // \"unknown\"" "$tasks_json" 2>/dev/null)
        local task_title=$(jq -r ".tasks[$i].title // \"\"" "$tasks_json" 2>/dev/null)
        local task_desc=$(jq -r ".tasks[$i].description // \"\"" "$tasks_json" 2>/dev/null)
        local combined="$task_title $task_desc"
        if echo "$combined" | grep -qiE "$GREP_PATTERN" 2>/dev/null; then
          local risk="medium"
          if [ "$task_status" = "assigned" ] || [ "$task_status" = "in_progress" ]; then
            risk="high"
          fi
          COUNTS[$risk]=$((COUNTS[$risk] + 1))
          TOTAL=$((TOTAL + 1))
          local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
          add_result "tasks" "  $label $goal/$task_id — $task_status: $(echo "$task_title" | head -c 60)"
        fi
        i=$((i + 1))
      done
    fi
    # Grep task markdown files
    for tf in "$goal_dir"/*.md; do
      [ -f "$tf" ] || continue
      [[ "$(basename "$tf")" == "README.md" ]] && continue
      [[ "$(basename "$tf")" == "00-overview.md" ]] && continue
      while IFS= read -r match; do
        [ -z "$match" ] && continue
        local lineno=$(echo "$match" | cut -d: -f1)
        local text=$(echo "$match" | cut -d: -f2-)
        local risk="medium"
        COUNTS[$risk]=$((COUNTS[$risk] + 1))
        TOTAL=$((TOTAL + 1))
        local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
        local fname=$(basename "$tf")
        local detail
        if [ "$VERBOSE" -eq 1 ]; then
          detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
        else
          detail="references $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
        fi
        add_result "tasks" "  $label $goal/$fname — $detail"
      done < <(grep -n -iE "$GREP_PATTERN" "$tf" 2>/dev/null || true)
    done
  done
}

# ---- check skills ----
check_skills() {
  local dir="$PROJECT_ROOT/skills"
  [ -d "$dir" ] || return 0
  for skill_dir in "$dir"/*/; do
    [ -d "$skill_dir" ] || continue
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      local lineno=$(echo "$match" | cut -d: -f1)
      local text=$(echo "$match" | cut -d: -f2-)
      local risk="medium"
      if echo "$text" | grep -qF '/'; then
        risk="high"
      fi
      COUNTS[$risk]=$((COUNTS[$risk] + 1))
      TOTAL=$((TOTAL + 1))
      local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
      local skill_name=$(basename "$skill_dir")
      local detail
      if [ "$VERBOSE" -eq 1 ]; then
        detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
      else
        detail="references $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
      fi
      add_result "skills" "  $label skills/$skill_name/SKILL.md — $detail"
    done < <(grep -n -iE "$GREP_PATTERN" "$skill_file" 2>/dev/null || true)
  done
}

# ---- check agents ----
check_agents() {
  local dir="$PROJECT_ROOT/agents"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      local lineno=$(echo "$match" | cut -d: -f1)
      local text=$(echo "$match" | cut -d: -f2-)
      local risk="low"
      COUNTS[$risk]=$((COUNTS[$risk] + 1))
      TOTAL=$((TOTAL + 1))
      local label="[$(echo "$risk" | tr '[:lower:]' '[:upper:]')]"
      local fname=$(basename "$f")
      local detail
      if [ "$VERBOSE" -eq 1 ]; then
        detail="line $lineno: $(echo "$text" | sed 's/^[[:space:]]*//')"
      else
        detail="references $(echo "$text" | sed 's/^[[:space:]]*//' | head -c 80)"
      fi
      add_result "agents" "  $label agents/$fname — $detail"
    done < <(grep -n -iE "$GREP_PATTERN" "$f" 2>/dev/null || true)
  done
}

# ---- run checks ----
run_checks() {
  local run_all=1
  [ -z "$SECTION" ] || run_all=0

  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "decisions" ]; then check_decisions; fi
  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "lessons" ]; then check_lessons; fi
  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "failures" ]; then check_failures; fi
  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "tasks" ]; then check_tasks; fi
  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "skills" ]; then check_skills; fi
  if [ "$run_all" -eq 1 ] || [ "$SECTION" = "agents" ]; then check_agents; fi
}

# ---- output: text ----
output_text() {
  echo "Impact Report: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Changed files: $CHANGED_COUNT"
  echo ""

  local prev_section=""
  for entry in "${SECTION_RESULTS[@]}"; do
    local sec="${entry%%|*}"
    local line="${entry#*|}"
    if [ "$sec" != "$prev_section" ]; then
      [ -n "$prev_section" ] && echo ""
      case "$sec" in
        decisions) echo "Impact on Decisions (memory/decisions/):" ;;
        lessons)   echo "Impact on Lessons (memory/lessons/):" ;;
        failures)  echo "Impact on Memory Failures (memory/failures/):" ;;
        tasks)     echo "Impact on Tasks (.tasks/):" ;;
        skills)    echo "Impact on Skills (skills/):" ;;
        agents)    echo "Impact on Agents (agents/):" ;;
      esac
      prev_section="$sec"
    fi
    printf '%s\n' "$line"
  done

  echo ""
  echo "Summary: critical=${COUNTS[critical]}, high=${COUNTS[high]}, medium=${COUNTS[medium]}, low=${COUNTS[low]}, total=$TOTAL"
}

# ---- output: json ----
output_json() {
  # Collect all results per section
  declare -A SEC_LINES=()
  for entry in "${SECTION_RESULTS[@]}"; do
    local sec="${entry%%|*}"
    local line="${entry#*|}"
    SEC_LINES[$sec]+="${line}"$'\n'
  done

  printf '{\n'
  printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "changed_files": %d,\n' "$CHANGED_COUNT"
  printf '  "changed": [\n'
  local first=1
  printf '%s\n' "$CHANGED" | while IFS= read -r f; do
    [ "$first" -eq 1 ] || printf ',\n'
    printf '    "%s"' "$f"
    first=0
  done
  printf '\n  ],\n'

  # Sections with results
  local first_sec=1
  printf '  "sections": {\n'
  for sec in decisions lessons failures tasks skills agents; do
    if [ -n "${SEC_LINES[$sec]:-}" ]; then
      [ "$first_sec" -eq 1 ] || printf ',\n'
      printf '    "%s": [\n' "$sec"
      local first_line=1
      while IFS= read -r l; do
        [ -z "$l" ] && continue
        [ "$first_line" -eq 1 ] || printf ',\n'
        # Escape for JSON
        local escaped=$(printf '%s' "$l" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '      "%s"' "$escaped"
        first_line=0
      done <<< "${SEC_LINES[$sec]}"
      printf '\n    ]'
      first_sec=0
    fi
  done
  printf '\n  },\n'

  printf '  "summary": {\n'
  printf '    "critical": %d,\n' "${COUNTS[critical]}"
  printf '    "high": %d,\n' "${COUNTS[high]}"
  printf '    "medium": %d,\n' "${COUNTS[medium]}"
  printf '    "low": %d,\n' "${COUNTS[low]}"
  printf '    "total": %d\n' "$TOTAL"
  printf '  }\n'
  printf '}\n'
}

# ---- main ----
run_checks

case "$FORMAT" in
  json) output_json ;;
  text) output_text ;;
  *) echo "ERROR: unknown format: $FORMAT (text|json)" >&2; exit 2 ;;
esac
