#!/usr/bin/env bash
set -euo pipefail

# Install the 14 dev_agent_team opencode agents AND the self-contained runtime
# tree into a local opencode config.
#
# The runtime tree is installed under $OPENCODE_DEV_AGENT_TEAM (default
# $XDG_CONFIG_HOME/opencode/dev-agent-team, fallback ~/.config/opencode/dev-agent-team):
#   bin/            - memory-lifecycle.sh, repo-bootstrap.sh, verify-permission-patterns.sh, state.sh, agora.sh, test suites
#   skills/         - 13 general-purpose skills + SKILLS.md (managed, read-only)
#   improvements/   - README (only if absent) + pending/applied/rejected (user data, never overwritten)
#   install-manifest.json - version, date, installed file list + sha256
#
# Usage:
#   ./scripts/install.sh                # install runtime tree (agents + runtime)
#   ./scripts/install.sh --uninstall    # remove manifest-tracked install
#   ./scripts/install.sh --uninstall --purge   # also remove improvements/ user data
#   ./scripts/install.sh --migrate      # import pending improvement proposals (no-op today)
#   ./scripts/install.sh --self-test    # run the new runtime test suites in a temp HOME
#
# Override target with: OPENCODE_AGENTS_DIR=/some/dir
# Override runtime root with: OPENCODE_DEV_AGENT_TEAM=/some/runtime

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${OPENCODE_AGENTS_DIR:-$HOME/.config/opencode/agents}"
EXPECTED_COUNT=14
KEEP_BACKUPS=5

# Runtime root resolution (D3/D8): env var first, then XDG_CONFIG_HOME, then
# ~/.config/opencode/dev-agent-team.
if [ -n "${OPENCODE_DEV_AGENT_TEAM:-}" ]; then
  RUNTIME_ROOT="$OPENCODE_DEV_AGENT_TEAM"
elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
  RUNTIME_ROOT="$XDG_CONFIG_HOME/opencode/dev-agent-team"
else
  RUNTIME_ROOT="$HOME/.config/opencode/dev-agent-team"
fi

MANIFEST="$RUNTIME_ROOT/install-manifest.json"
STAMP="$(date +%Y%m%d_%H%M%S)_$$"

log() { echo "==> $*"; }

# --------------------------------------------------------------------- #
# Usage / flags
# --------------------------------------------------------------------- #
usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

SELF_TEST=0
UNINSTALL=0
PURGE=0
MIGRATE=0

for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --purge)     PURGE=1 ;;
    --migrate)   MIGRATE=1 ;;
    --self-test) SELF_TEST=1 ;;
    -h|--help)   usage ;;
    *)           echo "ERROR: unknown option: $arg" >&2; usage ;;
  esac
done

