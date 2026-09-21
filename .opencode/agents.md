# Agent Roster & Routing

This document defines all agents, their capabilities, and routing rules.
The orchestrator uses this to dispatch tasks to the correct specialist.

## Agent Roster

| Agent | Role | Primary Skills | Optional Skills |
|-------|------|----------------|-----------------|
| Orchestrator | Coordinate and dispatch | coordination | — |
| Explorer | Understand systems | repository-analysis, research, arch-overview | browser-automation |
| Detective | Isolate failures | systematic-debugging, failure-analysis | incident-investigation |
| Architect | Decide boundaries | architecture-design | code-review, security-review |
| Builder | Implement changes | tdd, refactoring | code-review |
| Tester | Verify behavior | tdd, test-analysis, verification-loop | failure-analysis |
| Reviewer | Adversarial verification | code-review, security-review | test-analysis, architecture-design |
| Maintainer | Restore standards | refactoring | code-review |
| Toolsmith | Build safeguards | systematic-debugging, impact-analysis, deadcode-detection, session-coordination | adr-management |
| Designer | UI/UX specification | — | research, browser-automation |
| Philosopher | Discover purpose | — | research |
| Writer | Create documentation | — | research |
| Workflow Architect | Model workflows | — | — |
| Breakdowner | Decompose goals | — | — |

## Routing Rules

### By Task Type

```
Bug/failure/regression       → Detective (always, even if "looks simple")
New feature                  → Builder (after design approved)
Code review                  → Reviewer
Architecture decision        → Architect
UI/UX design                 → Designer
Test strategy/coverage       → Tester
Automation/safeguard         → Toolsmith (always, even if "looks small")
Documentation                → Writer
Maintenance/drift            → Maintainer (always, even if "looks trivial")
System understanding         → Explorer
Purpose/meaning              → Philosopher (always for new projects)
Workflow/state model         → Workflow Architect
Large goal (>3 files)        → Breakdowner first
```

### By Phase

```
Discovery:    Explorer → Philosopher → Architect
Design:       Designer → Architect → Workflow Architect
Implementation: Builder → Tester → Reviewer
Maintenance:  Maintainer → Reviewer
```

### Skill Loading

When dispatching an agent, include the skill path:

```bash
# Example dispatch brief
Load skill: ${OPENCODE_DEV_AGENT_TEAM}/skills/systematic-debugging/SKILL.md
Report to: ./AgentsReport/detective/<date>_<task>.md
```

## Agent Capabilities

### Orchestrator
- Routes tasks to correct specialist
- Manages multi-step workflows
- Tracks state across handoffs
- Recalls memory before dispatching
- Verifies artifacts on disk

### Explorer
- Understands system structure
- Maps codebase layout
- Identifies entry points
- Traces dependencies
- Generates architecture overviews

### Detective
- Isolates failures
- Establishes root cause
- Classifies failure types
- Produces evidence-backed reports
- Recommends next actions

### Architect
- Decides boundaries
- Defines ownership
- Specifies interfaces
- Makes long-term structure decisions
- Reviews architectural impact

### Builder
- Implements approved changes
- Follows TDD workflow
- Writes tests first
- Implements to pass tests
- Refactors within scope

### Tester
- Designs test strategy
- Writes test suites
- Analyzes coverage
- Verifies behavior correctness
- Identifies regression risks

### Reviewer
- Independently verifies work
- Checks against approved scope
- Finds adversarial issues
- Produces verdict + findings
- Blocks if scope expanded

### Maintainer
- Restores drifted standards
- Fixes documentation drift
- Synchronizes conventions
- Makes smallest corrective change

### Toolsmith
- Builds mechanical safeguards
- Prevents recurring problems
- Creates automation scripts
- Encodes rules as tools

### Designer
- Specifies UI/UX design
- Defines interaction patterns
- Ensures accessibility
- Creates visual specifications

### Philosopher
- Discovers project purpose
- Clarifies "why" before "how"
- Identifies core problem
- Prevents building wrong thing

### Writer
- Creates technical documentation
- Writes API references
- Produces user guides
- Documents decisions

### Workflow Architect
- Models state/transition systems
- Creates FSMs and DAGs
- Specifies workflow requirements
- Produces executable specs

### Breakdowner
- Decomposes large goals
- Creates task breakdowns
- Tracks dependencies
- Manages .tasks/ trees

## Coordination Patterns

### Sequential Handoff
```
Agent A → Agent B → Agent C
Each agent's output is the next agent's input
```

### Parallel Independent
```
Agent A ──┐
Agent B ──┼→ Integration
Agent C ──┘
No dependencies between A, B, C
```

### Gate Pattern
```
Agent A → Gate (verification) → Agent B
Gate must pass before B starts
```

### Loop Pattern
```
Agent A → Agent B → Gate → (if fail) → Agent A
Until gate passes or max iterations
```
