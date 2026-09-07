#!/usr/bin/env bash
set -euo pipefail

# repo-bootstrap.sh — Repository Intelligence Bootstrap for the dev_agent_team
#
# Generates/maintains a repository-specific `.opencode/` knowledge layer:
#   .opencode/AGENTS.md                      repository intelligence entry point
#   .opencode/.bootstrap-meta                staleness metadata (key=value, no JSON parser needed)
#   .opencode/skills/<name>/SKILL.md         repository-specific skills (opencode skill format)
# plus a root AGENTS.md pointer (opencode auto-loads root AGENTS.md from the project root).
#
# The tool is GENERIC: it never hardcodes any repository-specific assumption. It
# only scaffolds structure and records mechanically detectable signals (top-level
# layout, build/deploy manifest presence). Semantic enrichment is done by agents
# (Orchestrator/Explorer/Architect/Builder/Tester/...) after bootstrap runs.
#
# Usage:
#   repo-bootstrap.sh status    → print freshness verdict. exit 0=fresh, 1=stale/missing, 2=error
#   repo-bootstrap.sh bootstrap → create/refresh generated intelligence (idempotent)
#   repo-bootstrap.sh refresh   → force-regenerate GENERATED files (same as bootstrap --force)
#
# Idempotency / preservation rules (binding):
#   * A generated file carries a marker: first line `<!-- GENERATED-SCAFFOLD dev_agent_team ... -->`
#     (AGENTS.md) or `generated-by` metadata (SKILL.md frontmatter). The tool ONLY
#     rewrites files it generated.
#   * Files WITHOUT the marker are treated as MANUAL — never touched, never removed.
#     Agents that substantially enrich a generated file should strip its marker to
#     freeze it as manual.
#   * `bootstrap` rewrites a generated file only when it is missing or the staleness
#     fingerprint changed. A second run in an unchanged repo is a no-op (idempotent).
#   * Existing `.opencode/AGENTS.md`/skills that are manual are left alone and reported.

VERSION=1.0
MARKER_COMMENT="<!-- GENERATED-SCAFFOLD dev_agent_team repo-bootstrap v${VERSION} — treat as generated; strip this line to freeze manually -->"

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# --- helpers ---------------------------------------------------------------

reporoot() {
  # Prefer git worktree root; fall back to cwd (script is safe when run anywhere inside).
  if command -v git >/dev/null 2>&1; then
    local root
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      printf '%s' "$root"
      return 0
    fi
  fi
  pwd -P
}

sha256_of() { # sha256_of <string>
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  elif command -v cksum >/dev/null 2>&1; then
    printf '%s' "$1" | cksum | awk '{print $1}'
  else
    printf '%s' "${#1}"
  fi
}

top_level_snapshot() { # top_level_snapshot <root> -> newline list, sorted
  find "$1" -maxdepth 1 -mindepth 1 \( -name .git -o -name node_modules -o -name target -o -name build -o -name dist \) -prune -o -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | LC_ALL=C sort
}

# detect_manifest <root> <name...> : 0 if any of the files exist at root
detect_manifest() {
  local root="$1"; shift
  local f
  for f in "$@"; do
    [ -f "$root/$f" ] && return 0
  done
  return 1
}

# detect_any_dir <root> <name...> : 0 if any of the dirs exist at root
detect_any_dir() {
  local root="$1"; shift
  local d
  for d in "$@"; do
    [ -d "$root/$d" ] && return 0
  done
  return 1
}

