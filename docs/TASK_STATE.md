# Task-state contract

## Ownership and locations

Tracker is the only agent authorized to mutate workflow task state. Task descriptions and state are separate from specialist reports and durable project decisions.

For workflow ID `<workflow-id>`:

```text
.tasks/<workflow-id>/
├── tasks.json
├── events.jsonl
└── .lock
.opencode/reports/<workflow-id>/
└── <agent>-agent-<task-id>-<report-name>.md
```

- `tasks.json` is the authoritative current state.
- `events.jsonl` is an append-only audit trail.
- `.lock` serializes concurrent writers using an advisory POSIX file lock (Linux/macOS).
- `tasks.json` is written using a temporary file, fsync, and atomic rename.
- Runtime state and reports are ignored by Git by default. Archive them separately when a project needs long-term records.

Use the installed helper from the project root:

```sh
python3 .opencode/scripts/task_state.py init --workflow-id <id> --goal "<goal>"
python3 .opencode/scripts/task_state.py add --workflow-id <id> --task-id T1 \
  --title "<title>" --objective "<objective>" --owner explorer \
  --report-path .opencode/reports/<id>/explorer-agent-T1-investigation.md \
  --expected-output "<deliverable>" --verification "<acceptance check>"
python3 .opencode/scripts/task_state.py set-status --workflow-id <id> --task-id T1 --status queued
python3 .opencode/scripts/task_state.py validate --workflow-id <id>
```

For global installations, the helper is at `$XDG_CONFIG_HOME/opencode/scripts/task_state.py` (default `~/.config/opencode/scripts/task_state.py`).

## Task record

Every task is self-contained and records:

- stable ID and title
- objective and owner
- explicit in-scope and out-of-scope boundaries
- inputs and expected output
- verification criteria
- dependencies
- the exact single report path
- current status and timestamps

Do not store credentials or secrets in task descriptions, event reasons, or reports.

## States

| State | Meaning |
|---|---|
| `planned` | Defined but not ready for execution |
| `queued` | Ready to be dispatched |
| `running` | Specialist is executing |
| `waiting_agent` | Waiting for a specialist handoff |
| `waiting_tool` | Waiting for a tool or external operation |
| `waiting_verification` | Implementation is complete and verification is pending |
| `blocked` | Cannot proceed until a named blocker is resolved |
| `repairing` | A defect was found and an approved repair is underway |
| `completed` | Required work and verification are complete |
| `failed` | Work failed and will not continue without replanning |
| `cancelled` | Work was explicitly cancelled |

Allowed transitions:

```text
planned → queued | cancelled
queued → running | blocked | cancelled
running → waiting_agent | waiting_tool | waiting_verification
          | blocked | repairing | completed | failed | cancelled
waiting_agent → running | blocked | failed | cancelled
waiting_tool → running | blocked | failed | cancelled
waiting_verification → completed | repairing | blocked | failed
blocked → queued | running | cancelled
repairing → running | waiting_verification | blocked | failed | cancelled
failed → queued | cancelled
completed → (terminal)
cancelled → (terminal)
```

A transition to `blocked`, `failed`, `cancelled`, or `completed` requires a reason. For `completed`, the reason must identify the verification evidence; do not use completion as a synonym for "the agent stopped."

A task with dependencies cannot enter `queued` or `running` until every dependency is `completed`. Dependencies must refer to existing task IDs and cannot contain cycles.

## Concurrency and recovery

Only Tracker writes workflow state. The helper targets POSIX systems (Linux/macOS), acquires `.lock` before reading or mutating state, atomically replaces `tasks.json`, and then appends the corresponding event. If the process crashes between the state replacement and event append, the state file remains authoritative and the event log may be missing the final event. Run `validate` to detect malformed records; do not reconstruct task status from event prose.

If a helper command fails, preserve the existing state, capture the error, and report the workflow as blocked rather than editing JSON around the validator.

## Report contract

The Orchestrator assigns one path per dispatch:

```text
.opencode/reports/<workflow-id>/<agent>-agent-<task-id>-<report-name>.md
```

The specialist may create this exact directory when needed to write the assigned report. It must not choose another directory or create additional report files.
