#!/usr/bin/env bash
set -euo pipefail

# memory-lifecycle.sh — Manage project memory: recall, store, list, search
#
# Usage:
#   memory-lifecycle.sh recall <category> [query]    — search memory for relevant entries
#   memory-lifecycle.sh store <category> <file>      — add or update a memory entry
#   memory-lifecycle.sh list <category>              — list entries in a category
#   memory-lifecycle.sh search <query>               — full-text search across all memory
#   memory-lifecycle.sh sessions                     — list active/interrupted sessions
#   memory-lifecycle.sh cleanup                      — archive old completed sessions
#
# Categories: decisions, lessons, failures, architecture, sessions
#
# This script provides deterministic memory operations for the agent team.
# It does NOT do semantic search — that is the Orchestrator's responsibility
# using agent reasoning over the recalled entries.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_DIR="$ROOT/memory"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# --- recall -----------------------------------------------------------------

cmd_recall() {
  local category="$1" query="${2:-}"
  local dir="$MEMORY_DIR/$category"

  if [ ! -d "$dir" ]; then
    echo "ERROR: memory category '$category' does not exist" >&2
    exit 1
  fi

  echo "=== Memory recall: $category ==="
  if [ -n "$query" ]; then
    echo "Query: $query"
    echo "---"
    # Search for matching entries (case-insensitive grep)
    local found=0
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "README.md" ] && continue
      if grep -qiF "$query" "$f" 2>/dev/null; then
        echo "  FOUND: $(basename "$f")"
        # Show matching lines with context
        grep -iF "$query" "$f" | head -5 | sed 's/^/    /'
        found=$((found + 1))
      fi
    done
    if [ "$found" = "0" ]; then
      echo "  No entries matching '$query' in $category"
    else
      echo "  ---"
      echo "  $found matching entr(y/ies)"
    fi
  else
    # List all entries
    local count=0
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "README.md" ] && continue
      echo "  $(basename "$f")"
      count=$((count + 1))
    done
    if [ "$count" = "0" ]; then
      echo "  No entries in $category"
    else
      echo "  ---"
      echo "  $count entr(y/ies)"
    fi
  fi
}

# --- store ------------------------------------------------------------------

cmd_store() {
  local category="$1" file="$2"
  local dir="$MEMORY_DIR/$category"

  if [ ! -d "$dir" ]; then
    echo "ERROR: memory category '$category' does not exist" >&2
    exit 1
  fi

  if [ ! -f "$file" ]; then
    echo "ERROR: source file '$file' does not exist" >&2
    exit 1
  fi

  local basename
  basename="$(basename "$file")"
  local dest="$dir/$basename"

  if [ -f "$dest" ]; then
    echo "UPDATED: $category/$basename"
  else
    echo "CREATED: $category/$basename"
  fi

  cp -p "$file" "$dest"
}

# --- list -------------------------------------------------------------------

cmd_list() {
  local category="$1"
  cmd_recall "$category" ""
}

# --- search -----------------------------------------------------------------

cmd_search() {
  local query="$1"
  echo "=== Full-text memory search: '$query' ==="
  local found=0

  for category in decisions lessons failures architecture sessions; do
    local dir="$MEMORY_DIR/$category"
    [ -d "$dir" ] || continue

    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "README.md" ] && continue
      if grep -qiF "$query" "$f" 2>/dev/null; then
        echo "  $category/$(basename "$f")"
        found=$((found + 1))
      fi
    done
  done

  if [ "$found" = "0" ]; then
    echo "  No entries matching '$query'"
  else
    echo "  ---"
    echo "  $found matching entr(y/ies) across all categories"
  fi
}

# --- sessions ---------------------------------------------------------------

cmd_sessions() {
  echo "=== Active/Interrupted Sessions ==="
  local dir="$MEMORY_DIR/sessions"
  local count=0

  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "README.md" ] && continue

    local status
    status=$(grep -m1 "^Status:" "$f" 2>/dev/null | sed 's/^Status: *//' || echo "unknown")
    if [ "$status" = "active" ] || [ "$status" = "interrupted" ]; then
      local title
      title=$(grep -m1 "^# " "$f" 2>/dev/null | sed 's/^# //' || echo "$(basename "$f")")
      echo "  [$status] $(basename "$f"): $title"
      count=$((count + 1))
    fi
  done

  if [ "$count" = "0" ]; then
    echo "  No active or interrupted sessions"
  fi
}

# --- cleanup ----------------------------------------------------------------

cmd_cleanup() {
  echo "=== Session cleanup ==="
  local dir="$MEMORY_DIR/sessions"
  local archived=0

  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "README.md" ] && continue

    local status
    status=$(grep -m1 "^Status:" "$f" 2>/dev/null | sed 's/^Status: *//' || echo "unknown")

    if [ "$status" = "completed" ]; then
      # Check if older than 7 days
      local file_age
      file_age=$(( ($(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0)) / 86400 ))
      if [ "$file_age" -gt 7 ]; then
        local dest="$dir/archive"
        mkdir -p "$dest"
        mv "$f" "$dest/"
        echo "  Archived: $(basename "$f") (age: ${file_age}d)"
        archived=$((archived + 1))
      fi
    fi
  done

  if [ "$archived" = "0" ]; then
    echo "  No sessions to archive"
  else
    echo "  Archived $archived session(s)"
  fi
}

# --- main -------------------------------------------------------------------

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  recall)
    [ $# -ge 1 ] || { echo "ERROR: recall requires a category" >&2; usage; }
    cmd_recall "$1" "${2:-}"
    ;;
  store)
    [ $# -ge 2 ] || { echo "ERROR: store requires a category and file" >&2; usage; }
    cmd_store "$1" "$2"
    ;;
  list)
    [ $# -ge 1 ] || { echo "ERROR: list requires a category" >&2; usage; }
    cmd_list "$1"
    ;;
  search)
    [ $# -ge 1 ] || { echo "ERROR: search requires a query" >&2; usage; }
    cmd_search "$1"
    ;;
  sessions)
    cmd_sessions
    ;;
  cleanup)
    cmd_cleanup
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "ERROR: unknown command: $CMD" >&2
    usage
    ;;
esac