# --------------------------------------------------------------------- #
# Uninstall (D9)
# --------------------------------------------------------------------- #
if [ "$UNINSTALL" = "1" ]; then
  log "Uninstalling dev_agent_team agents + runtime"

  # Honor the agents target recorded by the manifest if not overridden.
  if [ -z "${OPENCODE_AGENTS_DIR:-}" ] && [ -f "$MANIFEST" ]; then
    MAN_TARGET="$(sed -n 's/.*"agents_target": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)"
    [ -n "$MAN_TARGET" ] && TARGET="$MAN_TARGET"
  fi

  if [ -f "$MANIFEST" ]; then
    # Remove manifest-tracked agent files from $TARGET (entries with file: agents/...)
    removed=0
    while IFS= read -r line; do
      tgt="$(printf '%s' "$line" | sed -n 's/.*"target": "\([^"]*\)".*/\1/p')"
      if [ -n "$tgt" ] && [ -f "$TARGET/$tgt" ]; then
        rm -f "$TARGET/$tgt"
        removed=$((removed + 1))
      fi
    done < <(grep '"file": "agents/' "$MANIFEST" || true)
    log "Removed $removed agent file(s) tracked by manifest."
  else
    log "No manifest at $MANIFEST; removing runtime root directly."
  fi

  # Leave agent backups in place and print their location.
  BACKUP_TARGET="$TARGET/.backup"
  if [ -d "$BACKUP_TARGET" ]; then
    log "Agent backups left in place under: $BACKUP_TARGET"
  fi

  # Remove runtime root; preserve improvements/ unless --purge.
  if [ -d "$RUNTIME_ROOT" ]; then
    if [ "$PURGE" = "1" ]; then
      rm -rf "$RUNTIME_ROOT"
      log "Removed runtime root: $RUNTIME_ROOT (--purge: including improvements/ user data)"
    else
      # Preserve improvements/ user data: move it aside to a location OUTSIDE
      # the runtime root (never inside, or the rm -rf below would delete it),
      # remove the rest of the tree, then restore. Clean up the temp save dir.
      IMPROV="$RUNTIME_ROOT/improvements"
      if [ -d "$IMPROV" ]; then
        IMPROV_PARENT="$(dirname "$RUNTIME_ROOT")"
        IMPROV_SAVE="$(mktemp -d "$IMPROV_PARENT/.improvements-user.XXXXXX" 2>/dev/null || true)"
        if [ -z "$IMPROV_SAVE" ]; then
          # Fail-safe: single sibling path (still outside the runtime root).
          IMPROV_SAVE="$IMPROV_PARENT/.improvements-user"
          rm -rf "$IMPROV_SAVE"
        fi
        mv "$IMPROV" "$IMPROV_SAVE/user"
        rm -rf "$RUNTIME_ROOT"
        mkdir -p "$RUNTIME_ROOT"
        mv "$IMPROV_SAVE/user" "$IMPROV"
        rmdir "$IMPROV_SAVE" >/dev/null 2>&1 || true
        log "Preserved improvements/ user data at: $IMPROV"
        log "Runtime root removed (excluding improvements/)."
      else
        rm -rf "$RUNTIME_ROOT"
        log "Runtime root removed: $RUNTIME_ROOT"
      fi
    fi
  fi

  # Ask before removing the rc export line (it may be shared).
  RC_FILE=""
  [ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"
  [ -z "$RC_FILE" ] && [ -f "$HOME/.profile" ] && RC_FILE="$HOME/.profile"
  if [ -n "$RC_FILE" ] && grep -q 'OPENCODE_DEV_AGENT_TEAM' "$RC_FILE"; then
    echo ""
    echo "The shell-rc export of OPENCODE_DEV_AGENT_TEAM exists in $RC_FILE."
    printf 'Remove it? [y/N] ' >&2
    read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES) sed -i '/OPENCODE_DEV_AGENT_TEAM/d' "$RC_FILE"; log "Removed OPENCODE_DEV_AGENT_TEAM export from $RC_FILE." ;;
      *) log "Left OPENCODE_DEV_AGENT_TEAM export in $RC_FILE." ;;
    esac
  fi

  log "Uninstall complete. Never touched: project memory/, .opencode/, AgentsReport/, user opencode.json."
  exit 0
fi

# --------------------------------------------------------------------- #
# Migrate (D10) — minimal one-time import of pending proposals (no-op today)
# --------------------------------------------------------------------- #
if [ "$MIGRATE" = "1" ]; then
  log "Migrate mode: import pending improvement proposals from source checkout."
  SRC_IMPROV="$ROOT/improvements"
  DST_IMPROV="$RUNTIME_ROOT/improvements"
  imported=0
  if [ -d "$SRC_IMPROV/pending" ]; then
    mkdir -p "$DST_IMPROV/pending" 2>/dev/null || true
    for p in "$SRC_IMPROV"/pending/*.md; do
      [ -f "$p" ] || continue
      name="$(basename "$p")"
      if [ ! -f "$DST_IMPROV/pending/$name" ]; then
        cp -p "$p" "$DST_IMPROV/pending/$name"
        log "Imported pending: $name"
        imported=$((imported + 1))
      else
        log "Skipped (already present): $name"
      fi
    done
  fi
  log "Migrate complete: imported $imported pending proposal(s) (no-op today — only README exists)."
  exit 0
fi

# --------------------------------------------------------------------- #
# Agent install (preserve existing behavior exactly)
# --------------------------------------------------------------------- #
log "dev_agent_team installer"
log "Source:      $ROOT/agents"
log "Destination: $TARGET"
log "Runtime:     $RUNTIME_ROOT"

shopt -s nullglob
AGENT_FILES=( "$ROOT"/agents/*.md )
shopt -u nullglob

# Gate BEFORE any copying: refuse to touch anything unless the full set exists.
if (( ${#AGENT_FILES[@]} < EXPECTED_COUNT )); then
  echo "ERROR: expected $EXPECTED_COUNT agent files in $ROOT/agents, found ${#AGENT_FILES[@]}. Aborting." >&2
  exit 1
fi

mkdir -p "$TARGET"

BACKUP_DIR="$TARGET/.backup/$STAMP"

# Back up any pre-existing same-named agent files before touching them.
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

# Retention cap (agents) — keep only the most recent KEEP_BACKUPS stamp dirs.
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

if (( copied != EXPECTED_COUNT )); then
  echo "ERROR: expected $EXPECTED_COUNT agent files, but installed $copied. Aborting." >&2
  exit 1
fi

# Decision-4 gate 1 — byte integrity (cmp -s).
for src_path in "${AGENT_FILES[@]}"; do
  name="$(basename "$src_path")"
  if ! cmp -s "$src_path" "$TARGET/$name"; then
    echo "ERROR: integrity check failed for '$name' ($TARGET/$name differs from $src_path). Aborting." >&2
    exit 1
  fi
done

# Decision-4 gate 2 — permission-engine semantics.
echo "==> Verifying permission-engine semantics..."
rc=0
sh "$ROOT/scripts/verify-permission-patterns.sh" || rc=$?
case "$rc" in
  0) ;;
  1) echo "ERROR: ENGINE DRIFT — opencode permission matching does NOT match documented semantics; installed definitions cannot be trusted. Aborting." >&2; exit 1 ;;
  2) echo "ERROR: NO RUNTIME — no opencode binary found (set OPENCODE_BIN to override); install completed but CANNOT be verified." >&2 ;;
  *) echo "ERROR: verifier exited unexpectedly (rc=$rc). Aborting." >&2; exit "$rc" ;;
esac

echo "==> Installed $copied/$EXPECTED_COUNT agents."

if (( backed_up > 0 )); then
  echo "==> Previous versions of $backed_up file(s) saved under: $BACKUP_DIR"
fi

# --------------------------------------------------------------------- #
# Runtime tree install (D8)
# --------------------------------------------------------------------- #
echo "==> Installing runtime tree into $RUNTIME_ROOT"

mkdir -p "$RUNTIME_ROOT"

# Managed-subtree backup + retention: back up replaced runtime files before
# overwriting, under $RUNTIME_ROOT/.backup/<stamp>/, with KEEP_BACKUPS=5.
RT_BACKUP_DIR="$RUNTIME_ROOT/.backup/$STAMP"
managed_backed_up=0
backup_runtime_file() { # <relpath>  — back up existing managed target before overwrite
  local rel="$1"
  if [ -e "$RUNTIME_ROOT/$rel" ]; then
    mkdir -p "$RT_BACKUP_DIR/$(dirname "$rel")"
    cp -p "$RUNTIME_ROOT/$rel" "$RT_BACKUP_DIR/$rel"
    managed_backed_up=$((managed_backed_up + 1))
  fi
}

# Stage-managed atomic install: write to .staging-<pid> then move.
install_managed_file() { # <src> <relpath>
  local src="$1" rel="$2"
  backup_runtime_file "$rel"
  mkdir -p "$RUNTIME_ROOT/$(dirname "$rel")"
  local stage="$RUNTIME_ROOT/.staging-$$-$(basename "$rel")"
  cp -p "$src" "$stage"
  mv -f "$stage" "$RUNTIME_ROOT/$rel"
}

# bin/ — memory-lifecycle.sh, repo-bootstrap.sh, verify-permission-patterns.sh, state.sh, test suites
BIN_SRC_DIR="$ROOT/scripts"
mkdir -p "$RUNTIME_ROOT/bin"
for s in memory-lifecycle.sh repo-bootstrap.sh verify-permission-patterns.sh state.sh agora.sh \
         test-install.sh test-runtime.sh test-path-resolution.sh test-memory-isolation.sh \
         test-agent-architecture.sh test-memory-system.sh test-repo-bootstrap.sh test-integration.sh test-agora.sh; do
  if [ -f "$BIN_SRC_DIR/$s" ]; then
    install_managed_file "$BIN_SRC_DIR/$s" "bin/$s"
    chmod 755 "$RUNTIME_ROOT/bin/$s"
    echo "    runtime: bin/$s"
  fi
done

# skills/ — 13 skill dirs + SKILLS.md (managed, read-only)
if [ -d "$ROOT/skills" ]; then
  mkdir -p "$RUNTIME_ROOT/skills"
  # SKILLS.md
  if [ -f "$ROOT/skills/SKILLS.md" ]; then
    install_managed_file "$ROOT/skills/SKILLS.md" "skills/SKILLS.md"
  fi
  # each skill dir's SKILL.md
  for d in "$ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -f "$d/SKILL.md" ]; then
      install_managed_file "$d/SKILL.md" "skills/$name/SKILL.md"
      echo "    runtime: skills/$name/SKILL.md"
    fi
  done
fi

# improvements/ — README only if absent; pending/applied/rejected never overwritten
mkdir -p "$RUNTIME_ROOT/improvements/pending" \
         "$RUNTIME_ROOT/improvements/applied" \
         "$RUNTIME_ROOT/improvements/rejected"
if [ -f "$ROOT/improvements/README.md" ] && [ ! -f "$RUNTIME_ROOT/improvements/README.md" ]; then
  cp -p "$ROOT/improvements/README.md" "$RUNTIME_ROOT/improvements/README.md"
  echo "    runtime: improvements/README.md (first install)"
fi

# Runtime backup retention (same KEEP_BACKUPS=5 policy).
if (( managed_backed_up > 0 )); then
  shopt -s nullglob
  rt_backup_dirs=( "$RUNTIME_ROOT"/.backup/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_* )
  shopt -u nullglob
  rt_excess=$(( ${#rt_backup_dirs[@]} - KEEP_BACKUPS ))
  if (( rt_excess > 0 )); then
    for prune_dir in "${rt_backup_dirs[@]:0:rt_excess}"; do
      [ -d "$prune_dir" ] || continue
      rm -rf "$prune_dir"
      echo "    pruned old runtime backup: .backup/$(basename "$prune_dir")"
    done
  fi
fi

# --------------------------------------------------------------------- #
# install-manifest.json (version, date, installed files + sha256)
# --------------------------------------------------------------------- #
echo "==> Writing install-manifest.json"
VERSION="1.0.0"
{
  echo "{"
  echo "  \"version\": \"$VERSION\","
  echo "  \"date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"agents_target\": \"$TARGET\","
  echo "  \"installed\": ["
  first=1
  for src_path in "${AGENT_FILES[@]}"; do
    name="$(basename "$src_path")"
    chk="$(sha256sum "$TARGET/$name" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
    [ "$first" = "0" ] && echo ","
    printf '    { "file": "agents/%s", "target": "%s", "sha256": "%s" }' "$name" "$name" "$chk"
    first=0
  done
  # runtime managed files
  for s in memory-lifecycle.sh repo-bootstrap.sh verify-permission-patterns.sh state.sh agora.sh; do
    rp="bin/$s"
    if [ -f "$RUNTIME_ROOT/$rp" ]; then
      chk="$(sha256sum "$RUNTIME_ROOT/$rp" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
      echo ","
      printf '    { "file": "runtime/%s", "target": "%s", "sha256": "%s" }' "$rp" "$rp" "$chk"
    fi
  done
  echo ""
  echo "  ]"
  echo "}"
} > "$MANIFEST"

# --------------------------------------------------------------------- #
# Idempotent shell-rc export of OPENCODE_DEV_AGENT_TEAM
# --------------------------------------------------------------------- #
RC_FILE=""
[ -f "$HOME/.bashrc" ] && RC_FILE="$HOME/.bashrc"
[ -z "$RC_FILE" ] && [ -f "$HOME/.profile" ] && RC_FILE="$HOME/.profile"
if [ -n "$RC_FILE" ]; then
  if grep -q 'OPENCODE_DEV_AGENT_TEAM' "$RC_FILE"; then
    echo "==> OPENCODE_DEV_AGENT_TEAM already exported in $RC_FILE (no change)."
  else
    printf '\n# dev_agent_team runtime root (added by install.sh)\nexport OPENCODE_DEV_AGENT_TEAM="${OPENCODE_DEV_AGENT_TEAM:-%s}"\n' "$RUNTIME_ROOT" >> "$RC_FILE"
    echo "==> Added OPENCODE_DEV_AGENT_TEAM export to $RC_FILE"
  fi
else
  # No rc file: export via ~/.profile (create if missing) so GUI launches can
  # still pick the var up from a login shell. Guarded/idempotent.
  if [ ! -f "$HOME/.profile" ]; then
    printf '# dev_agent_team runtime root (added by install.sh)\nexport OPENCODE_DEV_AGENT_TEAM="${OPENCODE_DEV_AGENT_TEAM:-%s}"\n' "$RUNTIME_ROOT" > "$HOME/.profile"
    echo "==> Created $HOME/.profile with OPENCODE_DEV_AGENT_TEAM export"
  else
    echo "==> No shell rc (.bashrc/.profile) found to export OPENCODE_DEV_AGENT_TEAM; export it manually if needed."
  fi
fi

# --------------------------------------------------------------------- #
# Install-time self-verification (D8 §5)
# --------------------------------------------------------------------- #
echo "==> Install-time verification"
# Permission gate: re-run verify-permission against transferred bin.
VP_RT="$RUNTIME_ROOT/bin/verify-permission-patterns.sh"
if [ -f "$VP_RT" ]; then
  vprc=0
  bash "$VP_RT" || vprc=$?
  case "$vprc" in
    0|2) echo "    verify-permission-patterns: ok (rc=$vprc)" ;;
    *)   echo "    WARNING: verify-permission-patterns rc=$vprc" >&2 ;;
  esac
fi

# Presence checks on the runtime tree.
presence_ok=1
[ -x "$RUNTIME_ROOT/bin/memory-lifecycle.sh" ] || { echo "    MISSING bin/memory-lifecycle.sh" >&2; presence_ok=0; }
[ -x "$RUNTIME_ROOT/bin/repo-bootstrap.sh" ] || { echo "    MISSING bin/repo-bootstrap.sh" >&2; presence_ok=0; }
[ -d "$RUNTIME_ROOT/skills" ] || { echo "    MISSING skills/" >&2; presence_ok=0; }
[ "$(find "$RUNTIME_ROOT/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)" = "12" ] || { echo "    skills/ has != 12 dirs" >&2; presence_ok=0; }
if [ "$presence_ok" = "1" ]; then
  echo "    runtime presence + permission checks: PASS"
else
  echo "    runtime presence + permission checks: some checks FAILED (see above)" >&2
fi

# Optional: run the new runtime test suites in a throwaway temp HOME via
# --self-test, so install self-proves before the user deletes the repo.
if [ "$SELF_TEST" = "1" ]; then
  SELF_T="$(mktemp -d)"
  SELF_TMP_HOME="$SELF_T/home"
  SELF_SRC="$SELF_T/source"
  mkdir -p "$SELF_TMP_HOME" "$SELF_SRC"
  cp -r "$ROOT/agents" "$SELF_SRC/agents"
  mkdir -p "$SELF_SRC/scripts" "$SELF_SRC/skills" "$SELF_SRC/improvements"
  cp -p "$ROOT"/scripts/*.sh "$SELF_SRC/scripts/" 2>/dev/null || true
  cp -r "$ROOT/skills/." "$SELF_SRC/skills/" 2>/dev/null || true
  cp -r "$ROOT/improvements/." "$SELF_SRC/improvements/" 2>/dev/null || true
  SELF_RT="$SELF_T/runtime"
  SELF_AG="$SELF_T/agents"
  echo "    Running self-test (temp HOME install) ..."
  env -i HOME="$SELF_TMP_HOME" \
      OPENCODE_AGENTS_DIR="$SELF_AG" \
      OPENCODE_DEV_AGENT_TEAM="$SELF_RT" \
      TEAM_ROOT="$SELF_SRC" \
      bash "$RUNTIME_ROOT/bin/test-install.sh" >"$SELF_T/install.log" 2>&1 && self_install=0 || self_install=$?
  env -i HOME="$SELF_TMP_HOME" \
      OPENCODE_AGENTS_DIR="$SELF_AG" \
      OPENCODE_DEV_AGENT_TEAM="$SELF_RT" \
      TEAM_ROOT="$SELF_SRC" \
      bash "$RUNTIME_ROOT/bin/test-memory-isolation.sh" >"$SELF_T/mem.log" 2>&1 && self_mem=0 || self_mem=$?
  if [ "$self_install" = "0" ] && [ "$self_mem" = "0" ]; then
    echo "    self-test: PASS (test-install + test-memory-isolation sub-suites green)"
  else
    echo "    self-test: FAILED (install rc=$self_install, memory rc=$self_mem) — see $SELF_T logs" >&2
  fi
  rm -rf "$SELF_T"
fi

# --------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------- #
echo "==> Installed runtime tree to $RUNTIME_ROOT"
echo "==> Upgrade: re-run ./scripts/install.sh from a newer source"
echo "==> Uninstall: ./scripts/install.sh --uninstall"
echo "==> The source checkout may now be deleted; agents + runtime remain installed."

if command -v opencode >/dev/null 2>&1; then
  echo "==> Reminder: restart opencode, then run: opencode agent list"
else
  echo "==> Note: 'opencode' not found on PATH; skipped restart/verify reminder."
fi

echo "==> Done."