# has_workflow_files <root>
has_workflow_files() {
  [ -d "$1/.github/workflows" ] && ls "$1/.github/workflows"/* >/dev/null 2>&1
}

# --- signals ---------------------------------------------------------------

detect_signals() { # detect_signals <root> -> sets BUILD_IND / DEPLOY_IND / CODE_IND
  local root="$1"
  BUILD_IND=0; DEPLOY_IND=0; CODE_IND=0

  if detect_manifest "$root" \
      package.json pnpm-lock.yaml yarn.lock package-lock.json \
      pyproject.toml requirements.txt setup.py \
      Cargo.toml go.mod pom.xml build.gradle build.gradle.kts \
      Makefile CMakeLists.txt Gemfile composer.json mix.exs \
      pubspec.yaml meson.build WORKSPACE BUILD dune-project \
      *.csproj *.sln; then
    BUILD_IND=1
  fi

  if detect_manifest "$root" \
      Dockerfile docker-compose.yml docker-compose.yaml \
      .gitlab-ci.yml Jenkinsfile cloudbuild.yaml heroku.yml \
      fly.toml vercel.json netlify.toml \
      *.tf *.tfvars || has_workflow_files "$root" || detect_any_dir "$root" k8s helm terraform systemd; then
    DEPLOY_IND=1
  fi

  if [ "$BUILD_IND" -eq 1 ] || detect_any_dir "$root" src lib packages cmd internal app core; then
    CODE_IND=1
  fi
}

# --- meta ------------------------------------------------------------------

META_FILE=".bootstrap-meta"
META_KEYS="schema tool version generated_at git_head manifest_fingerprint top_level_fingerprint signals"

read_meta_value() { # read_meta_value <file> <key>
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  sed -n "s/^${key}=//p" "$file" | head -n1
}

# --- fingerprint -----------------------------------------------------------

current_fingerprint() { # current_fingerprint <root> -> sets MANIFEST_FP / TOPLEVEL_FP / GIT_HEAD / SIGNAL_TXT
  local root="$1"
  GIT_HEAD=""
  if command -v git >/dev/null 2>&1; then
    GIT_HEAD="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
  fi

  local manifest_lines="" f
  for f in package.json pnpm-lock.yaml yarn.lock package-lock.json pyproject.toml requirements.txt setup.py Cargo.toml go.mod pom.xml build.gradle build.gradle.kts Makefile CMakeLists.txt Gemfile composer.json mix.exs pubspec.yaml meson.build WORKSPACE BUILD dune-project Dockerfile docker-compose.yml docker-compose.yaml .gitlab-ci.yml Jenkinsfile cloudbuild.yaml heroku.yml fly.toml vercel.json netlify.toml; do
    if [ -f "$root/$f" ]; then
      manifest_lines+="$(printf '%s' "$f:$(sha256_of "$(cat "$root/$f")")"; printf '\n')"
    fi
  done
  MANIFEST_FP="$(sha256_of "$manifest_lines")"
  TOPLEVEL_FP="$(sha256_of "$(top_level_snapshot "$root")")"

  SIGNAL_TXT="build=$BUILD_IND deploy=$DEPLOY_IND code=$CODE_IND"
}

# --- verdict ---------------------------------------------------------------

verdict() { # verdict <root> -> sets VERDICT=fresh|stale|missing|error ; sets META_OUT
  local root="$1"
  local dir="$root/.opencode"
  VERDICT="error"; META_OUT=""
  [ -d "$root" ] || return 2

  if [ ! -d "$dir" ]; then
    VERDICT="missing"; return 0
  fi
  if [ ! -f "$dir/$META_FILE" ]; then
    VERDICT="stale"; return 0
  fi

  local schema tool_version meta_fp mt_fp signals
  schema="$(read_meta_value "$dir/$META_FILE" schema)"
  tool_version="$(read_meta_value "$dir/$META_FILE" version)"
  meta_fp="$(read_meta_value "$dir/$META_FILE" manifest_fingerprint)"
  mt_fp="$(read_meta_value "$dir/$META_FILE" top_level_fingerprint)"
  signals="$(read_meta_value "$dir/$META_FILE" signals)"

  detect_signals "$root"
  current_fingerprint "$root"

  if [ "$schema" != "1" ] || [ "$tool_version" != "$VERSION" ] \
     || [ "$meta_fp" != "$MANIFEST_FP" ] || [ "$mt_fp" != "$TOPLEVEL_FP" ] \
     || [ "$signals" != "$SIGNAL_TXT" ]; then
    VERDICT="stale"; return 0
  fi
  VERDICT="fresh"; return 0
}

# --- generation ------------------------------------------------------------

write_if_owned() { # write_if_owned <path> <content> <force> ; sets CREATED/UPDATED/SKIPPED counters
  local path="$1" content="$2" force="$3"
  if [ ! -e "$path" ]; then
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
    CREATED=$((CREATED + 1))
  elif grep -qF "GENERATED-SCAFFOLD dev_agent_team" "$path" || grep -qF "generated-by: dev_agent_team-repo-bootstrap" "$path"; then
    if [ "$force" = "1" ] || [ "$VERDICT" = "stale" ] || [ "$VERDICT" = "missing" ]; then
      printf '%s' "$content" > "$path"
      UPDATED=$((UPDATED + 1))
    else
      SKIPPED=$((SKIPPED + 1))   # fresh and generated → leave as-is (idempotent)
    fi
  else
    MANUAL=$((MANUAL + 1))        # manual content — never touch
  fi
}

root_agents_md() { # root_agents_md <root>
  printf '%s\n' \
"$MARKER_COMMENT" \
"# Repository Intelligence" \
"" \
"Read \`.opencode/AGENTS.md\` for repository-specific context before starting work." \
"Deeper knowledge lives in \`.opencode/skills/\` (repo-context, architecture, build-and-test, conventions, deployment)." \
"" \
"Treat repository intelligence as context, not absolute truth: verify against the actual repository when they disagree." \
""
}

repo_agents_md() { # repo_agents_md <root>
  local rname; rname="$(basename "$1")"
  local bt="" arch="" dep="" conv="# Conventions"$'\n\n# Repository coding, naming, structure, and workflow conventions are maintained in \`.opencode/skills/conventions/SKILL.md\`.\n'
  [ "$BUILD_IND" -eq 1 ] && bt="# Build & Test"$'\n\n# Build/test/lint/validation commands live in \`.opencode/skills/build-and-test/SKILL.md\`.\n'
  [ "$CODE_IND" -eq 1 ] && arch="# Architecture"$'\n\n# Components, relationships, boundaries, and architectural rules live in \`.opencode/skills/architecture/SKILL.md\`.\n'
  [ "$DEPLOY_IND" -eq 1 ] && dep="# Deployment"$'\n\n# Deployment and runtime information lives in \`.opencode/skills/deployment/SKILL.md\`.\n'

  printf '%s\n' \
"$MARKER_COMMENT" \
"# AGENTS.md — Repository Intelligence for \`${rname}\`" \
"" \
"## What this repository is" \
"" \
"- (fill in: purpose, for whom, why it exists; verified by Philosopher/Explorer)" \
"" \
"## How it is structured" \
"" \
"- (fill in: top-level layout and module roles; see \`.opencode/skills/repo-context/SKILL.md\`)" \
"" \
"## Build & test" \
"" \
"$bt" \
"## Conventions" \
"" \
"$conv" \
"## Architecture constraints" \
"" \
"$arch" \
"## Deployment / runtime" \
"" \
"$dep" \
"## Rules for agents (binding)" \
"" \
"- Consult \`.opencode/\` before making architectural or implementation decisions." \
"- Treat this knowledge as context, not absolute truth; verify against the source of truth." \
"- Owned skills: Explorer→repo-context, Architect→architecture, Builder/Tester→build-and-test, Maintainer→cleanup/consistency, Reviewer→validation." \
"- Never fill \`.opencode/\` with task-specific noise; add only durable knowledge." \
"" \
"## Bootstrap metadata" \
"" \
"- Generated by dev_agent_team repo-bootstrap v${VERSION} on $(date -u +%Y-%m-%dT%H:%M:%SZ)." \
""
}

skill_meta() { printf '%s\n' "---" "name: $1" "description: $2" "metadata:" "  generated-by: dev_agent_team-repo-bootstrap" "  bootstrap-version: \"$VERSION\"" "---" ""; }

skill_repo_context() {
  skill_meta repo-context \
    "High-level orientation for a repository: purpose, structure, modules, dependencies, and entry points. Use when entering an unfamiliar repository or before architectural and implementation work."
  printf '%s\n' \
"# Repo Context" \
"" \
"> Generated scaffold by dev_agent_team repo-bootstrap v${VERSION}. OWNER: Explorer (verify/enrich). Treat as context — verify against the repository." \
"" \
"## Purpose" \
"- (What does this repository do? For whom? Why?)" \
"" \
"## Structure" \
"- (Top-level directories and their roles)" \
"" \
"## Important modules / entry points" \
"- (Files/dirs that matter most for common work)" \
"" \
"## Dependencies (bootstrap-detected — verify)" \
"- (manifest files and package manager)" \
"" \
"## Runtime requirements" \
"- (verify)" \
"" \
"## Generated vs handwritten files" \
"- (verify)" \
"" \
"## Dangerous areas / fragile components" \
"- (verify)" \
"" \
"## Known technical decisions" \
"- (verify/add reference to ADRs)" \
""
}

skill_architecture() {
  skill_meta architecture \
    "Repository architecture: components, relationships, boundaries, and architectural rules. Use when making architectural decisions or understanding system design."
  printf '%s\n' \
"# Architecture" \
"" \
"> Generated scaffold by dev_agent_team repo-bootstrap v${VERSION}. OWNER: Architect (verify/enrich). Treat as context — verify against the repository." \
"" \
"## Components & modules" \
"- (list and their relationships)" \
"" \
"## Boundaries & ownership" \
"- (layering, module boundaries, responsibilities)" \
"" \
"## Architectural rules & constraints" \
"- (patterns that must be followed)" \
"" \
"## Integration points" \
"- (external systems, APIs, data flows)" \
"" \
"## Known architectural decisions" \
"- (ADR summaries/links)" \
""
}

skill_build_test() {
  skill_meta build-and-test \
    "How to build, test, lint, type-check, and validate a repository. Use before modifying code or when running or verifying project commands."
  printf '%s\n' \
"# Build & Test" \
"" \
"> Generated scaffold by dev_agent_team repo-bootstrap v${VERSION}. OWNERS: Builder + Tester (verify/enrich). Treat as context — verify against the repository." \
"" \
"## Framework / toolchain (bootstrap-detected — verify)" \
"- (manifest files seen during bootstrap; confirm actual toolchain)" \
"" \
"## Build commands" \
"- (list exact commands and order)" \
"" \
"## Test commands" \
"- (list exact commands; note the fast subset for quick checks)" \
"" \
"## Lint / type-check / static analysis" \
"- (list exact commands)" \
"" \
"## Validation order" \
"- (which commands, in which order, before declaring work done)" \
"" \
"## Known build/test gotchas" \
"- (verify/add)" \
""
}

skill_conventions() {
  skill_meta conventions \
    "Repository-specific coding, naming, structure, and workflow conventions. Use when writing code or documentation in this repository."
  printf '%s\n' \
"# Conventions" \
"" \
"> Generated scaffold by dev_agent_team repo-bootstrap v${VERSION}. OWNER: Maintainer (cleanup/consistency); every agent follows conventions. Treat as context — verify against the repository." \
"" \
"## Language / style" \
"- (fill)" \
"" \
"## Naming" \
"- (fill)" \
"" \
"## Structure / layout" \
"- (fill)" \
"" \
"## Workflow (branching, commits, review)" \
"- (fill)" \
"" \
"## Constraints / gotchas" \
"- (fill)" \
""
}

skill_deployment() {
  skill_meta deployment \
    "Deployment and runtime information for a repository, including environments, packaging, and operations. Use when deploying, operating, or debugging runtime behavior."
  printf '%s\n' \
"# Deployment" \
"" \
"> Generated scaffold by dev_agent_team repo-bootstrap v${VERSION}. Treat as context — verify against the repository." \
"" \
"## Deployment targets / environments (bootstrap-detected — verify)" \
"- (indicators: Dockerfile, compose, workflows, IaC files — confirm actual setup)" \
"" \
"## Build / packaging for deploy" \
"- (fill)" \
"" \
"## Runtime requirements" \
"- (fill)" \
"" \
"## Operations / rollout / rollback" \
"- (fill)" \
"" \
"## Monitoring / logs / troubleshooting" \
"- (fill)" \
""
}

do_write_skills() { # do_write_skills <root> <force>
  local root="$1" force="$2" skills="$root/.opencode/skills"

  write_if_owned "$skills/repo-context/SKILL.md" "$(skill_repo_context)" "$force"
  write_if_owned "$skills/conventions/SKILL.md" "$(skill_conventions)" "$force"

  if [ "$CODE_IND" -eq 1 ]; then
    write_if_owned "$skills/architecture/SKILL.md" "$(skill_architecture)" "$force"
  fi
  if [ "$BUILD_IND" -eq 1 ]; then
    write_if_owned "$skills/build-and-test/SKILL.md" "$(skill_build_test)" "$force"
  fi
  if [ "$DEPLOY_IND" -eq 1 ]; then
    write_if_owned "$skills/deployment/SKILL.md" "$(skill_deployment)" "$force"
  fi
}

write_meta() { # write_meta <root>
  local root="$1"
  mkdir -p "$root/.opencode"
  current_fingerprint "$root"
  local new_meta
  new_meta="$(printf '%s\n' \
"schema=1" \
"tool=dev_agent_team-repo-bootstrap" \
"version=$VERSION" \
"generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
"git_head=$GIT_HEAD" \
"manifest_fingerprint=$MANIFEST_FP" \
"top_level_fingerprint=$TOPLEVEL_FP" \
"signals=$SIGNAL_TXT")"
  # Idempotent: skip rewrite if content is identical (preserves timestamp).
  local existing=""
  [ -f "$root/.opencode/$META_FILE" ] && existing="$(cat "$root/.opencode/$META_FILE")"
  if [ "$existing" = "$new_meta" ]; then
    return 0
  fi
  printf '%s\n' "$new_meta" > "$root/.opencode/$META_FILE"
}

# --- commands --------------------------------------------------------------

cmd_status() {
  local root="$1"
  detect_signals "$root"
  verdict "$root"
  case "$VERDICT" in
    fresh)   echo "REPO_BOOTSTRAP_STATUS: fresh   # .opencode up to date (root: $root)";              return 0 ;;
    stale)   echo "REPO_BOOTSTRAP_STATUS: stale   # signals changed or metadata outdated (root: $root)"; return 1 ;;
    missing) echo "REPO_BOOTSTRAP_STATUS: missing # no .opencode intelligence (root: $root)";            return 1 ;;
    *)       echo "REPO_BOOTSTRAP_STATUS: error   # cannot evaluate (root: $root)" >&2;                  return 2 ;;
  esac
}

cmd_bootstrap() {
  local root="$1" force="$2"
  CREATED=0; UPDATED=0; SKIPPED=0; MANUAL=0

  detect_signals "$root"
  verdict "$root"
  [ "$VERDICT" = "error" ] && { echo "ERROR: cannot evaluate repository root: $root" >&2; return 2; }

  echo "==> Repository Intelligence bootstrap (root: $root)"
  echo "==> Signals: build=$BUILD_IND deploy=$DEPLOY_IND code=$CODE_IND"
  echo "==> State before: $VERDICT"

  # Root AGENTS.md pointer: only when absent or generated-owned (never clobber manual).
  write_if_owned "$root/AGENTS.md" "$(root_agents_md "$root")" "$force"

  # .opencode/AGENTS.md + skills.
  write_if_owned "$root/.opencode/AGENTS.md" "$(repo_agents_md "$root")" "$force"
  do_write_skills "$root" "$force"

  # Meta last, so it reflects what was just produced.
  write_meta "$root"

  echo "==> created=$CREATED updated=$UPDATED skipped-fresh=$SKIPPED manual-preserved=$MANUAL"
  if [ "$MANUAL" -gt 0 ]; then
    echo "==> NOTE: $MANUAL file(s) treated as manual content and preserved untouched."
  fi
  echo "==> Next: agents should READ .opencode/AGENTS.md and relevant skills, verify facts against the repository, and enrich owned files (stripping the generated marker when freezing them as manual)."
  return 0
}

# --- main -------------------------------------------------------------------

[ $# -ge 1 ] || usage
CMD="$1"; shift || true

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)  ROOT="$2"; shift 2 ;;
    *)       break ;;
  esac
done
[ -z "$ROOT" ] && ROOT="$(reporoot)"
case "$CMD" in
  status)    cmd_status "$ROOT" ;;
  bootstrap) cmd_bootstrap "$ROOT" 0 ;;
  refresh)   cmd_bootstrap "$ROOT" 1 ;;
  -h|--help) usage ;;
  *)         echo "ERROR: unknown command: $CMD" >&2; usage ;;
esac