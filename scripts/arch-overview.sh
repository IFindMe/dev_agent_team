#!/usr/bin/env bash
# arch-overview.sh — Generate a structured architecture overview of a repository.
#
# Adapted from CBM's get_architecture concept: languages, packages, entry points,
# hotspots, module boundaries — implemented in bash/markdown (no tree-sitter).
#
# Usage:
#   arch-overview.sh                       # full overview, current repo
#   arch-overview.sh --path /some/repo     # full overview, specific path
#   arch-overview.sh --format json         # JSON output
#   arch-overview.sh --section tree        # only file tree
#   arch-overview.sh --section languages   # only languages
#   arch-overview.sh --section entry-points # only entry points
#   arch-overview.sh --section dependencies # only dependencies
#   arch-overview.sh --section hotspots    # only hotspots
#   arch-overview.sh --section modules     # only module boundaries
#   arch-overview.sh --section cross-deps  # only cross-module dependencies
#   arch-overview.sh --depth 2             # limit tree depth
#   arch-overview.sh -h|--help             # help
#
# Exit status: 0 success, 1 error (missing repo, bad args).
#
# Output: markdown (default) or JSON (--format json).

set -euo pipefail

# --------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------- #
REPO_PATH="."
FORMAT="markdown"
SECTION=""
TREE_DEPTH=3
TIMESTAMP="$(date '+%Y-%m-%d %H:%M')"

# --------------------------------------------------------------------- #
# Language extension map
# --------------------------------------------------------------------- #
declare -A LANG_MAP=(
  [sh]="bash" [bash]="bash"
  [py]="python" [python]="python"
  [js]="javascript" [jsx]="javascript"
  [ts]="typescript" [tsx]="typescript"
  [go]="go"
  [rs]="rust"
  [java]="java"
  [rb]="ruby"
  [pl]="perl"
  [c]="c" [h]="header"
  [cpp]="cpp" [cc]="cpp" [cxx]="cpp" [hpp]="cpp"
  [md]="markdown"
  [json]="json"
  [yaml]="yaml" [yml]="yaml"
  [toml]="toml"
  [sql]="sql"
  [html]="html" [htm]="html"
  [css]="css"
  [Dockerfile]="Dockerfile" [dockerfile]="Dockerfile"
  [Makefile]="makefile" [makefile]="makefile"
  [sh]="bash"
)

# --------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------- #
usage() {
  sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \?//'
  exit 0
}

# --------------------------------------------------------------------- #
# Arg parsing
# --------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help) usage ;;
    --path)  REPO_PATH="${2:?--path requires a value}"; shift 2 ;;
    --format) FORMAT="${2:?--format requires a value}"; shift 2 ;;
    --section) SECTION="${2:?--section requires a value}"; shift 2 ;;
    --depth)  TREE_DEPTH="${2:?--depth requires a value}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Validate
if [[ ! -d "$REPO_PATH/.git" && ! -d "$REPO_PATH" ]]; then
  echo "ERROR: $REPO_PATH is not a valid directory" >&2
  exit 1
fi

REPO_NAME="$(basename "$(cd "$REPO_PATH" && pwd)")"

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

# Count files by extension (excluding .git)
count_by_ext() {
  local root="$1"
  find "$root" -not -path '*/.git/*' -type f -name '*.*' 2>/dev/null \
    | sed -n 's/.*\.//p' \
    | tr '[:upper:]' '[:lower:]' \
    | sort | uniq -c | sort -rn
}

# Language detection: extension -> language name
lang_from_ext() {
  local ext="$1"
  echo "${LANG_MAP[$ext]:-unknown}"
}

# File tree with counts per directory (find + awk)
file_tree() {
  local root="$1" depth="$2"
  # Use find with maxdepth, strip root prefix, group by dir
  find "$root" -maxdepth "$depth" -not -path '*/.git/*' -not -path '*/.git' \
    | sed "s|^$root/||;s|^$root$|.|" \
    | awk -F/ '{dir=""; for(i=1;i<NF;i++){dir=dir"/"$i}; print dir}' \
    | sort | uniq -c | sort -rn \
    | awk '{
        # Reconstruct path
        path=""
        for(i=2;i<=NF;i++){
          if(path=="") path=$i; else path=path"/"$i
        }
        # Indent based on depth
        depth=0; n=split(path,a,"/"); depth=n-1
        indent=""
        for(i=0;i<depth;i++) indent=indent"  "
        printf "%s%s/ (%d files)\n", indent, a[n], $1
      }'
}

