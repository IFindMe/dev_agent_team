#!/usr/bin/env bash
set -euo pipefail

# Install the 12 dev_agent_team opencode agents into a local opencode config.
#
# Usage:   ./scripts/install.sh
# Override target dir with: OPENCODE_AGENTS_DIR=/some/dir ./scripts/install.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${OPENCODE_AGENTS_DIR:-$HOME/.config/opencode/agents}"
EXPECTED_COUNT=12
KEEP_BACKUPS=5

echo "==> dev_agent_team installer"
echo "==> Source:      $ROOT/agents"
echo "==> Destination: $TARGET"

# Resolve the agent source list into an array up front (nullglob: no match
# means an empty array, not a literal glob string).
shopt -s nullglob
AGENT_FILES=( "$ROOT"/agents/*.md )
shopt -u nullglob

# Gate BEFORE any copying: refuse to touch anything unless the full set
# exists at the source.
if (( ${#AGENT_FILES[@]} < EXPECTED_COUNT )); then
  echo "ERROR: expected $EXPECTED_COUNT agent files in $ROOT/agents, found ${#AGENT_FILES[@]}. Aborting." >&2
  exit 1
fi

mkdir -p "$TARGET"

STAMP="$(date +%Y%m%d_%H%M%S)_$$"  # PID suffix keeps rapid reruns distinct
BACKUP_DIR="$TARGET/.backup/$STAMP"

# Back up any pre-existing same-named files before touching them.
backed_up=0
for src_path in "${AGENT_FILES[@]}"; do
  name="$(basename "$src_path")"
  if [[ -e "$TARGET/$name" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -p "$TARGET/$name" "$BACKUP_DIR/$name"
    echo "    backed up: $name -> .backup/$STAMP/$name"
    backed_up=$((backed_up + 1))
  fi
done

# Retention cap: after creating a new backup dir, keep only the most recent
# stamp dirs. Stamp names sort chronologically, so name order == age order.
# Only entries matching the stamp pattern are considered; all writes stay
# inside $TARGET/.backup/.
if (( backed_up > 0 )); then
  shopt -s nullglob
  backup_dirs=( "$TARGET"/.backup/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_* )
  shopt -u nullglob
  excess=$(( ${#backup_dirs[@]} - KEEP_BACKUPS ))
  if (( excess > 0 )); then
    for prune_dir in "${backup_dirs[@]:0:excess}"; do
      [ -d "$prune_dir" ] || continue
      rm -rf "$prune_dir"
      echo "    pruned old backup: .backup/$(basename "$prune_dir")"
    done
  fi
fi

# Copy the agents.
copied=0
for src_path in "${AGENT_FILES[@]}"; do
  name="$(basename "$src_path")"
  cp -p "$src_path" "$TARGET/$name"
  echo "    copied: $name"
  copied=$((copied + 1))
done

# Fail loudly if the expected set was not installed.
if (( copied != EXPECTED_COUNT )); then
  echo "ERROR: expected $EXPECTED_COUNT agent files, but installed $copied. Aborting." >&2
  exit 1
fi

# Decision-4 gate 1 — byte integrity: every installed file must be a faithful
# copy of its repo source (install is cp -p, no transformation). Copy-all first,
# verify-all after: a failure aborts with a nonzero exit and no success message.
for src_path in "${AGENT_FILES[@]}"; do
  name="$(basename "$src_path")"
  if ! cmp -s "$src_path" "$TARGET/$name"; then
    echo "ERROR: integrity check failed for '$name' ($TARGET/$name differs from $src_path). Aborting." >&2
    exit 1
  fi
done

# Decision-4 gate 2 — engine semantics: the installed definitions are only
# trustworthy if the target opencode engine matches the documented matching
# rules. Verifier exits: 0 = pass, 1 = engine drift, 2 = no usable runtime.
echo "==> Verifying permission-engine semantics..."
rc=0
sh "$ROOT/scripts/verify-permission-patterns.sh" || rc=$?
case "$rc" in
  0) ;;
  1) echo "ERROR: ENGINE DRIFT — opencode permission matching does NOT match documented semantics; installed definitions cannot be trusted. Aborting." >&2; exit 1 ;;
  2) echo "ERROR: NO RUNTIME — no opencode binary found (set OPENCODE_BIN to override); install completed but CANNOT be verified. Aborting." >&2; exit 2 ;;
  *) echo "ERROR: verifier exited unexpectedly (rc=$rc). Aborting." >&2; exit "$rc" ;;
esac

echo "==> Installed $copied/$EXPECTED_COUNT agents."

if (( backed_up > 0 )); then
  echo "==> Previous versions of $backed_up file(s) saved under: $BACKUP_DIR"
fi

# Post-install reminder (non-fatal if opencode is absent).
if command -v opencode >/dev/null 2>&1; then
  echo "==> Reminder: restart opencode, then run: opencode agent list"
else
  echo "==> Note: 'opencode' not found on PATH; skipped restart/verify reminder."
fi

echo "==> Done."
