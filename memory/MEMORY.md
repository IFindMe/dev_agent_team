# Project Memory

This directory contains the persistent memory of the project, organized by category.

## Structure

```
memory/
├── decisions/          # Architectural and technical decisions (ADR-style)
├── lessons/            # Implementation lessons, patterns discovered
├── failures/           # Known failures, root causes, and how they were resolved
├── architecture/       # Current architectural decisions, component maps
├── sessions/           # Session state for cross-session continuity
└── MEMORY.md           # This file — index and conventions
```

## Memory Lifecycle

### Before significant work (RECALL)
1. Search `memory/decisions/` for relevant architectural decisions
2. Search `memory/lessons/` for similar past situations
3. Search `memory/failures/` for related incidents or recurring problems
4. Check `memory/sessions/` for unfinished work from previous sessions

### During work (OBSERVE)
1. Record meaningful decisions as they are made
2. Track important discoveries
3. Note failures and their root causes
4. Identify assumptions that were validated or disproven

### After work (LEARN + STORE)
1. Extract reusable knowledge from what was learned
2. Classify: is this a decision, lesson, or failure record?
3. Store in the appropriate memory location
4. Update `MEMORY.md` index if new categories emerge

## Conventions

- Memory entries are **selective and useful** — not every tool call or conversation
- Each entry has: date, author (agent), context, content, relevance
- Entries use deterministic markdown format (human-readable, version-controllable)
- Entries reference source files with `file:line` when applicable
- Trivial discoveries do not belong in memory
- Entries that become stale are corrected by the owning agent, not deleted

## Memory vs Task State

| What | Where |
|------|-------|
| Architectural decisions | `memory/decisions/` |
| Implementation lessons | `memory/lessons/` |
| Known failures | `memory/failures/` |
| Current architecture | `memory/architecture/` |
| Session state | `memory/sessions/` |
| Task reports | `AgentsReport/<agent>/` (ephemeral) |
| Repository knowledge | `.opencode/skills/` (per-repo) |
| Scratch / temp | `/tmp/opencode` |