# Detect entry points
find_entry_points() {
  local root="$1"
  # Shell scripts with shebang
  echo "#!/bin/bash or #!/bin/sh shebangs:"
  find "$root" -not -path '*/.git/*' -type f \( -name '*.sh' -o -name '*.bash' \) \
    -exec grep -l '^#!.*sh' {} \; 2>/dev/null | head -20 || true
  echo ""

  # Python __main__
  echo 'if __name__ == "__main__":'
  grep -rl 'if __name__.*==.*"__main__"' "$root" --include='*.py' 2>/dev/null | grep -v '.git/' | head -20 || true
  echo ""

  # main() functions in Go/Rust/Java
  echo "main() / fn main():"
  grep -rl 'func main()' "$root" --include='*.go' 2>/dev/null | grep -v '.git/' | head -10 || true
  grep -rl 'fn main()' "$root" --include='*.rs' 2>/dev/null | grep -v '.git/' | head -10 || true
  grep -rl 'public static void main' "$root" --include='*.java' 2>/dev/null | grep -v '.git/' | head -10 || true
  echo ""

  # Web entry points (index.*)
  echo "index.* entry points:"
  find "$root" -not -path '*/.git/*' -type f \( -name 'index.html' -o -name 'index.js' -o -name 'index.ts' -o -name 'index.jsx' -o -name 'index.tsx' \) 2>/dev/null | head -20 || true
}

# Detect dependency files
find_dependencies() {
  local root="$1"
  local found=0
  for manifest in package.json requirements.txt go.mod go.sum Cargo.toml Gemfile pom.xml build.gradle setup.py pyproject.toml Pipfile composer.json; do
    if [[ -f "$root/$manifest" ]]; then
      echo "- $manifest"
      found=1
    fi
  done
  if [[ $found -eq 0 ]]; then
    echo "(no dependency manifests found)"
  fi
}

# Hotspots: top 10 most-edited files via git log
find_hotspots() {
  local root="$1"
  if [[ ! -d "$root/.git" ]]; then
    echo "(not a git repo — no hotspot data)"
    return
  fi
  (cd "$root" && git log --format=format: --name-only 2>/dev/null \
    | grep -v '^$' \
    | sort | uniq -c | sort -rn \
    | head -10)
}

# Module boundaries: top-level directories with descriptions
find_modules() {
  local root="$1"
  for dir in "$root"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    # Skip .git, node_modules, __pycache__, etc.
    [[ "$name" == ".git" || "$name" == "node_modules" || "$name" == "__pycache__" || "$name" == ".venv" ]] && continue
    local count
    count="$(find "$dir" -type f -not -path '*/.git/*' 2>/dev/null | wc -l)"
    # Try to read a README for description
    local desc=""
    if [[ -f "$dir/README.md" ]]; then
      desc="$(head -5 "$dir/README.md" | grep -v '^#' | grep -v '^$' | head -1)"
    fi
    if [[ -n "$desc" ]]; then
      echo "- **${name}/** (${count} files) — ${desc}"
    else
      echo "- **${name}/** (${count} files) — no description"
    fi
  done
}

