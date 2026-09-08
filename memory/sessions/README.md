# Session State

Cross-session continuity for long-running work.

## Purpose

When OpenCode restarts, the system needs to know:
- What was being worked on
- What was completed
- What was interrupted
- What the next step should be

## Format

```markdown
# Session-NNNN: <task summary>

Started: YYYY-MM-DD HH:MM
Last updated: YYYY-MM-DD HH:MM
Status: active | interrupted | completed

## Task

<what was being done>

## Completed

<what was finished>

## In Progress

<what was interrupted>

## Next Steps

<what should happen next>

## Context

<relevant facts needed to resume — decisions, evidence, file paths>
```

## Lifecycle

- Session records are created at the start of significant work
- Updated incrementally as work progresses
- Marked `completed` when the task is done
- Left as `interrupted` if the session ends mid-task
- Old sessions (>7 days, completed) can be archived or removed

## Recovery

On session restart, the Orchestrator:
1. Checks `memory/sessions/` for `active` or `interrupted` sessions
2. Reads the context from the most recent relevant session
3. Decides whether to resume or start fresh
4. Creates a new session record if starting fresh
