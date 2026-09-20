#!/usr/bin/env bash
# adr.sh — Architecture Decision Record management CLI.
#
# Manages ADRs as individual markdown files in memory/decisions/.
# Inspired by CBM's section-splicing model (cbm_adr_*), adapted to bash/markdown.
#
# Usage:
#   adr.sh create <id> --title "..." [--status proposed] [--tags "tag1,tag2"]
#   adr.sh get <id> [--section <name>]
#   adr.sh set <id> <section> --body "text"
#   adr.sh set <id> <section> --body-ref <file>
#   adr.sh list [--status <status>] [--tag <tag>]
#   adr.sh search <query>
#   adr.sh supersedes <old-id> <new-id>
#   adr.sh validate <id>
#   adr.sh export
#   adr.sh -h|--help|help
#
# Exit codes: 0=ok, 1=error, 2=usage

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
MEMORY_DIR="${OPENCODE_MEMORY_DIR:-$PROJECT_ROOT/memory}"
ADR_DIR="$MEMORY_DIR/decisions"

# ── Helpers ──────────────────────────────────────────────────────────────

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

die()  { echo "error: $*" >&2; exit 1; }
die2() { echo "usage: $*" >&2; exit 2; }

adr_file() { echo "$ADR_DIR/$1.md"; }

# ensure_dir — create ADR directory if missing
ensure_dir() { mkdir -p "$ADR_DIR"; }

# ── Section splicing engine ──────────────────────────────────────────────
# Reads markdown from stdin, replaces body of "## <heading>" with new body,
# preserves everything else.  Handles the first section (YAML-like header)
# via a special "## Header" sentinel.

splice_section() {
  local heading="$1" new_body="$2"
  local in_section=0 found=0
  local line

  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+ ]]; then
      local h
      h="$(echo "$line" | sed 's/^##[[:space:]]*//')"
      if [[ $in_section -eq 1 ]]; then
        # Leaving target section: emit new body, then this heading
        echo "$new_body"
        in_section=0
      fi
      if [[ "$h" == "$heading" ]]; then
        in_section=1; found=1
        echo "$line"
        continue
      fi
    fi
    # Skip old body lines if inside target section
    [[ $in_section -eq 1 ]] && continue
    echo "$line"
  done

  # If target section was last, emit new body at EOF
  if [[ $in_section -eq 1 ]]; then
    echo "$new_body"
  fi

  [[ $found -eq 1 ]]
}

# extract_section — read markdown from stdin, output body of "## <heading>"
extract_section() {
  local heading="$1"
  local in_section=0 line first=1
  local result=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+ ]]; then
      local h
      h="$(echo "$line" | sed 's/^##[[:space:]]*//')"
      if [[ "$h" == "$heading" ]]; then
        in_section=1
        continue
      elif [[ $in_section -eq 1 ]]; then
        break
      fi
    fi
    if [[ $in_section -eq 1 ]]; then
      if [[ $first -eq 1 ]]; then
        result="$line"
        first=0
      else
        result="$result
$line"
      fi
    fi
  done

  echo "$result"
}

# extract_front_field — get "Field: value" from markdown frontmatter
extract_front_field() {
  local file="$1" field="$2"
  grep -m1 "^${field}:" "$file" 2>/dev/null | sed "s/^${field}:[[:space:]]*//" || true
}

# ── Commands ─────────────────────────────────────────────────────────────

cmd_create() {
  local id="" title="" status="proposed" tags=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)  title="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --tags)   tags="$2"; shift 2 ;;
      *)        id="$1"; shift ;;
    esac
  done

  [[ -n "$id" ]]    || die2 "adr.sh create <id> --title \"...\" [options]"
  [[ -n "$title" ]]  || die2 "adr.sh create $id --title \"...\""
  [[ "$status" =~ ^(proposed|accepted|deprecated|superseded)$ ]] || die "invalid status: $status"

  ensure_dir
  local file
  file="$(adr_file "$id")"

  [[ -f "$file" ]] && die "ADR $id already exists: $file"

  cat > "$file" <<EOF
