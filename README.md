# dev_agent_team

A distributable package of 13 opencode agent definitions plus a one-command
installer, so the same agent team can be set up identically on any machine.

## What this is

This repository packages a complete multi-agent team for
[opencode](https://opencode.ai) — 13 role-specialized agents that work as one
system:

`architect`, `builder`, `designer`, `detective`, `explorer`, `maintainer`,
`orchestrator` (primary), `philosopher`, `reviewer`, `tester`, `toolsmith`,
`workflow-architect`, `writer`.

The agent definitions live in `agents/` and are copied verbatim into your
opencode config directory by `scripts/install.sh`. The installer is idempotent:
re-running it is safe, and it backs up any pre-existing files it would
overwrite into a timestamped folder under `<target>/.backup/`, keeping only
the 5 most recent backup folders.

### Repository Intelligence Bootstrap

The team includes a **Repository Intelligence Bootstrap** system: when the
Orchestrator starts work on an unfamiliar repository, it automatically analyzes
the repository and generates a local `.opencode/` knowledge layer
(context, architecture, build/test, conventions, deployment). Every agent then
reads this pre-analyzed context instead of re-discovering repository fundamentals.

The bootstrap is idempotent, language-agnostic, and preserves manually enriched
content. See [docs/REPOSITORY_INTELLIGENCE.md](docs/REPOSITORY_INTELLIGENCE.md)
for the full architecture.

### Adaptive, Evidence-Driven Orchestration

The team is architected as a **decision engine**: the Orchestrator understands
the task, estimates complexity, loads repository intelligence, chooses the next
best action from an explicit action catalog, verifies outcomes independently,
re-plans when evidence changes, and stops when sufficiently verified. Every
agent produces structured evidence-state records and knows when to stop and
escalate.

See [docs/AGENT_ARCHITECTURE.md](docs/AGENT_ARCHITECTURE.md) for the full
architecture, and [docs/EVALUATION_SCENARIOS.md](docs/EVALUATION_SCENARIOS.md)
for the 12 runtime evaluation scenarios used to measure the team's own quality.

## Repository layout

```text
dev_agent_team/
├── README.md                          # this file
├── .gitignore
├── agents/                            # the 13 agent definitions (*.md)
├── scripts/
│   ├── install.sh                     # one-command installer
│   ├── repo-bootstrap.sh              # repository intelligence bootstrap tool
│   ├── test-repo-bootstrap.sh         # test suite for the bootstrap
│   ├── test-agent-architecture.sh     # structural tests for the agent architecture
│   └── verify-permission-patterns.sh  # permission engine verifier
└── docs/
    ├── PROMPT_INSTALL.md              # paste-ready prompt for installing from inside opencode
    ├── REPOSITORY_INTELLIGENCE.md     # bootstrap architecture documentation
    ├── AGENT_ARCHITECTURE.md          # adaptive/evidence-driven architecture documentation
    └── EVALUATION_SCENARIOS.md        # runtime evaluation scenarios for the team itself
```

## Quickstart

```bash
git clone git@gitea.skink-platy.ts.net:admin/dev_agent_team.git
cd dev_agent_team
./scripts/install.sh
```

To install somewhere other than the default location:

```bash
OPENCODE_AGENTS_DIR=/path/to/opencode/agents ./scripts/install.sh
```

## Repository bootstrap

After installing the agents, the bootstrap tool is available at
`scripts/repo-bootstrap.sh`. From inside any target repository:

```bash
# Check freshness (exit 0=fresh, 1=stale/missing)
repo-bootstrap.sh status

# Create/update .opencode/ knowledge layer
repo-bootstrap.sh bootstrap

# Force regenerate generated files
repo-bootstrap.sh refresh
```

Run `bash scripts/test-repo-bootstrap.sh` to verify bootstrap behavior
(11 tests covering all 10 acceptance criteria).

Run `bash scripts/test-agent-architecture.sh` to verify the agent architecture
contains the required adaptive/evidence-driven elements
(16 structural tests).

## Manual install alternative

Prefer to do it yourself? A plain copy achieves the same result:

```bash
mkdir -p ~/.config/opencode/agents
cp -p agents/*.md ~/.config/opencode/agents/
```

(You will not get the automatic backup of pre-existing files that
`scripts/install.sh` provides.)

## Prompt-based install

Already inside an opencode session? Copy a ready-made prompt that instructs
the primary agent to clone this repo, run the installer, and verify the
result: see [docs/PROMPT_INSTALL.md](docs/PROMPT_INSTALL.md).

## Requirements

- [opencode](https://opencode.ai) installed (needed to actually use the agents)
- `bash` and coreutils (`cp`, `mkdir`, `date`, `sha256sum` or `cksum`)
- SSH access to the gitea host for cloning (or an HTTPS remote, if mirrored)

## Verification

After installing:

1. Restart any running opencode sessions so they pick up the new agents.
2. Run:

   ```bash
   opencode agent list
   ```

3. You should see exactly **13 agents**: architect, builder, designer,
   detective, explorer, maintainer, orchestrator, philosopher, reviewer,
   tester, toolsmith, workflow-architect, writer.
