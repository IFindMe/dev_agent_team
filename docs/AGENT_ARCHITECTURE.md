# Agent Team Architecture — Adaptive, Evidence-Driven Upgrade (v2)

This document describes the architecture of `dev_agent_team` after the second
architectural upgrade: making the existing 14-agent team **adaptive,
evidence-driven, repository-aware, cost-aware, and capable of long-horizon
work**. It extends — it does not replace — the Repository Intelligence Bootstrap
architecture documented in
[REPOSITORY_INTELLIGENCE.md](REPOSITORY_INTELLIGENCE.md).

> Summary of the change: the system moved from
> `"Choose an agent and ask it to do work"`
> to
> `"Understand the task → estimate complexity → gather the minimum necessary
> evidence → choose the best next action → execute → verify → re-plan → learn"`.

## 1. Architecture changes at a glance

| Area | Before | After |
|------|--------|-------|
| Orchestrator behavior | linear `REQUEST → … → REPORT` flow | adaptive `RECALL → UNDERSTAND → ESTIMATE → LOAD CONTEXT → CHOOSE ACTION → EXECUTE → VERIFY → RE-PLAN/STOP → LEARN → STORE` decision loop |
| Task sizing | implicit | explicit lightweight complexity estimation (`ESTIMATE → EXECUTE → EXPAND`) |
| Action selection | implicit routing by task type | explicit **Action Catalog** (27 actions with purpose/cost/risk/prereq/failure modes); direct tool calls preferred over agent dispatch when cheaper |
| Handoffs | prose contract | structured **evidence-state record** (9 fields) for meaningful decisions/investigations/failures/handoffs |
| Planning | replan on handoff | **adaptive planning** with failure classification (7 types) and no blind retries |
| Verification | verification gate | verification gate + **process quality** detection (lucky-pass, symptom-fixing, etc.) and lightweight **quality gates** |
| Cost | — | lightweight cost/token awareness driving routing decisions |
| Completion | completion rule | **explicit stop conditions** (goal satisfied + verified, acceptable uncertainty, no useful action, blocked) |
| Subagents | role boundaries + handoff formats | role-adapted **Evidence & Handoffs** sections; each agent knows its evidence product, knowledge ownership, stop, and escalation points |
| Repository knowledge | bootstrap + skills | unchanged structure + **knowledge lifecycle** rules (discover → classify → identify owner → update only the relevant doc → preserve valid content) |
| Agent roster | 13 agents | **now exactly 14 agents** (1 orchestrator primary + 13 subagents); one new role (`breakdowner`) added |
| Project memory | — | **deterministic cross-session memory** in `memory/` (decisions, lessons, failures, architecture, sessions) with lifecycle script |
| Skills | — | **12 reusable specialized methodologies** in `skills/` loaded by agents when needed |
| Improvements | — | **proposal-based improvement system** in `improvements/` requiring human approval |

## 2. Orchestrator decision loop

The Orchestrator is a decision engine. Its core loop:

```text
UNDERSTAND → ESTIMATE → LOAD CONTEXT → CHOOSE ACTION → EXECUTE → VERIFY → RE-PLAN (or STOP) → LEARN
```

At every iteration it:

1. **Understands** the objective (goal vs investigation vs implementation vs architecture).
2. **Estimates** complexity (scope, likely files, dependency depth, architecture impact, uncertainty, testability, risk, expected actions).
3. **Loads context** — `.opencode/` repository intelligence, refreshed when stale.
4. **Chooses the next action** from the Action Catalog (cheapest reliable action that yields the evidence needed for the NEXT decision).
5. **Executes** — a direct tool call (inspect/search/git/tests) or a specialist dispatch.
6. **Observes + verifies** — evidence over claims; independent verification drives the next decision.
7. **Re-plans** when evidence changes, or **stops** when the stop conditions hold; then updates durable knowledge.

Optimization target: **verified progress, minimum sufficient work, correct
tool/agent selection, low unnecessary context usage, recoverability, evidence
quality, repository consistency** — not maximum agents or maximum reasoning.

## 3. Task complexity estimation