# ADR-${id}: ${title}
Date: $(date +%Y-%m-%d)
Status: ${status}
Tags: ${tags}

## Purpose

## Context

## Decision

## Consequences

## Alternatives

## References
EOF

  echo "$file"
}

cmd_get() {
  local id="" section=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section) section="$2"; shift 2 ;;
      *)         id="$1"; shift ;;
    esac
  done

  [[ -n "$id" ]] || die2 "adr.sh get <id> [--section <name>]"

  local file
  file="$(adr_file "$id")"
  [[ -f "$file" ]] || die "ADR $id not found: $file"

  if [[ -n "$section" ]]; then
    extract_section "$section" < "$file"
  else
    cat "$file"
  fi
}

cmd_set() {
  local id="" section="" body="" body_ref=""

  # First two positional args are id and section
  [[ $# -ge 1 && "$1" != --* ]] && { id="$1"; shift; }
  [[ $# -ge 1 && "$1" != --* ]] && { section="$1"; shift; }

  # Remaining: flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)     body="$2"; shift 2 ;;
      --body-ref) body_ref="$2"; shift 2 ;;
      *)          shift ;;
    esac
  done

  [[ -n "$id" ]]      || die2 "adr.sh set <id> <section> --body \"text\" | --body-ref <file>"
  [[ -n "$section" ]]  || die2 "adr.sh set <id> <section> --body \"text\" | --body-ref <file>"

  local new_body=""
  if [[ -n "$body_ref" ]]; then
    [[ -f "$body_ref" ]] || die "body-ref file not found: $body_ref"
    new_body="$(cat "$body_ref")"
  elif [[ -n "$body" ]]; then
    new_body="$body"
  else
    die2 "adr.sh set <id> <section> --body \"text\" | --body-ref <file>"
  fi

  local file
  file="$(adr_file "$id")"
  [[ -f "$file" ]] || die "ADR $id not found: $file"

  local tmp
  tmp="$(mktemp)"

  if ! splice_section "$section" "$new_body" < "$file" > "$tmp"; then
    rm -f "$tmp"
    die "section '$section' not found in ADR $id"
  fi
  mv "$tmp" "$file"
  echo "$file"
}

cmd_list() {
  local filter_status="" filter_tag=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) filter_status="$2"; shift 2 ;;
      --tag)    filter_tag="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  ensure_dir

  local count=0
  for f in "$ADR_DIR"/*.md; do
    [[ -f "$f" ]] || continue

    if [[ -n "$filter_status" ]]; then
      local s
      s="$(extract_front_field "$f" "Status")"
      [[ "$s" == "$filter_status" ]] || continue
    fi

    if [[ -n "$filter_tag" ]]; then
      local tg
      tg="$(extract_front_field "$f" "Tags")"
      echo "$tg" | grep -qi "$filter_tag" || continue
    fi

    local base
    base="$(basename "$f" .md)"
    local title date status
    title="$(grep -m1 '^# ' "$f" | sed 's/^# [^:]*: //')"
    date="$(extract_front_field "$f" "Date")"
    status="$(extract_front_field "$f" "Status")"
    printf "%-12s %-8s %-12s %s\n" "$base" "$status" "$date" "$title"
    count=$((count + 1))
  done

  [[ $count -gt 0 ]] || echo "(no ADRs found)"
}

cmd_search() {
  local query="$1"
  [[ -n "$query" ]] || die2 "adr.sh search <query>"

  ensure_dir
  grep -rn -i "$query" "$ADR_DIR"/ 2>/dev/null || echo "(no matches)"
}

cmd_supersedes() {
  local old_id="$1" new_id="$2"
  [[ -n "$old_id" && -n "$new_id" ]] || die2 "adr.sh supersedes <old-id> <new-id>"

  local old_file new_file
  old_file="$(adr_file "$old_id")"
  new_file="$(adr_file "$new_id")"
  [[ -f "$old_file" ]] || die "ADR $old_id not found: $old_file"
  [[ -f "$new_file" ]] || die "ADR $new_id not found: $new_file"

  # Update old ADR: set Superseded-by
  if grep -q "^Superseded-by:" "$old_file"; then
    sed -i "s/^Superseded-by:.*/Superseded-by: $new_id/" "$old_file"
  else
    # Insert after Tags line
    sed -i "/^Tags:/a Superseded-by: $new_id" "$old_file"
  fi

  # Update new ADR: set Supersedes
  if grep -q "^Supersedes:" "$new_file"; then
    sed -i "s/^Supersedes:.*/Supersedes: $old_id/" "$new_file"
  else
    sed -i "/^Tags:/a Supersedes: $old_id" "$new_file"
  fi

  echo "$old_file"
  echo "$new_file"
}

