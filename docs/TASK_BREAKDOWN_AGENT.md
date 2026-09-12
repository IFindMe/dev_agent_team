# Task Breakdown Agent (`breakdowner`)

`breakdowner` is the 14th agent of `dev_agent_team` (approved 2026-09-12,
Architect Decision): a planning-only subagent, dispatched by the Orchestrator,
that re-writes LARGE goal prompts into a numbered, state-tracked **Task
Breakdown** under `.tasks/<goal-name>/` — so the rest of the team executes from
small, self-contained task files instead of re-feeding a giant prompt into every
context.

This document is the normative Task Breakdown convention and the agent spec
summary. It matches the [agent architecture
documentation](AGENT_ARCHITECTURE.md) conventions.

## 1. Role summary

`breakdowner` produces the **implementation plan** — what tasks must be
executed, in what order, in what state. It does NOT produce the workflow/state
model (→ Workflow Architect), the technical architecture (→ Architect), the
implementation (→ Builder), or the verification (→ Tester/Reviewer).

- Owns ONLY the `.tasks/<goal-name>/` tree and its planning/re-planning state.
- Never implements, never verifies implementations, never models domain
  behavior, never dispatches or coordinates agents.
- Its "verification" is the structural **validation invariant** of its own tree
  (§ 10), never the work the tree describes.

## 2. Location and lifecycle of `.tasks/`

- Every breakdown lives at `<project git root>/.tasks/<goal-name>/`, where
  `<goal-name>` is a short kebab-case slug of the goal (e.g.
  `add-build-cache`, `fix-ci-timeout`).
- `.tasks/` is **project-local, local-only, and gitignored — NEVER committed and
  NEVER installed**. It is not copied by `scripts/install.sh`, is not part of
  the runtime (`${OPENCODE_DEV_AGENT_TEAM}/...`), and is never referenced as a
  shipped artifact in docs. If anything tries to commit `.tasks/`, flag it to
  the Orchestrator.
- A breakdown is created ONCE per goal and updated ONLY on re-planning.

## 3. Mandatory breakdown files

```text
.tasks/<goal-name>/
├── README.md          # goal statement + how to read the breakdown + pointer to 00-overview.md
├── 00-overview.md     # the plan: ordered task list, one line each: description + depends-on + responsible role hint
├── 01-<slug>.md       # task 1 — self-contained: objective, scope, depends-on, inputs, expected output, verification, out-of-scope
├── 02-<slug>.md       # task 2
└── NN-<slug>.md       # last task (zero-padded 2-digit ascending: 01, 02, …; 00 reserved for overview)
```

- **README.md** — goal statement, how to read the breakdown, pointer to
  `00-overview.md`.
- **00-overview.md** — the plan: an ordered list of every numbered task (one
  line each) with `depends-on` and a responsible-role hint. `00-overview.md`
  MUST list every numbered file, and every numbered file MUST be referenced
  there.
- **NN-<slug>.md** — one self-contained file per task: objective, scope,
  depends-on, inputs, expected output, verification, out-of-scope. An agent
  executing `03-<slug>.md` should not need the original goal prompt.
- **flag.json** — the machine-readable planning state (§ 4).

## 4. `flag.json` — planning state (verbatim format)

The compact verbatim format is normative:

```json
{"goal":"<goal-name>","status":"pending|in-progress|done","tasks":{"01":"pending","02":"in-progress",...}}
```

The same contract, expanded:

```json
{
  "goal": "<goal-name>",
  "status": "pending",
  "tasks": {
    "01": "pending",
    "02": "in-progress"
  }
}
```

- Keys: `goal` (string, must equal `<goal-name>`), `status` (one of
  `pending|in-progress|done`), `tasks` (object mapping each zero-padded task
  number to one of `pending|in-progress|done`).
- State meanings: `pending` = not started; `in-progress` = selected / dispatch
  active; `done` = verified complete.

## 5. Dependency ordering

- Tasks are ordered by dependency: foundational and externally-deciding tasks
  first; each task file declares `depends-on` explicitly over assumed ordering.