A few bullets before committing to a workflow:

```text
scope:            small | medium | large
likely files:     <count estimate>
dependency depth: shallow | moderate | deep
architecture impact: none | local | cross-cutting
uncertainty:      low | medium | high
testability:      high | medium | low
risk:             low | medium | high
expected actions: <estimate>
```

Guiding principle: **`ESTIMATE → EXECUTE → EXPAND`**. Start with the smallest
reliable investigation; expand only when evidence says so; shrink when the task
is simpler than expected; record why scope expanded; never reread what is
already understood.

- Trivial → self-serve, no dispatched agents.
- Medium → one or two specialists, small verification.
- Complex → full context bootstrap, evidence-first investigation, architecture if
  needed, staged implementation, independent verification, review.

## 4. Action catalog (tool cards)

The Orchestrator selects actions from a catalogue of 24 entries. Each entry has:

```text
name, purpose, inputs, outputs, read_only, cost, risk, prerequisites, failure_modes
```

Groups: **inspect** (repository, search, git history, dependencies, build
system, tests, configuration), **experiment/verify** (run experiment, run
verification), **dispatch** (Explorer, Detective, Architect, Designer, Builder,
Tester, Reviewer, Workflow Architect, Philosopher, Maintainer, Toolsmith,
Writer), **update** (repository knowledge), **terminate** (finish/report,
re-plan).

Selection rules: prefer the cheapest action yielding the required next-decision
evidence; prefer direct inspection over agent dispatch for simple lookups;
dispatch agents only for specialist reasoning/evidence/implementation; on
failure choose a different action; never run Builder without approved scope,
Reviewer without an implementation, or Philosopher after purpose is clear.

## 5. Evidence / state model

Meaningful decisions, investigations, failures, and handoffs use the structured
state record:

```text
goal
hypothesis
evidence
actions_taken
result
verification
confidence
remaining_unknowns
recommended_next_action
```

Trivial steps use brief prose. The Orchestrator reasons from evidence, not
conversational claims; it never accepts "it works" as "evidence shows it works".

### State separation (context management)

```text
repository knowledge  → .opencode/ skills + AGENTS.md (durable, role-owned)
project memory        → memory/ decisions, lessons, failures, architecture, sessions (cross-session)
task state            → .tasks/<goal>/tasks.json (authoritative JSON) + AgentsReport/<agent>/ reports (Markdown)
agent handoff state   → the state records passed between agents
scratch               → /tmp/opencode or in-memory (throwaway)
```

Long-running tasks persist the current state record in the task report so work
survives context compaction and can be resumed with identical facts.

## 6. Verification model

- Implementation and verification are separate: Builder produces changes;
  Tester/Reviewer produce independent verification.
- Verification uses real evidence: tests, build results, static analysis,
  runtime behavior, logs, reproducible commands, artifacts, measurements.
- Agents do not give themselves full credit for unverified claims.
- The Verification Gate requires: objective satisfied, specialists completed,
  no scope expansion, coherent handoffs, targeted verification passed, project
  validation performed, no hidden blocker, explicit remaining risks.

### Process quality

The outcome alone is not the trajectory. Detected anti-patterns: blind retries,
repeated identical actions, unnecessary file reading, implementation before
understanding, testing too late, skipping verification, fixing symptoms without
evidence, solving only the visible test case, repeatedly calling agents without
new information, continuing after sufficient verification. A lucky pass is a
finding (Reviewer), not acceptance.

### Quality gates

```text
UNDERSTANDING → PLAN → IMPLEMENT → VERIFY → REVIEW → COMPLETE
```

Each transition requires appropriate evidence; gates are skipped for trivial
tasks, mandatory for complex ones.

## 7. Handoff model

Compact handoffs carry only what the next agent needs: objective, known facts,
evidence, files/components, changes made, failed attempts, verification state,
open questions, recommended next action. No whole transcripts. Persistent where
long-running tasks require it.

## 8. Failure recovery

Every significant failure is classified before the next action:

