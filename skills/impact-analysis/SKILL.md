---
name: impact-analysis
description: Map code changes to affected decisions, lessons, tasks, skills, and agents for blast-radius analysis
version: "1.0"
owner: Toolsmith
prerequisites: bash, git, jq, grep, a git repository with memory/tasks/skills/agents
---

# Impact Analysis

## When to use this skill

- Before rework on files that may affect existing decisions, tasks, or lessons
- When planning a change and need to know what else depends on the changed files
- When prioritizing which changes need careful handling vs safe-to-merge

## Core methodology

CHANGED FILES -> PATTERN MATCH -> RISK CLASSIFY -> REPORT

The tool greps for references to changed file basenames (and stems without extension)
across the markdown memory system, task state, skills, and agent definitions.
Each match is classified by risk level based on context.

## Risk levels

| Level | Meaning |
|-------|---------|
| critical | Breaks an approved gate or active task assignment |
| high | Directly referenced by an active task or in-progress work |
| medium | Mentions the changed file or pattern with path reference |
| low | Tangential reference (same directory, related topic) |

## Step-by-step procedure

### 1. Run the impact tool

```bash
bash scripts/impact.sh                       # diff HEAD-1
bash scripts/impact.sh --files "src/foo.sh"  # explicit files
bash scripts/impact.sh --commit abc123       # against commit
bash scripts/impact.sh --format json         # JSON output
bash scripts/impact.sh --section decisions   # one section only
bash scripts/impact.sh --verbose             # line numbers
```

### 2. Interpret the report

Each section lists affected artifacts with risk levels.
The summary line gives totals: critical, high, medium, low, total.

### 3. Act on findings

- critical or high: review before merging; may break active work
- medium: note for awareness; may need updating after the change
- low: tangential; usually safe to ignore

## Common pitfalls

- Pattern too broad: many unrelated matches when basenames are short (e.g. "a.sh")
- Missing references: the tool greps content, not AST; it finds text mentions, not structural dependencies
- False positives: basename matches in unrelated contexts

## Exit criteria

- Report produced with risk-classified findings
- Summary counts match individual risk levels
