---
name: coordination
description: Long-context coordination patterns for orchestrator — agent routing, skill dispatch, state tracking, and context handoff
location: skills/coordination/SKILL.md
version: 1.0.0
owner: orchestrator
---

# Coordination Skill

Orchestrator patterns for coordinating agents across long-context sessions with
state preservation, skill dispatch, and context handoff.

## When to use

- Dispatching agents in long sessions (context may compact)
- Tracking multi-step workflows across agent handoffs
- Coordinating parallel independent work tracks
- Resuming interrupted work from session state
- Routing tasks to the correct specialist agent

## Core methodology

### 1. Agent Routing

Route tasks to the correct specialist based on task classification:

| Task Type | Agent | Skill |
|-----------|-------|-------|
| Bug/failure | Detective | systematic-debugging |
| New feature | Builder | tdd |
| Code review | Reviewer | code-review |
| Architecture | Architect | architecture-design |
| UI/UX | Designer | — |
| Testing | Tester | tdd, test-analysis |
| Documentation | Writer | — |
| Automation | Toolsmith | systematic-debugging |
| Maintenance | Maintainer | refactoring |
| Discovery | Explorer | repository-analysis |
| Purpose | Philosopher | research |
| Workflow model | Workflow Architect | — |
| Large goal | Breakdowner | — |

### 2. Skill Dispatch

When dispatching an agent, include the skill path in the brief:

```
Load skill: ${OPENCODE_DEV_AGENT_TEAM}/skills/<skill-name>/SKILL.md
```

### 3. State Tracking

Use `.tasks/<goal>/tasks.json` for per-goal state:
- `state.sh task create <id> --title "..." --goal <goal>`
- `state.sh task assign <id> <agent>`
- `state.sh task status <id> <status>`
- `state.sh task complete <id>`

### 4. Context Handoff

When context is long, persist state in handoff files:
- `AgentsReport/<agent>/<date>_<task>.md`
- Include: objective, evidence, files, changes, verification, next action

### 5. Memory Recall

Before significant work, recall relevant memory:
- `memory-lifecycle.sh recall decisions <keywords>`
- `memory-lifecycle.sh recall lessons <keywords>`
- `memory-lifecycle.sh recall failures <keywords>`

### 6. Local Installation Awareness

When working in a project with `.opencode/`:
- Check for local `.opencode/dev-agent-team/` installation
- If present, prefer local runtime over global
- Set `OPENCODE_DEV_AGENT_TEAM` to local path

## Coordination Checklist

Before dispatching:
1. [ ] Task classified correctly
2. [ ] Agent selected from routing table
3. [ ] Skill path included in brief
4. [ ] Report path specified
5. [ ] Dependencies identified
6. [ ] Memory recalled if relevant

After agent completes:
1. [ ] Verify artifacts exist on disk
2. [ ] Check handoff contains enough info
3. [ ] Update task state
4. [ ] Store memory if durable learning

## Failure Recovery

When an agent fails:
1. Classify failure type (tool/environment/assumption/plan/implementation/test/coordination)
2. Collect evidence
3. Choose a DIFFERENT action (don't retry same action)
4. Update task state with failure record

## Context Economy

- Keep briefs compact (objective, scope, inputs, outputs, report path)
- Don't paste whole documents into briefs — point at them
- Use context packs when multiple agents share background
- Verify claimed artifacts exist on disk before accepting handoffs
