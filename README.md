# dev_agent_team

A distributable package of 12 opencode agent definitions plus a one-command
installer, so the same agent team can be set up identically on any machine.

## What this is

This repository packages a complete multi-agent team for
[opencode](https://opencode.ai) — 12 role-specialized agents that work as one
system:

`architect`, `builder`, `designer`, `detective`, `explorer`, `maintainer`,
`orchestrator` (primary), `philosopher`, `reviewer`, `tester`, `toolsmith`,
`writer`.

The agent definitions live in `agents/` and are copied verbatim into your
opencode config directory by `scripts/install.sh`. The installer is idempotent:
re-running it is safe, and it backs up any pre-existing files it would
overwrite into a timestamped folder under `<target>/.backup/`.

## Repository layout

```text
dev_agent_team/
├── README.md              # this file
├── .gitignore
├── agents/                # the 12 agent definitions (*.md)
├── scripts/
│   └── install.sh         # one-command installer
└── docs/
    └── PROMPT_INSTALL.md  # paste-ready prompt for installing from inside opencode
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
- `bash` and coreutils (`cp`, `mkdir`, `date`) — present on any Linux/macOS system
- SSH access to the gitea host for cloning (or an HTTPS remote, if mirrored)

## Verification

After installing:

1. Restart any running opencode sessions so they pick up the new agents.
2. Run:

   ```bash
   opencode agent list
   ```

3. You should see exactly **12 agents**: architect, builder, designer,
   detective, explorer, maintainer, orchestrator, philosopher, reviewer,
   tester, toolsmith, writer.
