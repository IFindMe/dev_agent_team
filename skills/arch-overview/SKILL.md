---
name: arch-overview
description: Generate a structured architecture overview of a repository using filesystem heuristics and git log analysis
version: "1.0"
owner: Toolsmith
prerequisites: bash, git (optional but recommended for hotspots)
---

# Architecture Overview

## When to use this skill

Use when you need a quick, structured overview of a repository's architecture:
- understanding a new codebase
- verifying architectural assumptions against actual repo state
- generating a snapshot for documentation or onboarding
- identifying hotspots and entry points before planning changes
- supporting Architect or Explorer briefs with concrete repo facts

## Core methodology

1. Run `arch-overview.sh` with appropriate flags to generate the overview
2. Parse the output (markdown or JSON) for the relevant sections
3. Use the structured data to inform architectural decisions or documentation

## Sections available

| Section | Flag | What it shows |
|---------|------|---------------|
| File tree | `--section tree` | Directory structure with file counts |
| Languages | `--section languages` | Files detected by extension |
| Entry points | `--section entry-points` | Shebangs, `main()`, `if __name__`, `index.*` |
| Module boundaries | `--section modules` | Top-level dirs with file counts + README snippets |
| Dependencies | `--section dependencies` | Manifest files (package.json, requirements.txt, etc.) |
| Hotspots | `--section hotspots` | Top 10 most-edited files via git log |
| Cross-module deps | `--section cross-deps` | Import/require analysis between top-level dirs |

## Step-by-step procedure

### Quick overview (all sections)

```bash
bash scripts/arch-overview.sh
```

### Focused query

```bash
# Just hotspots
bash scripts/arch-overview.sh --section hotspots

# Just languages with depth limit
bash scripts/arch-overview.sh --section languages

# JSON for programmatic use
bash scripts/arch-overview.sh --format json
```

### Cross-repo comparison

```bash
bash scripts/arch-overview.sh --path /path/to/other/repo --section hotspots
bash scripts/arch-overview.sh --path /path/to/other/repo --section languages
```

### Machine-readable output

```bash
bash scripts/arch-overview.sh --format json | jq '.languages'
bash scripts/arch-overview.sh --format json | jq '.hotspots'
```

## Common pitfalls

- Hotspots require git history — empty repos show no hotspot data
- Language detection uses extension mapping only (no AST analysis)
- Cross-dep detection is grep-based (may miss dynamic imports)
- Tree depth defaults to 3; use `--depth` to adjust
- Module boundaries are top-level directories only (not nested packages)

## Evidence requirements

When using this skill in a brief, reference:
- the generated output (file path or inline)
- which sections were used
- any notable findings (hotspot clusters, missing dependency manifests, etc.)

## Exit criteria

- overview generated successfully (exit 0)
- output covers requested sections
- findings are consistent with manual inspection
