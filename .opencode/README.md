# .opencode/ — AI Coordination Directory

This directory contains AI-specific coordination files for the dev_agent_team system.
It is the central location for all AI-related configuration, state, and documentation.

## Directory Structure

```
.opencode/
├── README.md              # This file — coordination overview
├── agents.md              # Agent roster, capabilities, and routing
├── AGENTS.md              # Global agent definitions (symlink or copy)
├── tests/                 # AI test suites
│   ├── test-all.sh        # Test aggregator
│   ├── test-*.sh          # Individual test suites
│   └── ...
├── tasks/                 # Per-goal task state
│   └── <goal>/
│       ├── tasks.json     # Task state machine
│       └── ...
└── skills/                # Local skill overrides (optional)
    └── <skill-name>/
        └── SKILL.md
```

## Purpose

When a project has `.opencode/` in its root, the dev_agent_team system operates
in **local mode** — all AI coordination happens within the project directory.

### Global vs Local

| Aspect | Global | Local (.opencode/) |
|--------|--------|-------------------|
| Location | `~/.config/opencode/dev-agent-team/` | `./.opencode/dev-agent-team/` |
| Agents | Shared across projects | Project-specific |
| Skills | Shared across projects | Project-specific overrides |
| Tests | Global test suite | Project-specific tests |
| State | Global task state | Project-specific task state |
| Memory | Global memory | Project-specific memory |

### Setup

```bash
# Install locally
./scripts/install.sh --local

# Set environment
export OPENCODE_DEV_AGENT_TEAM="$(pwd)/.opencode/dev-agent-team"

# Or add to .env / .bashrc
echo 'export OPENCODE_DEV_AGENT_TEAM="$(pwd)/.opencode/dev-agent-team"' >> .env
```

## Agent Coordination

### How Agents Find Skills

1. Agent receives dispatch brief with skill path
2. Agent loads skill from `${OPENCODE_DEV_AGENT_TEAM}/skills/<name>/SKILL.md`
3. If not found, falls back to global runtime

### How Orchestrator Routes Tasks

1. Classify task (bug/feature/review/architecture/etc.)
2. Select agent from routing table (see `agents.md`)
3. Include skill path in dispatch brief
4. Specify report path for handoff

### State Tracking

```bash
# Create task
bash scripts/state.sh task create <id> --title "..." --goal <goal>

# Assign to agent
bash scripts/state.sh task assign <id> <agent>

# Update status
bash scripts/state.sh task status <id> in_progress

# Complete
bash scripts/state.sh task complete <id>
```

## Test Suites

All test scripts live in `.opencode/tests/`:

```bash
# Run all tests
bash .opencode/tests/test-all.sh

# Run specific suite
bash .opencode/tests/test-adr.sh
```

## Memory

Project-specific memory lives in `memory/`:

```
memory/
├── MEMORY.md              # Index and conventions
├── decisions/             # Architectural decisions (ADRs)
├── lessons/               # Implementation lessons
├── failures/              # Known failures and root causes
├── architecture/          # Current architectural state
└── sessions/              # Cross-session continuity
```

## Long-Context Coordination

When context is long (>50k tokens):

1. Persist state in `AgentsReport/<agent>/<date>_<task>.md`
2. Include: objective, evidence, files, changes, verification, next action
3. Use `state.sh` for task state (survives context compaction)
4. Recall memory before resuming work

## Quick Reference

| Command | Purpose |
|---------|---------|
| `state.sh task create <id> --title "..." --goal <g>` | Create task |
| `state.sh task assign <id> <agent>` | Assign task |
| `state.sh task status <id> <status>` | Update status |
| `state.sh task complete <id>` | Complete task |
| `memory-lifecycle.sh recall <cat> <query>` | Search memory |
| `memory-lifecycle.sh store <cat> <file>` | Store memory |
| `test-all.sh` | Run all tests |
