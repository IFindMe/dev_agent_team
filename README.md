# Dev Agent Team

A role-separated engineering team for OpenCode. The repository contains reusable agent definitions plus a small installer and task-state helper.

The design goal is not to maximize the number of agents. It is to route each concern to the smallest suitable specialist, preserve evidence across handoffs, and independently review implementation changes.

## Agents

| Agent | Responsibility |
|---|---|
| `orchestrator` | Primary coordinator; plans and dispatches named specialists |
| `philosopher` | Clarifies purpose, values, success criteria, and non-goals |
| `explorer` | Bounded repository and system investigation |
| `detective` | Root-cause investigation of failures |
| `architect` | Technical boundaries, ownership, interfaces, and scope |
| `workflow-architect` | State, transition, dependency, and recovery models |
| `designer` | UI/UX and accessibility specifications |
| `builder` | Approved product implementation |
| `tester` | Test strategy, test implementation, and behavior verification |
| `reviewer` | Independent review of completed implementation |
| `toolsmith` | Reusable mechanical safeguards and automation |
| `maintainer` | Restoration of established conventions and documentation |
| `writer` | New technical documentation |
| `tracker` | Authoritative task-state management |

## Requirements

- An OpenCode release that supports the V2 agent Markdown frontmatter and ordered `permissions` rules.
- Python 3.10+ for validation and task-state tooling.
- A POSIX-compatible environment (Linux/macOS) for the task-state helper's advisory file locking.
- Bash for the installer.

The agent files are the source definitions. They are not discovered directly from this repository's `agents/` directory; they must be installed into an OpenCode agent directory.

## Install

Project-local installation (recommended):

```sh
git clone https://github.com/IFindMe/dev_agent_team.git
cd dev_agent_team
./install.sh --project /path/to/your/project
```

Global installation:

```sh
./install.sh --global
```

The installer copies agents into `.opencode/agents/` for project installs or `$XDG_CONFIG_HOME/opencode/agents/` (default: `~/.config/opencode/agents/`) for global installs. It also installs the task-state helper beside the selected agent configuration.

Useful commands:

```sh
./install.sh --check
./install.sh --project /path/to/your/project --dry-run
./install.sh --project /path/to/your/project --force
./install.sh --project /path/to/your/project --uninstall
```

The installer refuses to overwrite files it does not own unless `--force` is supplied. Replaced files are backed up. Uninstall removes only files that still match the installer manifest; locally modified files are preserved.

After installation, start OpenCode in the target project and run:

```sh
opencode agent list
```

Select `orchestrator` as the primary agent for the session. No default-agent configuration is written automatically because existing projects may already define one.

## How the team works

The Orchestrator dispatches specialists only when their evidence or expertise is needed. It does not inspect or modify the codebase itself.

Typical failure workflow:

```text
User → Orchestrator → Detective → Builder → Tester → Reviewer
                                ↑                 |
                                └── repair loop ──┘
```

That is an example, not a mandatory pipeline. For a clear, low-risk change, skip discovery and architecture work that is already resolved. For any implementation change, require independent review before acceptance.

### Reports

Each workflow uses one directory:

```text
.opencode/reports/<workflow-id>/
  explorer-agent-T1-investigation.md
  architect-agent-T2-design.md
  builder-agent-T3-implementation.md
  reviewer-agent-T4-review.md
```

The Orchestrator assigns the workflow ID, task ID, report name, and complete report path in each dispatch brief. A specialist may create only that designated report directory when needed to write its report.

### Task state

For multi-task work, Tracker owns:

```text
.tasks/<workflow-id>/
  tasks.json
  events.jsonl
  .lock
```

Use the installed helper from the project root:

```sh
python3 .opencode/scripts/task_state.py --help
```

For a global installation, use:

```sh
python3 "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/scripts/task_state.py" --help
```

Example:

```sh
python3 .opencode/scripts/task_state.py init --workflow-id telemetry --goal "Implement telemetry ingestion"
python3 .opencode/scripts/task_state.py add \
  --workflow-id telemetry --task-id T1 --title "Inspect current ingestion" \
  --objective "Map the current data path" --owner explorer \
  --report-path .opencode/reports/telemetry/explorer-agent-T1-investigation.md \
  --expected-output "Evidence-backed data-flow map" \
  --verification "Cite source files and relevant symbols"
python3 .opencode/scripts/task_state.py set-status \
  --workflow-id telemetry --task-id T1 --status queued
python3 .opencode/scripts/task_state.py show --workflow-id telemetry
```

Task state is authoritative in `tasks.json`; the JSONL file is an audit trail. State transitions and dependency constraints are validated by the helper.

## Model selection

No provider or model is hardcoded. Agents inherit the active session's model unless a model is explicitly configured in their frontmatter or OpenCode configuration. Use `opencode models` to inspect models available in your environment before assigning specialist models. This keeps the package usable with hosted providers and local OpenAI-compatible endpoints.

## Validate the source repository

```sh
python3 scripts/validate.py
python3 -m unittest discover -s tests -v
```

GitHub Actions runs the same checks on pushes and pull requests.

## Security model

Agent permissions are explicitly deny-by-default and role-specific. Read-only agents cannot edit project files. The Orchestrator can launch only the named specialist agents. Shell execution is denied or approval-gated except for narrowly allowlisted read-only Git commands and the Tracker state helper.

These controls are defense in depth, not a security sandbox. OpenCode permissions do not replace OS-level isolation, least-privilege accounts, filesystem permissions, containerization, or human review. See [SECURITY.md](SECURITY.md).

## License

No license has been selected for this repository. Public visibility on GitHub does not itself grant permission to redistribute or create derivative works. The repository owner should choose and add a license before presenting this as an openly licensed package.