| Type | Response |
|------|----------|
| tool | switch tool/invocation, verify prerequisites |
| environment | fix environment or surface BLOCKED |
| assumption | record evidence, form new hypothesis |
| plan | revise plan from evidence |
| implementation | Detective if cause unknown, else Builder fix |
| test | Tester corrects the test/strategy |
| coordination | re-route or repair handoff |

Rules: one immediate retry per failed Task, then classify and choose
differently; surface repeated-failure loops instead of looping silently; a
failed hypothesis produces a new plan.

## 9. Stop conditions

The Orchestrator stops when: goal satisfied AND required verification passed;
remaining uncertainty is acceptable (documented); no useful next action
remains; or the workflow is genuinely BLOCKED. It does not call agents merely
because they are available.

## 10. Cost and token awareness

Lightweight execution-cost model driving routing: approximate tool calls, agent
dispatches, expensive/repeated ops, unnecessary investigation, context growth.
No billing system. Rules: cheapest action that yields the needed evidence;
fewer better-scoped agents; equal evidence → cheaper action; context growing
faster than progress → stop investigating and re-plan.

## 11. Repository intelligence and knowledge lifecycle

`.opencode/` remains the repository-local source of agent context (skills +
AGENTS.md + `.bootstrap-meta`). No separate `knowledge/` or `state/` trees were
added: the skills already play the role of `architecture.md`/`build.md`/
`conventions.md`, and `AgentsReport/` already separates task state from repo
knowledge. Machine task state lives in the per-goal `.tasks/<goal>/tasks.json`
(machine-readable JSON, enforced by `scripts/state.sh`), with the goal tree
itself (`README.md`, `00-overview.md`, `NN-*.md`) staying Markdown.

Lifecycle: when new durable facts are discovered → decide whether they belong in
repository knowledge → identify the owner (Explorer for repo-context, Architect
for architecture, Builder/Tester for build-and-test, Maintainer for
conventions, Orchestrator for AGENTS.md) → update only that document → preserve
valid existing information → never record temporary task details. Stale content
is detected by bootstrap fingerprints and corrected by the owning agent.

## 12. Project memory (cross-session persistence)

Project memory provides deterministic, inspectable, version-controlled
persistence across sessions. It lives in `memory/` at the repository root:

```text
memory/
├── MEMORY.md           # index with lifecycle rules
├── decisions/          # architectural/technical choices (evidence-backed)
├── lessons/            # reusable knowledge (proven patterns)
├── failures/           # root causes + prevention (incident records)
├── architecture/       # system structure documentation
└── sessions/           # work-in-progress state (session continuity)
```

**Lifecycle script**: `scripts/memory-lifecycle.sh` provides deterministic
operations: `recall`, `store`, `list`, `search`, `sessions`, `cleanup`.

**Integration**: The Orchestrator recalls relevant memory before task
classification and stores durable findings after substantial work. All 12
subagents check memory before investigating/implementing and store lessons
after completing their work.

**Rules**: Store selectively (not every tool call); entries must be
evidence-backed; preserve existing memory; never store task-specific noise as
durable knowledge.

**Sessions coexistence**: `memory/sessions/*.md` stays the sessions source of
truth (pinned `Status: active | interrupted | completed` parse, unchanged).
`.tasks/sessions.json` is only a **derived cursor**, regenerated by
`state.sh sessions sync` from the Markdown `Status:`/`Started:`/
`Last updated:` lines — `memory-lifecycle.sh` never reads it and the Markdown
session flow is unchanged.

## 13. Skills system (reusable methodologies)

Skills are reusable, specialized capabilities that agents load when needed.
They live in `skills/` at the repository root:

```text
skills/
├── tdd/SKILL.md                    # Test-Driven Development
├── systematic-debugging/SKILL.md   # debugging methodology
├── architecture-design/SKILL.md    # architecture decisions
├── code-review/SKILL.md            # code review process
├── security-review/SKILL.md        # security review
├── repository-analysis/SKILL.md    # repo exploration
├── failure-analysis/SKILL.md       # failure investigation
├── refactoring/SKILL.md            # safe code restructuring
├── test-analysis/SKILL.md          # test quality assessment
├── incident-investigation/SKILL.md # production incidents
├── browser-automation/SKILL.md     # web interaction patterns
└── research/SKILL.md               # information gathering
```

