# Operations Reference — Orchestrator Lifecycle & Environment

**For:** the Orchestrator (and any specialist performing a setup or post-work lifecycle action that fires OFF the mainline decision loop).
**Read when:** the orchestrator brief points here, or you are doing one of: environment/setup verification, conflict resolution, learning/memory storage, improvement proposals, scope escalation.
**Location:** `docs/OPERATIONS_REFERENCE.md` — the single lifecycle/operations reference for orchestrator actions that fire off the mainline loop. Bodies extracted from `agents/orchestrator.md` during the 2026-09-12 semantic-compression refactor; stewarded by Maintainer thereafter.

Contents: Environment and Setup · Conflict Resolution · Learning and Memory Storage · Improvement Proposals · Scope Expansion Protocol.

---

## 1. Environment and Setup

(origin: orchestrator "Agent Availability in This Environment")

This is a custom opencode setup. Agent definitions live in
`~/.config/opencode/agents/` (global, loaded at startup); a staging copy may
exist in `<repo>/opencode_helper/` — when present, keep both in sync after
every edit.

Roster — all fourteen team agents are dedicated definitions:

- `orchestrator` — `mode: primary` (user-invoked coordination layer)
- `explorer`, `builder`, `breakdowner`, `detective`, `philosopher`, `designer`, `tester`,
  `toolsmith`, `maintainer`, `writer`, `architect`, `workflow-architect`,
  `reviewer` — `mode: subagent` (dedicated, Task-dispatchable specialists)

Config is loaded once at startup and is not hot-reloaded. After editing agent
files, restart opencode, then re-verify the roster with `opencode agent list`
before relying on dispatchability.

Global runtime: always resolve via `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"`. Runtime-owned artifacts live under `bin/` (scripts), `skills/` (12 skills), `improvements/`. Project-scoped artifacts (`memory/`, `.opencode/`, `./AgentsReport/`) stay relative to this project.

---

## 2. Conflict Resolution

(origin: orchestrator "Conflict Resolution")

When specialist outputs disagree:

1. Preserve both claims.
2. Identify exactly what conflicts.
3. Prefer primary evidence over inference.
4. Route the unresolved technical question to the specialist whose role owns it.
5. Use Architect when the disagreement is about design, ownership, or boundaries.
6. Do not merge incompatible conclusions into a vague compromise.

Examples:

```text
Explorer vs Detective disagreement about system behavior
→ Detective establishes runtime cause if needed

Detective vs Architect disagreement about intended remedy
→ Architect owns the design decision

Designer vs Architect disagreement about user-facing structure
→ Designer owns user experience; Architect owns technical constraints
→ If conflict persists, Orchestrator coordinates resolution

Builder vs approved scope disagreement
→ Architect resolves scope/design boundary

Maintainer vs Toolsmith disagreement about prevention
→ choose based on whether the problem is systemic restoration or mechanical prevention
```

---

## 3. Learning and Memory Storage (after work)

(origin: orchestrator "Learning and Memory Storage (after work)")

After completing substantial work, the Orchestrator performs a brief learning cycle:

### 1. Review

```text
What happened?    → summarize key events
What was learned? → extract reusable knowledge
What failed?      → identify root causes and prevention
```

### 2. Classify

- Is this a **decision** (architectural or technical choice)? → `memory/decisions/`
- Is this a **lesson** (reusable knowledge)? → `memory/lessons/`
- Is this a **failure** (root cause + prevention)? → `memory/failures/`
- Is this **session state** (work in progress)? → `memory/sessions/`

### 3. Store

Use `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"/bin/memory-lifecycle.sh store <category> <file>` to persist entries.
Format entries using the templates in each category's `README.md`.

### 4. Update session

For long-running tasks, update the session record with current state so work
survives context compaction. (This is the "Long-horizon persistence" rule's
post-work hook — see orchestrator "Evidence-First State and Handoff Discipline".)

### 5. Identify improvements (optional)

If the work revealed a recurring problem, missing skill, or process inefficiency,
create an improvement proposal in `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"/improvements/pending/`. **Do not modify core
agent behavior without human approval.**

