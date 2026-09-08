# Skills System

## Purpose

Skills provide reusable, specialized capabilities that agents can load when needed.
Instead of duplicating instruction sets across every agent, skills centralize
domain-specific knowledge and procedures.

## Structure

```
skills/
├── SKILLS.md                    # This file — index and loading rules
├── tdd/                         # Test-Driven Development
│   └── SKILL.md
├── systematic-debugging/        # Systematic debugging methodology
│   └── SKILL.md
├── architecture-design/         # Architecture decision process
│   └── SKILL.md
├── code-review/                 # Code review checklist and process
│   └── SKILL.md
├── security-review/             # Security review methodology
│   └── SKILL.md
├── repository-analysis/         # Repository exploration methodology
│   └── SKILL.md
├── failure-analysis/            # Failure investigation methodology
│   └── SKILL.md
├── refactoring/                 # Refactoring principles and patterns
│   └── SKILL.md
├── test-analysis/               # Test coverage and quality analysis
│   └── SKILL.md
├── incident-investigation/      # Incident response methodology
│   └── SKILL.md
├── browser-automation/          # Browser automation patterns
│   └── SKILL.md
└── research/                    # Research methodology
    └── SKILL.md
```

## Loading Rules

1. The Orchestrator identifies which skill(s) a task requires
2. The Orchestrator includes the skill path in the agent's dispatch brief
3. The agent reads the skill file before beginning work
4. The agent applies the skill's procedures to the task

## Skill Format

Each skill file contains:

```markdown
---
name: <skill-name>
description: <what this skill provides>
version: "1.0"
owner: <which agent maintains this skill>
prerequisites: <what must be true before using this skill>
---

# <Skill Name>

## When to use this skill
## Core methodology
## Step-by-step procedure
## Common pitfalls
## Evidence requirements
## Exit criteria
```

## Agent-Skill Mapping

| Agent | Primary Skills | Optional Skills |
|-------|---------------|-----------------|
| Explorer | repository-analysis, research | browser-automation |
| Detective | systematic-debugging, failure-analysis | incident-investigation |
| Architect | architecture-design | code-review, security-review |
| Builder | tdd, refactoring | code-review |
| Tester | tdd, test-analysis | failure-analysis |
| Reviewer | code-review, security-review | test-analysis, architecture-design |
| Maintainer | refactoring | code-review |
| Toolsmith | systematic-debugging | — |
| Designer | — | research, browser-automation |
| Philosopher | — | research |
| Writer | — | research |
| Workflow Architect | — | — |

## Customization

Skills can be extended per-project by adding project-specific sections.
When a skill is customized, add a note at the top:

```markdown
> Customized for <project> on YYYY-MM-DD. Original skill preserved in
> the agent team repository.
```
