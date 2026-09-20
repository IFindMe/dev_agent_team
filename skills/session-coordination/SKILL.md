---
name: session-coordination
description: Multi-agent session coordination — register sessions, lock files, detect conflicts, manage leases via scripts/sessions.sh
version: "1.0"
owner: Toolsmith
prerequisites: bash, jq, scripts/sessions.sh
---

# Session Coordination

## When to use this skill

- When multiple agents will work on the same goal concurrently
- Before editing files that other agents may also touch
- To prevent two agents from silently modifying the same file
- To clean up abandoned sessions from agents that crashed or timed out

## Core methodology

```text
REGISTER → LOCK FILES → WORK → HEARTBEAT → UNLOCK → UNREGISTER
```

Every agent that touches the repository should register before starting
work, lock the files it intends to modify, refresh its heartbeat during
long work, unlock files when done, and unregister when finished.

## Step-by-step procedure

### 1. Register before starting work

```bash
scripts/sessions.sh register <agent-name> --task <task-id> --goal <goal-name>
```

This creates a session record in `.tasks/<goal>/sessions.json` with a
timestamp and heartbeat. The agent is now visible to conflict detection.

### 2. Lock files before editing

```bash
scripts/sessions.sh lock <file-path> --by <agent-name> --goal <goal-name>
```

**Always check the output.** If it says `CONFLICT`, another agent already
holds the lock. Do NOT proceed — resolve the conflict first.

### 3. Refresh heartbeat during long work

```bash
scripts/sessions.sh heartbeat <agent-name> --goal <goal-name>
```

Sessions with no heartbeat for 30+ minutes are considered stale and can
be expired by any agent or by the Orchestrator.

### 4. Detect conflicts before committing

```bash
scripts/sessions.sh conflicts --goal <goal-name>
```

This reports any file locked by two or more agents. Resolve all conflicts
before committing or pushing.

### 5. Unlock files when done editing

```bash
scripts/sessions.sh unlock <file-path> --by <agent-name>
```

### 6. Unregister when work is complete

```bash
scripts/sessions.sh unregister <agent-name> --goal <goal-name>
```

This removes the session and any locks held by the agent.

### 7. Clean up stale sessions

```bash
scripts/sessions.sh expire --stale-minutes 30
```

Removes sessions whose heartbeat is older than the threshold. Also
removes locks held by expired agents.

## Common pitfalls

- **Forgetting to register** — the agent becomes invisible to conflict
  detection; other agents may silently clash.
- **Skipping heartbeat** — long-running work may be expired as stale.
- **Not checking lock output** — a CONFLICT result means stop, not retry.
- **Forgetting to unregister** — stale session record persists until
  manually expired.

## Evidence requirements

- Every session register/unregister must succeed (exit 0).
- Every lock must be checked for CONFLICT before proceeding.
- Heartbeats must be refreshed at least every 25 minutes for long work.

## Exit criteria

- Agent registered, files locked, work done, files unlocked, agent
  unregistered — full lifecycle complete.
- No unresolved conflicts at the end of the session.
- Stale sessions cleaned up periodically.