Storage rules (store selectively — not every tool call or conversation belongs in memory; no trivial discoveries; entries evidence-backed; preserve existing memory; never task-specific noise as durable knowledge): canonical location is the Orchestrator's "Memory vs Task State" section in `agents/orchestrator.md`.

---

## 4. Improvement Proposals

(origin: orchestrator "Improvement Proposals")

At the end of substantial work, detect potential improvements. The detection is
evidence-driven and triggered by patterns, not by every task:

### When a proposal is warranted

Write a proposal to `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"/improvements/pending/` when ANY of these fire:

1. **Recurring failure** — you just stored a `failures/` record and it resembles a
   prior failure record. A failure that repeats is a system problem, not a task
   outcome. This is a strong signal to propose a Toolsmith safeguard or a
   regression test.
2. **Missing skill** — a specialist had to improvise a methodology that no
   existing skill covers. Propose adding a skill.
3. **Routing inefficiency** — an agent was dispatched and the task would have been
   cheaper as a direct tool call (or a different agent). Propose a routing rule
   change.
4. **Documentation gap** — several agents independently re-derived the same
   convention that should have been documented. Propose a docs/knowledge fix.
5. **Process friction** — the same multi-step manual sequence recurred in this
   task and would recur again. Propose automation.
6. **New proven pattern** — a specialist discovered a genuinely reusable pattern.
   Propose capturing it as a skill or lesson.

### Detection flow

```text
REVIEW: "What happened?"
LEARN: "What was learned?"
CHECK MEMORY: "Have I seen this before?"   → recall failures/lessons for the class
ANALYZE: "Is this one-time or recurring?"
PROPOSE: "What should change to prevent the class?"
STORE: "Lesson/failure stored in memory?"
APPROVAL: "Does the change touch core behavior?"  → if yes, proposal not edit
```

### Proposal format

```text
improvements/pending/YYYY-MM-DD_<short-id>.md

# Proposal: <title>
## Observed problem
   <what went wrong or what is inefficient>
## Evidence
   <files, commands, outputs, memory records that prove it>
## Root cause
   <why it happens — established, not guessed>
## Proposed change
   <what should change: add skill / improve routing / add guardrail / etc.>
## Scope
   <what is touched, what is explicitly out of scope>
## Risks
   <what could go wrong with the change>
## Verification plan
   <how the change will be validated if approved>
## Approval status
   PENDING (awaiting human review)
```

**Rules:**

- Do NOT silently rewrite agent prompts, skills, or architecture.
- Do NOT modify core behavior without human approval — proposals live in
  `"${OPENCODE_DEV_AGENT_TEAM:-$HOME/.config/opencode/dev-agent-team}"/improvements/pending/` until a human reviews them.
- Present proposals to the user at natural stopping points (end of a task, before
  committing, at a review gate) — do not bury them.
- Proposals are decisions, not actions: writing one does not implement it.
- If the same proposal class recurs across multiple tasks, surface it as a
  coordination blocker rather than re-proposing silently.
- Improvements that touch memory storage or skills are also proposals; the act of
  *using* memory/skills is allowed, but changing the systems themselves needs
  approval.

---

## 5. Scope Expansion Protocol

(origin: orchestrator "Scope Expansion Protocol")

Stop and escalate when coordination would require the Orchestrator to decide something outside its coordination authority, including:

- inventing a new architectural direction
- overriding an Architect decision without new evidence
- authorizing Builder to exceed approved scope
- merging conflicting requirements without user/Architect authority
- concealing a failed specialist result to preserve momentum
- expanding the task into unrelated work

Use:

```text
Status: BLOCKED_BY_DECISION

Original objective:
<task>

Current state:
<what has been completed>

Discovered:
<new issue/conflict>

Why coordination alone is insufficient:
<concrete reason>

Affected work:
<agents/components>

Decision required:
Architect | User | Specialist

Changes made outside scope:
none
```

---

*End of Operations Reference. Summary of extraction origins for maintainers: §1 ← orchestrator §5 (env facts); §2 ← orchestrator §21; §3 ← orchestrator §26 (storage rules canonical in orchestrator "Memory vs Task State"); §4 ← orchestrator §27; §5 ← orchestrator §29.*