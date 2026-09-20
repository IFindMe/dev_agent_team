---
name: deadcode-detection
description: Find orphaned code, unused symbols, and stale references using grep-based pattern matching
version: "1.0"
owner: toolsmith
prerequisites: bash, grep, find, stat
---

# Dead Code Detection

## When to use this skill

Use this skill when you need to:
- Find shell functions with zero callers
- Identify Python functions that are never imported or called
- Detect skills that are never referenced in agents/ or other skills
- Find memory entries that reference files that no longer exist
- Identify stale code that hasn't been modified in N days

## Core methodology

The dead code detection system uses grep-based pattern matching (no AST parsing) to find orphaned code and unused symbols. It adapts the CBM concept: functions with zero callers, excluding entry points.

### Detection strategies

1. **Shell functions**: Find function definitions (`funcname()` or `function funcname`) and check if they're referenced elsewhere
2. **Python functions**: Find function definitions (`def funcname`) and check if they're imported or called
3. **Unused skills**: Find skills in `skills/` that are never referenced in `agents/` or other skills
4. **Orphaned memory**: Find memory entries that reference files that no longer exist

### Severity levels

- **HIGH**: Function defined but never called, file not modified in 30+ days
- **MED**: Function only called by itself, or skill only referenced by itself
- **LOW**: Symbol mentioned but never used as actual code

## Step-by-step procedure

1. **Run the detection tool**:
   ```bash
   bash scripts/deadcode.sh [OPTIONS]
   ```

2. **Options**:
   - `--path <path>`: Scan specific path (default: current repo)
   - `--type <type>`: Filter by type: shell, python, skills, memory, all (default: all)
   - `--format <fmt>`: Output format: text, json (default: text)
   - `--stale-days <n>`: Days threshold for staleness (default: 30)
   - `--exclude <pattern>`: Exclude files matching pattern (repeatable)

3. **Analyze results**:
   - Review HIGH severity candidates first (most likely to be dead code)
   - Check MED severity candidates for self-referencing functions
   - Review LOW severity candidates for mentions that could be cleaned up

4. **Verify findings**:
   - Manually verify that flagged functions are truly unused
   - Check if entry points (main, usage, help, etc.) were correctly excluded
   - Verify that skill references are accurate

5. **Take action**:
   - Remove or archive truly dead code
   - Update documentation for unused skills
   - Fix orphaned memory references

## Common pitfalls

- **False positives**: Some functions may be called dynamically or via aliases
- **Entry points**: The tool excludes common entry points (main, usage, help, etc.)
- **Self-referencing**: Functions that only call themselves are flagged as MED
- **Stale code**: Code that hasn't been modified recently may be dead, but verify before removing

## Evidence requirements

- The tool provides file paths and line numbers for all findings
- Severity levels help prioritize which findings to investigate first
- JSON output can be used for automated processing

## Exit criteria

- All HIGH severity candidates have been reviewed
- MED severity candidates have been verified
- LOW severity candidates have been documented
- Dead code has been removed or archived
- Documentation has been updated