**Loading**: When the Orchestrator dispatches a specialist, the brief includes
the relevant skill path. The agent reads the skill before starting work.

**Ownership**: Skills are owned by their primary agent (e.g., `tdd` by Builder,
`systematic-debugging` by Detective). The Orchestrator is the index owner.

**Extension**: To add a skill, create `skills/<name>/SKILL.md` with frontmatter
(name, description, version, owner) and sections (When to use, Core
methodology, Step-by-step procedure). Update `skills/SKILLS.md` index.

## 14. Improvement proposals

The improvement proposal system provides a structured way to evolve agent
behavior, skills, and processes. Proposals live in `improvements/`:

```text
improvements/
├── README.md     # proposal format and lifecycle
├── pending/      # proposals awaiting human approval
├── applied/      # approved and implemented proposals
└── rejected/     # proposals that were not approved
```

**Rules**: Do NOT modify core agent behavior without human approval. Create
proposals in `improvements/pending/`. Present proposals at natural stopping
points. Include: observed problem, evidence, root cause, proposed change,
risks, verification plan.

**Detection triggers** (evidence-driven, not per-task): a proposal is warranted
when a failure recurs, a needed skill is missing, routing was inefficient, a
documentation gap forced re-derivation, a multi-step process would recur, or a
genuinely reusable pattern emerged. Proposals are decisions, not actions —
writing one does not implement it; human approval is required for changes that
touch core agent behavior, agent prompts, the orchestrator's decision logic,
or the agent roster.

### Task lifecycle (full loop)

A coherent task runs through these stages; trivial tasks collapse them, complex
tasks engage every stage with evidence feeding the next:

```text
1. RECALL      — search memory (sessions, decisions, lessons, failures)
2. UNDERSTAND  — separate goal from investigation/implementation/architecture
3. ESTIMATE    — lightweight complexity (scope, files, impact, uncertainty, risk)
4. LOAD        — read .opencode/ repo intelligence (refresh if stale); read skills
5. PLAN        — decompose into work items; pick agents; set dependencies
6. DISPATCH    — brief each agent (objective, scope, patterns, skill paths, report)
7. VERIFY      — check artifacts on disk; confirm evidence; re-plan on mismatch
8. LEARN       — classify outcomes: decision / lesson / failure / session
9. STORE       — persist durable findings to memory/ via memory-lifecycle.sh
10. IMPROVE    — detect improvement proposals; write to improvements/pending/
11. REPORT     — final report mapping result to original objective
```

Memory touch is selective: trivial/ephemeral work is not stored; one-off but
meaningful work stores a lesson/decision if durable; recurring patterns store a
failure record AND consider a proposal; architectural work stores a decision;
long-horizon work maintains a session record.

Agent selection is not a fixed pipeline: memory is recalled first, relevant
skills are loaded into dispatch briefs, and **skip-when** guards avoid
dispatching agents whose reasoning is not required for the next decision.

## 15. Agent ownership of knowledge and evidence

| Agent | Knowledge owned | Primary evidence product | Stop when |
|-------|-----------------|--------------------------|-----------|
| Explorer | repo-context | system map with file:line, certainty levels | findings complete + verified |
| Detective | — (consumer) | hypothesis/evidence/confidence, eliminated alternatives | root cause established |
| Architect | architecture | decision record (options, trade-offs, scope) `[DECIDED/PROVISIONAL/BLOCKED]` | decision ready |
| Builder | build-and-test (with Tester) | files changed + targeted verification actually run | brief end reached |
| Breakdowner | .tasks/ structure (per-goal) | valid Task Breakdown + tasks.json machine task state | invariant holds + handoff ready |
| Tester | build-and-test (with Builder) | tests run, pass/fail, coverage gaps | tests ready/provisional |
| Designer | — (consumer) | design spec tied to user needs/constraints | design ready |
| Reviewer | validation of all skills | verdict + findings with severity/certainty, lucky-pass detection | ACCEPT/CHANGES_REQUIRED/BLOCKED |
| Maintainer | conventions (+ audit all) | drift finding + minimal correction + validation | standard restored |
| Toolsmith | — (consumer; conventions via Maintainer) | recurrence record + proof safeguard fires | safeguard verified |
| Philosopher | — (may add purpose to repo-context) | recorded user voice + reasoning | philosophy ready |
| Workflow Architect | — (consumer) | model + justification + resolved ambiguities | model complete + valid |
| Writer | — (consumer) | docs mapped to source reports/files | docs ready |