- Numbering is **stable**: never renumber existing tasks when re-planning; new
  tasks append with the next free number; a removed task leaves a gap noted in
  `00-overview.md` (numbers are never silently reused).
- The **next executable task** is the first `pending` task whose `depends-on`
  are all `done`.

## 6. Workflow rules

```text
analyze → break-down → create → verify deps → implement
```

1. **analyze** — read the goal prompt, every report/evidence path the brief
   names, and the existing `.tasks/` tree when this is a re-plan. Do not explore
   broadly.
2. **break-down** — decompose the goal into numbered, dependency-ordered task
   files at the smallest valid granularity that keeps each task to one coherent
   unit.
3. **create** — scaffold `.tasks/<goal-name>/`: `README.md`, `00-overview.md`,
   one file per numbered task, `flag.json` with all tasks `pending` and goal
   `status: pending`.
4. **verify deps** — run the validation invariant (§ 10) against the tree;
   confirm each task's `depends-on` are satisfied by earlier tasks; identify the
   next executable task.
5. **implement** — hands off: the Orchestrator reads the breakdown and
   dispatches specialists per task; `breakdowner` does not implement.

**Per-task lifecycle** — `pending → in-progress → done`, with verification
before `done`:

- `pending` — not started.
- `in-progress` — the Orchestrator records this when it dispatches the task.
- `done` — set by the Orchestrator ONLY with verified-completion evidence, never
  by the implementing agent. Implementers report completion to the Orchestrator;
  they never self-flag `done`.

**Next-task selection** — during create and re-plan, `breakdowner` reports the
next executable task (first `pending` task whose `depends-on` are all `done`);
actual dispatch selection belongs to the Orchestrator.

**Living plan** — the tree is the single source of truth for task structure.
Re-planning that changes structure (split, merge, add, rescope, invalidate)
returns to `breakdowner`, which updates the affected task files +
`00-overview.md` + `flag.json` in one pass. During another agent's execution,
`.tasks/` is never mutated except through this route or the Orchestrator's two
execution flips.

**Never delete history** — the breakdown is never wholesale rewritten: task
numbers are appended, not renumbered; removed tasks leave noted gaps; prior task
files are superseded, not silently erased, so the plan's history stays
auditable.

## 7. Ownership of `.tasks/`

| Who | May read | May write |
|-----|----------|-----------|
| Breakdowner | yes (owns) | **YES — the only author of task structure + planning/re-planning state** |
| Orchestrator | yes | `flag.json` execution flips ONLY: set task `in-progress` at dispatch; set task `done` only with verified-completion evidence; never edits task files / overview |
| Workflow Architect | yes (reads README/overview/task files as input) | no — writes its model only in `AgentsReport/workflow-architect/` |
| Builder / Tester / Reviewer / all other agents | yes | no — implementers never self-flag `done`; they report completion to the Orchestrator |

Rule: any `.tasks/` mutation that is not one of the Orchestrator's two
execution flips is a re-plan and must be performed by `breakdowner`.

## 8. Trigger summary

`breakdowner` is dispatched ONLY by the Orchestrator and ONLY for large goals.
It never self-invokes.

**MUST dispatch (large goal)** — when ANY of these hold (measured before any
work dispatch):

1. `likely files >= 3`, or the estimate `scope` is medium/large.
2. Dependency depth is moderate/deep: task N's input is task M's output.
3. The goal requires >= 3 distinct specialist roles, OR >= 2 specialists plus an
   integration step.
4. Goal context exceeds one compact dispatch brief: goal text > ~800 tokens, OR
   > 5 source artifacts/reports must be referenced simultaneously.
5. Long-horizon: work spans multiple sessions, context compaction, or a
   state-tracked handoff chain.

**MUST NOT dispatch (small/trivial)** — when ALL of these hold:

1. Single file, single edit, single component, no ordering dependencies.
2. Goal fits one compact dispatch brief (<= ~800 tokens incl. context
   references).