cmd_validate() {
  local id="$1"
  [[ -n "$id" ]] || die2 "adr.sh validate <id>"

  local file
  file="$(adr_file "$id")"
  [[ -f "$file" ]] || die "ADR $id not found: $file"

  local required=("Purpose" "Decision" "Consequences")
  local ok=1

  for section in "${required[@]}"; do
    local body
    body="$(extract_section "$section" < "$file")"
    if [[ -z "$body" || "$body" =~ ^[[:space:]]*$ ]]; then
      echo "MISSING: $section"
      ok=0
    else
      echo "OK: $section"
    fi
  done

  [[ $ok -eq 1 ]]
}

cmd_export() {
  ensure_dir

  for f in "$ADR_DIR"/*.md; do
    [[ -f "$f" ]] || continue

    local id title date status tags
    id="$(basename "$f" .md)"
    title="$(grep -m1 '^# ' "$f" | sed 's/^# [^:]*: //')"
    date="$(extract_front_field "$f" "Date")"
    status="$(extract_front_field "$f" "Status")"
    tags="$(extract_front_field "$f" "Tags")"

    # Extract all sections into a JSON object
    local purpose context decision consequences alternatives references
    purpose="$(extract_section "Purpose" < "$f")"
    context="$(extract_section "Context" < "$f")"
    decision="$(extract_section "Decision" < "$f")"
    consequences="$(extract_section "Consequences" < "$f")"
    alternatives="$(extract_section "Alternatives" < "$f")"
    references="$(extract_section "References" < "$f")"

    # Use jq if available, else basic printf
    if command -v jq >/dev/null 2>&1; then
      jq -cn \
        --arg id "$id" \
        --arg title "$title" \
        --arg date "$date" \
        --arg status "$status" \
        --arg tags "$tags" \
        --arg purpose "$purpose" \
        --arg context "$context" \
        --arg decision "$decision" \
        --arg consequences "$consequences" \
        --arg alternatives "$alternatives" \
        --arg references "$references" \
        '{id:$id,title:$title,date:$date,status:$status,tags:$tags,purpose:$purpose,context:$context,decision:$decision,consequences:$consequences,alternatives:$alternatives,references:$references}'
    else
      printf '{"id":"%s","title":"%s","date":"%s","status":"%s","tags":"%s"}\n' \
        "$id" "$title" "$date" "$status" "$tags"
    fi
  done
}

# ── Main dispatch ────────────────────────────────────────────────────────

main() {
  [[ $# -gt 0 ]] || usage

  local cmd="$1"; shift

  case "$cmd" in
    -h|--help|help) usage ;;
    create)     cmd_create "$@" ;;
    get)        cmd_get "$@" ;;
    set)        cmd_set "$@" ;;
    list)       cmd_list "$@" ;;
    search)     cmd_search "$@" ;;
    supersedes) cmd_supersedes "$@" ;;
    validate)   cmd_validate "$@" ;;
    export)     cmd_export "$@" ;;
    *)          die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