# Cross-module dependencies: grep for import/require patterns between dirs
find_cross_deps() {
  local root="$1"
  # Look for require/import across top-level module dirs
  local modules=()
  for dir in "$root"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    [[ "$name" == ".git" || "$name" == "node_modules" || "$name" == "__pycache__" || "$name" == ".venv" ]] && continue
    modules+=("$name")
  done

  if [[ ${#modules[@]} -lt 2 ]]; then
    echo "(fewer than 2 modules — no cross-deps to analyze)"
    return
  fi

  local any_found=0
  for mod in "${modules[@]}"; do
    local mod_dir="$root/$mod"
    # Check JS/TS require/import from sibling dirs
    for sibling in "${modules[@]}"; do
      [[ "$sibling" == "$mod" ]] && continue
      local hits
      hits="$(grep -rl "from ['\"]\\./$sibling\\|require(['\"]\\./$sibling\\|from ['\"]$sibling\\b" "$mod_dir" --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' --include='*.go' --include='*.py' 2>/dev/null | head -5 || true)"
      if [[ -n "$hits" ]]; then
        echo "- $mod → $sibling"
        any_found=1
      fi
    done
  done
  if [[ $any_found -eq 0 ]]; then
    echo "(no cross-module imports detected)"
  fi
}

# --------------------------------------------------------------------- #
# Section builders
# --------------------------------------------------------------------- #

section_tree() {
  echo "## File Tree"
  echo ""
  file_tree "$REPO_PATH" "$TREE_DEPTH" | head -60
  echo ""
}

section_languages() {
  echo "## Languages"
  echo ""
  echo "| Count | Extension | Language |"
  echo "|-------|-----------|----------|"
  count_by_ext "$REPO_PATH" | while read -r count ext; do
    local lang
    lang="$(lang_from_ext "$ext")"
    printf "| %d | .%s | %s |\n" "$count" "$ext" "$lang"
  done
  echo ""
}

section_entry_points() {
  echo "## Entry Points"
  echo ""
  find_entry_points "$REPO_PATH"
  echo ""
}

section_modules() {
  echo "## Module Boundaries"
  echo ""
  find_modules "$REPO_PATH"
  echo ""
}

section_dependencies() {
  echo "## Dependencies"
  echo ""
  find_dependencies "$REPO_PATH"
  echo ""
}

section_hotspots() {
  echo "## Hotspots"
  echo ""
  echo "Top 10 most-edited files (by git log commit count):"
  echo ""
  find_hotspots "$REPO_PATH" | while read -r line; do
    echo "- $line"
  done
  echo ""
}

section_cross_deps() {
  echo "## Cross-Module Dependencies"
  echo ""
  find_cross_deps "$REPO_PATH"
  echo ""
}

# --------------------------------------------------------------------- #
# JSON output
# --------------------------------------------------------------------- #

json_languages() {
  echo '"languages": ['
  local first=1
  count_by_ext "$REPO_PATH" | while read -r count ext; do
    local lang
    lang="$(lang_from_ext "$ext")"
    [[ $first -eq 0 ]] && echo ","
    printf '    {"ext":"%s","count":%d,"language":"%s"}' "$ext" "$count" "$lang"
    first=0
  done
  echo ""
  echo "  ],"
}

json_hotspots() {
  echo '"hotspots": ['
  local first=1
  find_hotspots "$REPO_PATH" | while read -r line; do
    local count file
    count="$(echo "$line" | awk '{print $1}')"
    file="$(echo "$line" | awk '{print $2}')"
    [[ $first -eq 0 ]] && echo ","
    printf '    {"file":"%s","count":%d}' "$file" "$count"
    first=0
  done
  echo ""
  echo "  ],"
}

json_entry_points() {
  echo '"entry_points": ['
  local first=1
  find "$REPO_PATH" -not -path '*/.git/*' -type f \( -name '*.sh' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name 'index.*' \) 2>/dev/null | while read -r f; do
    local rel="${f#$REPO_PATH/}"
    [[ $first -eq 0 ]] && echo ","
    printf '    {"file":"%s"}' "$rel"
    first=0
  done
  echo ""
  echo "  ]"
}

json_output() {
  echo "{"
  echo "  \"repo\": \"$REPO_NAME\","
  echo "  \"generated\": \"$TIMESTAMP\","
  json_languages
  json_hotspots
  json_entry_points
  echo "}"
}

# --------------------------------------------------------------------- #
# Main: output
# --------------------------------------------------------------------- #

if [[ "$FORMAT" == "json" ]]; then
  json_output
  exit 0
fi

# Markdown output
if [[ -n "$SECTION" ]]; then
  case "$SECTION" in
    tree)        section_tree ;;
    languages)   section_languages ;;
    entry-points) section_entry_points ;;
    modules)     section_modules ;;
    dependencies) section_dependencies ;;
    hotspots)    section_hotspots ;;
    cross-deps)  section_cross_deps ;;
    *) echo "Unknown section: $SECTION (valid: tree, languages, entry-points, modules, dependencies, hotspots, cross-deps)" >&2; exit 2 ;;
  esac
  exit 0
fi

# Full overview
echo "# Architecture Overview: $REPO_NAME"
echo "Generated: $TIMESTAMP"
echo ""
section_tree
section_languages
section_entry_points
section_modules
section_dependencies
section_hotspots
section_cross_deps
