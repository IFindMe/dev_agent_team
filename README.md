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

The team is architected as a **decision engine**: the Orchestrator recalls
project memory, understands the task, estimates complexity, loads repository
intelligence, chooses the next best action from an explicit action catalog,
verifies outcomes independently, re-plans when evidence changes, stores durable
findings, and stops when sufficiently verified. Every agent produces structured
evidence-state records and knows when to stop and escalate.

See [docs/AGENT_ARCHITECTURE.md](docs/AGENT_ARCHITECTURE.md) for the full
architecture, and [docs/EVALUATION_SCENARIOS.md](docs/EVALUATION_SCENARIOS.md)
for the 12 runtime evaluation scenarios used to measure the team's own quality.

### Project Memory & Skills

The team includes **cross-session project memory** (`memory/`) for persisting
decisions, lessons, failures, architecture notes, and session state. A
lifecycle script (`scripts/memory-lifecycle.sh`) provides deterministic recall,
store, list, search, and cleanup operations.

The team also includes **12 reusable skills** (`skills/`) — specialized
methodologies for TDD, debugging, architecture, code review, security review,
and more. Agents load relevant skills when dispatched.

Both systems require **human approval** for changes to core agent behavior
(`improvements/`).

## Repository layout

```text
dev_agent_team/
├── README.md                          # this file
├── .gitignore
├── agents/                            # the 13 agent definitions (*.md)
├── memory/                            # cross-session project memory
│   ├── MEMORY.md                      # index with lifecycle rules
│   ├── decisions/                     # architectural/technical choices
│   ├── lessons/                       # reusable knowledge
│   ├── failures/                      # root causes + prevention
│   ├── architecture/                  # system structure documentation
│   └── sessions/                      # work-in-progress state
├── skills/                            # 12 reusable specialized methodologies
│   ├── SKILLS.md                      # index with loading rules
│   ├── tdd/SKILL.md                   # Test-Driven Development
│   ├── systematic-debugging/SKILL.md  # debugging methodology
│   ├── architecture-design/SKILL.md   # architecture decisions
│   ├── code-review/SKILL.md           # code review process
│   ├── security-review/SKILL.md       # security review
│   ├── repository-analysis/SKILL.md   # repo exploration
│   ├── failure-analysis/SKILL.md      # failure investigation
│   ├── refactoring/SKILL.md           # safe code restructuring
│   ├── test-analysis/SKILL.md         # test quality assessment
│   ├── incident-investigation/SKILL.md # production incidents
│   ├── browser-automation/SKILL.md    # web interaction patterns
│   └── research/SKILL.md              # information gathering
├── improvements/                      # proposal-based improvement system
│   ├── README.md                      # proposal format and lifecycle
│   ├── pending/                       # proposals awaiting approval
│   ├── applied/                       # approved and implemented
│   └── rejected/                      # not approved
├── scripts/
│   ├── install.sh                     # one-command installer
│   ├── repo-bootstrap.sh              # repository intelligence bootstrap tool
│   ├── memory-lifecycle.sh            # memory CRUD operations
│   ├── test-all.sh                    # single entry point that runs all test suites
│   ├── test-repo-bootstrap.sh         # test suite for the bootstrap
│   ├── test-agent-architecture.sh     # structural tests for the agent architecture
│   ├── test-memory-system.sh          # structural tests for memory/skills/improvements
│   ├── test-integration.sh            # end-to-end memory/skills/lifecycle integration tests
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

Run all test suites with a single command (aggregates the four suites below):

```bash
bash scripts/test-all.sh
```

51 individual checks across 4 suites (16 architecture + 12 memory + 11 bootstrap
+ 12 integration). Any suite failing makes the overall exit code non-zero.

Individual suites:

- `test-agent-architecture.sh` — architecture contains the required
  adaptive/evidence-driven elements (16 structural tests).
- `test-memory-system.sh` — memory, skills, and improvement systems are
  structurally sound (12 tests).
- `test-repo-bootstrap.sh` — bootstrap behavior and idempotency
  (11 tests covering all 10 acceptance criteria).
- `test-integration.sh` — end-to-end memory/skills/improvements integration
  (12 tests).

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