3. At most 2 specialists would be involved, with no integration dependency.
4. Orchestrator estimate: scope small, likely files <= 2, dependency shallow,
   architecture impact none/local, uncertainty low, risk low, expected actions
   < 8.

If dispatched for a goal that is actually trivial, do NOT create a breakdown:
return a `[BLOCKED: goal is too small for a Task Breakdown — Orchestrator should
self-serve]` report instead of inventing structure.

## 9. Interface contract

**Input** (dispatch brief from Orchestrator):

- The large goal prompt (or a scoped summary of it).
- Optional: cited evidence/report paths (Explorer findings, memory recalls,
  prior handoffs) to incorporate into `00-overview.md`.
- Constraints: `goal-name` slug; any mandatory dependency order; any forbidden
  split boundaries.

**Output**:

1. `.tasks/<goal-name>/README.md` — goal statement, how to read the breakdown,
   pointer to `00-overview.md`.
2. `.tasks/<goal-name>/00-overview.md` — the plan: ordered list of tasks (one
   line each), `depends-on`, responsible-role hint.
3. `.tasks/<goal-name>/NN-<slug>.md` (01…NN, zero-padded, 00 reserved) — one
   self-contained file per task.
4. `.tasks/<goal-name>/flag.json` — verbatim format (§ 4).
5. `AgentsReport/breakdowner/<YYYY-MM-DD>_<goal>.md` — TL;DR (≤10 lines) +
   `## Decision N:` sections ending `[DONE]/[PENDING]/[BLOCKED]`.

## 10. Validation invariant

For the tree `.tasks/<goal-name>/`, all six must hold:

1. `README.md`, `00-overview.md`, and `flag.json` all exist.
2. `flag.json` parses as JSON and has exactly the keys `goal`, `status`,
   `tasks`.
3. `flag.json.goal == "<goal-name>"`; `flag.json.status ∈ {pending, in-progress,
   done}`; every value of `flag.json.tasks ∈ {pending, in-progress, done}`.
4. The set of keys of `flag.json.tasks` equals the set of zero-padded numbers
   `NN` of existing files `NN-*.md` in the directory (no orphans, no missing
   files).
5. `00-overview.md` lists every numbered task `01…NN`; each listed task has a
   corresponding file on disk.
6. Task numbers are zero-padded ascending with no non-removal gaps; at least one
   numbered task exists.

Invariant passes ⇔ all six hold. `breakdowner` runs the invariant before
claiming completion and reports the checks run in its report's `verification:`
field. The invariant is intentionally testable; Tester may encode it from the
shell-checkable sketch in the Architect decision report.

## 11. Relationship to other agents

```text
Orchestrator (large goal)
    ↓ dispatch
Breakdowner (creates .tasks/<goal>/ → hands off)
    ↓ (Orchestrator reads breakdown, dispatches per task)
Workflow Architect (reads breakdown; model → AgentsReport/workflow-architect/)
    ↓
Architect → Builder → Tester → Reviewer
```

- **Orchestrator** decides when a goal is large, dispatches `breakdowner`, then
  plans the agent sequence FROM the breakdown — no parallel decomposition of
  its own for that goal.
- **Workflow Architect** reads the breakdown as input context and produces the
  domain behavior model in its own report directory; it never writes `.tasks/`.
  If a task needs a model first, `breakdowner` writes "model the workflow
  (Workflow Architect) before implementation" in the task file — it does not
  model it.
- **Builder / Tester / Reviewer** read the task file assigned to them and the
  overview for context; they never write `.tasks/`.
- Re-planning returns to `breakdowner` any time the task structure or planning
  state must change.

## 12. Final rules

- **Decide task boundaries, do not blur role boundaries.**
- **Never implement; never verify; never model workflows; never dispatch.**
- **Write only `.tasks/` structure and your report.**
- **Do not create a breakdown for a goal too small to need one.**
- **The validation invariant decides when you are done, not your opinion.**
- **A good breakdown makes every downstream agent's job smaller — and your own
  job invisible in the result.**