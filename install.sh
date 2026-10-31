#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh --project DIR [--force] [--dry-run]
  ./install.sh --global [--force] [--dry-run]
  ./install.sh --project DIR --uninstall
  ./install.sh --global --uninstall
  ./install.sh --check

Options:
  --project DIR  Install into DIR/.opencode/
  --global       Install into ${XDG_CONFIG_HOME:-~/.config}/opencode/
  --force        Back up and replace conflicting managed/unmanaged files
  --dry-run      Show planned changes without writing
  --uninstall    Remove only unmodified files recorded in the installer manifest
  --check        Validate source agent definitions; no installation
  -h, --help     Show this help
USAGE
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MODE=""
PROJECT_DIR=""
FORCE=0
DRY_RUN=0
UNINSTALL=0
CHECK=0

while (($#)); do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "error: --project requires a directory" >&2; exit 2; }
      MODE="project"; PROJECT_DIR="$2"; shift 2 ;;
    --global) MODE="global"; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ((CHECK)); then
  exec python3 "$SCRIPT_DIR/scripts/validate.py" --root "$SCRIPT_DIR"
fi

[[ -n "$MODE" ]] || { echo "error: choose --project DIR or --global" >&2; exit 2; }
if [[ "$MODE" == "project" ]]; then
  [[ -d "$PROJECT_DIR" ]] || { echo "error: project directory does not exist: $PROJECT_DIR" >&2; exit 2; }
  PROJECT_DIR="$(cd -- "$PROJECT_DIR" && pwd -P)"
  PREFIX="$PROJECT_DIR/.opencode"
  AGENT_DIR="$PREFIX/agents"
  SCRIPT_DIR_TARGET="$PREFIX/scripts"
  MANIFEST="$PREFIX/dev_agent_team.manifest"
  BACKUP_ROOT="$PREFIX/backups/dev_agent_team"
else
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  PREFIX="$CONFIG_HOME/opencode"
  AGENT_DIR="$PREFIX/agents"
  SCRIPT_DIR_TARGET="$PREFIX/scripts"
  MANIFEST="$PREFIX/dev_agent_team.manifest"
  BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dev_agent_team/backups"
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "error: sha256sum or shasum is required" >&2
    return 1
  fi
}

manifest_digest() {
  local wanted="$1"
  [[ -f "$MANIFEST" ]] || return 0
  awk -F '\t' -v wanted="$wanted" '$1 == wanted { print $2; exit }' "$MANIFEST"
}

FILES=("agents/"*.md "scripts/task_state.py")

if ((UNINSTALL)); then
  [[ -f "$MANIFEST" ]] || { echo "No installer manifest found at $MANIFEST"; exit 0; }
  while IFS=$'\t' read -r rel digest; do
    [[ -n "${rel:-}" && -n "${digest:-}" ]] || continue
    case "$rel" in
      agents/*) dest="$AGENT_DIR/${rel#agents/}" ;;
      scripts/*) dest="$SCRIPT_DIR_TARGET/${rel#scripts/}" ;;
      *) echo "skip unsafe manifest path: $rel" >&2; continue ;;
    esac
    if [[ -f "$dest" ]] && [[ "$(hash_file "$dest")" == "$digest" ]]; then
      echo "remove $dest"
      if ((!DRY_RUN)); then rm -f -- "$dest"; fi
    elif [[ -e "$dest" ]]; then
      echo "preserve modified/non-file path: $dest" >&2
    fi
  done < "$MANIFEST"
  if ((!DRY_RUN)); then rm -f -- "$MANIFEST"; fi
  exit 0
fi

python3 "$SCRIPT_DIR/scripts/validate.py" --root "$SCRIPT_DIR"

declare -a CONFLICTS=()
declare -a TYPE_CONFLICTS=()
for src in "${FILES[@]}"; do
  if [[ "$src" == agents/* ]]; then
    dest="$AGENT_DIR/${src#agents/}"
  else
    dest="$SCRIPT_DIR_TARGET/${src#scripts/}"
  fi
  [[ -e "$dest" ]] || continue
  if [[ ! -f "$dest" ]]; then
    TYPE_CONFLICTS+=("$dest")
    continue
  fi
  current="$(hash_file "$dest")"
  source_hash="$(hash_file "$SCRIPT_DIR/$src")"
  [[ "$current" == "$source_hash" ]] && continue
  previous="$(manifest_digest "$src")"
  [[ -n "$previous" && "$current" == "$previous" ]] && continue
  CONFLICTS+=("$dest")
done

if ((${#TYPE_CONFLICTS[@]} > 0)); then
  printf 'Refusing to replace non-file paths:\n' >&2
  printf '  %s\n' "${TYPE_CONFLICTS[@]}" >&2
  exit 1
fi
if ((${#CONFLICTS[@]} > 0)) && ((!FORCE)); then
  printf 'Refusing to overwrite unmanaged/modified files:\n' >&2
  printf '  %s\n' "${CONFLICTS[@]}" >&2
  echo "Use --force to back them up before replacement." >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if ((!DRY_RUN)); then
  new_manifest="$(mktemp)"
  trap 'rm -f -- "$new_manifest"' EXIT
else
  new_manifest=""
fi

for src in "${FILES[@]}"; do
  if [[ "$src" == agents/* ]]; then
    dest="$AGENT_DIR/${src#agents/}"
    rel="$src"
  else
    dest="$SCRIPT_DIR_TARGET/${src#scripts/}"
    rel="$src"
  fi
  source_hash="$(hash_file "$SCRIPT_DIR/$src")"
  if [[ -f "$dest" ]] && [[ "$(hash_file "$dest")" == "$source_hash" ]]; then
    echo "unchanged $dest"
  else
    echo "install $dest"
    if ((!DRY_RUN)); then
      mkdir -p "$(dirname -- "$dest")"
      if [[ -e "$dest" ]]; then
        backup="$BACKUP_ROOT/$timestamp/$rel"
        mkdir -p "$(dirname -- "$backup")"
        cp -p -- "$dest" "$backup"
        echo "backup $backup"
      fi
      install -m 0644 -- "$SCRIPT_DIR/$src" "$dest"
      [[ "$src" == scripts/* ]] && chmod 0755 "$dest"
    fi
  fi
  if ((!DRY_RUN)); then
    printf '%s\t%s\n' "$rel" "$source_hash" >> "$new_manifest"
  fi
done

if ((!DRY_RUN)); then
  mkdir -p "$(dirname -- "$MANIFEST")"
  mv -- "$new_manifest" "$MANIFEST"
  trap - EXIT
  echo "Installation complete."
else
  echo "Dry run complete; no files changed."
fi