Every agent additionally has a role-adapted **Evidence & Handoffs** section with
the 9-field state record, explicit evidence product, stop condition, and
escalation point.

## 16. Parallelism

Parallel only when genuinely independent (no unresolved dependency, no shared
state conflicts, independently interpretable results), and only after
considering coordination cost. Good: three independent Explorer investigations
(architecture, tests, dependencies). Bad: three agents investigating the same
files or proposing identical fixes.

## 17. Evaluation

Structural readiness is verified by `scripts/test-agent-architecture.sh`
(currently 17 checks). Runtime behavior is evaluated through the 12 scenarios in
[EVALUATION_SCENARIOS.md](EVALUATION_SCENARIOS.md), scored on success,
unnecessary work, repeated actions, verification quality, correct agent
selection, cost/context growth, and recovery quality — not just pass/fail.

## 18. Example execution trace — simple task

```text
User: "Fix the typo in README.md line 12."
  1. UNDERSTAND     — trivial, one file, no risk, known.
  2. ESTIMATE       — scope small; files 1; risk low; actions ≈ 2.
  3. LOAD CONTEXT   — .opencode fresh; README conventions known.
  4. CHOOSE ACTION  — A1 inspect repository? No — A2 search code (read README line 12) directly.
  5. EXECUTE        — self: read README.md, edit the typo.
  6. VERIFY         — self: re-read the line, confirm correction.
  7. STOP           — goal satisfied + verified; report.
  Agents dispatched: 0.  Cost: ~4 tool calls.
```

## 19. Example execution trace — complex task

```text
User: "Add a build cache to the pipeline and verify it improves CI time."
  1. UNDERSTAND     — implementation + measurement; architecture impact possible.
  2. ESTIMATE       — scope large; files 5–10; impact cross-cutting; uncertainty high; actions ≈ 20+.
  3. LOAD CONTEXT   — .opencode checkpointed/refreshed; build skill read.
  4. INVESTIGATE    — dispatch Explorer (build + CI layout) — one scoped pass.
  5. EVIDENCE       — Explorer returns system map, build commands, cache surfaces.
  6. ARCHITECTURE   — dispatch Architect: boundary of the cache (which builds share it, invalidation rule).
  7. PLAN → IMPLEMENT — dispatch Builder with approved scope + patterns.
  8. VERIFY         — dispatch Tester: cache correctness + baseline comparison; run before/after CI steps.
  9. REVIEW         — dispatch Reviewer: scope compliance, lucky-pass check (did tests actually exercise the cache?).
  10. LEARN         — update .opencode build-and-test with the cache command/invalidation rule.
  11. STOP          — measured improvement + review accepted; report with evidence.
  Agents dispatched: 4 (Explorer, Architect, Builder+Tester, Reviewer).
  Cost: higher, but each dispatch produced decision value.
```

## 20. Remaining weaknesses

- The action catalog and cost model are textual guidance, not enforced tooling;
  faithful use depends on the orchestrator model following instructions.
- Runtime evaluation scenarios require a live opencode session; they are
  documented, not automated end-to-end.
- Staleness of `.opencode/` is detected by bootstrap fingerprints (manifests +
  layout), not by semantic drift of manually enriched content; manual facts are
  protected and may still become stale until an owner corrects them.
- The 9-field state record is a contract, not a schema validator; adherence is
  enforced by reviewer attention, not mechanically.
- Knowledge ownership depends on role discipline; an agent that enriches the
  wrong skill would only be caught by review.
- Project memory is selective — not every finding is stored; agents must
  exercise judgment about what constitutes durable knowledge.
- Memory retrieval is keyword-based, not semantic; relevant entries may be missed
  if keywords don't match.
- Improvement proposals require human approval, which may slow rapid iteration
  on agent behavior.

## 21. Task Breakdown (14th agent: breakdowner)

`breakdowner` is the 14th agent (approved 2026-09-12, Architect Decision): a
planning-only subagent that re-writes LARGE goal prompts into a numbered,
state-tracked **Task Breakdown** under `.tasks/<goal-name>/` so big goals
execute from small, self-contained task files instead of re-feeding the giant
prompt into every context. It produces the implementation plan only — never the
implementation, the verification, or the workflow model.

### Location and lifecycle

- Every breakdown lives at `<project git root>/.tasks/<goal-name>/`, where
  `<goal-name>` is a short kebab-case slug (e.g. `add-build-cache`).
- `.tasks/` is **project-local, local-only, and gitignored — never committed and
  never installed**. It is not copied by `scripts/install.sh`, is not part of
  the runtime tree (`${OPENCODE_DEV_AGENT_TEAM}/...`), and must never be
  referenced as a shipped artifact in docs.
- A breakdown is created ONCE per goal and updated only on re-planning:
  `analyze → break-down → create → verify deps → implement`, with per-task
  status in `tasks.json` (`pending → assigned → in_progress → completed`, 7
  states total, flipped via `state.sh`; verify before `completed`), next-task
  selection from `depends-on`, and a living plan whose history is never deleted
  (append new task numbers, never renumber; removed tasks leave noted gaps).

### Artifact ownership

| Artifact | Question answered | Owner | Location |
|---|---|---|---|
| Task Breakdown | "what tasks must be executed, in what order, in what state" (implementation-plan tree: README.md, 00-overview.md, NN-*.md, tasks.json) | **Breakdowner** | `.tasks/<goal-name>/` |
| Workflow model | "what states/transitions does the resulting system have" (domain behavior spec) | **Workflow Architect** | `AgentsReport/workflow-architect/<YYYY-MM-DD>_<for-what>.md` |

- Workflow Architect READS the breakdown as input context and writes its model
  only in its own report dir; it writes nothing into `.tasks/`. Breakdowner
  never models behavior (no FSM/DAG/statechart).
- Orchestrator may perform only the two mechanical `tasks.json` execution flips,
  via `scripts/state.sh`: `task status <NN> in_progress` at dispatch; `task
  status <NN> completed` only with verified-completion evidence. Every other
  `.tasks/` mutation is re-planning and must return to Breakdowner.

### Trigger summary

Dispatch `breakdowner` for large goals when ANY holds (measured before work
dispatch): ≥ 3 likely files or medium/large scope; moderate/deep dependency
depth; ≥ 3 specialist roles, or ≥ 2 specialists plus an integration step; goal
context > ~800 tokens or > 5 artifacts/reports referenced simultaneously;
long-horizon multi-session work with a state-tracked handoff chain. Never
dispatch for goals that are single-file, fit one compact brief, need ≤ 2
specialists with no integration, and are low risk.

### Validation

Every tree must satisfy the 6-point **validation invariant** before
`breakdowner` claims done: `README.md`, `00-overview.md`, `tasks.json` exist
(`flag.json` optional legacy); `tasks.json` parses with exactly the top-level
keys `version`, `goal`, `tasks` and `goal` matches the slug; every record's
`status` ∈ {pending, assigned, in_progress, blocked, completed, failed,
cancelled} and record keys ⊆ {title, description, status, priority,
assigned_to, dependencies, created_at, updated_at, started_at, completed_at};
the `tasks` map keys equal the set of zero-padded numbered files `NN-*.md` on
disk; `00-overview.md` lists every numbered task; numbers are zero-padded
ascending with no non-removal gaps. Full convention and spec summary:
[Task Breakdown Agent (breakdowner)](TASK_BREAKDOWN_AGENT.md).