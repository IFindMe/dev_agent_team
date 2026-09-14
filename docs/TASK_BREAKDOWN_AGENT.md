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
├── NN-<slug>.md       # last task (zero-padded 2-digit ascending: 01, 02, …; 00 reserved for overview)
└── tasks.json         # machine task state — one record per task, 7-state status (§ 4)
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
- **tasks.json** — the machine-readable task state: one record per task with a
  7-state status; the authoritative per-goal task state, enforced by
  `scripts/state.sh` (§ 4).
- **flag.json** — legacy planning state, optional; pre-migration trees only
  (§ 4).

## 4. Machine task state — `tasks.json` (authoritative) + legacy `flag.json`

### `tasks.json` — authoritative per-goal machine task state

Task status lives in `.tasks/<goal>/tasks.json` — the authoritative
machine-readable task state for the goal, enforced by `scripts/state.sh`
(installed to runtime as `bin/state.sh`). NEVER parse Markdown for task status;
status comes from `tasks.json` only.

```json
{
  "version": 1,
  "goal": "<goal-name>",
  "tasks": {
    "01": {
      "title": "<concise objective>",
      "description": "<scope / required output>",
      "status": "pending",
      "priority": "normal",
      "assigned_to": null,
      "dependencies": [],
      "created_at": "2026-09-13T02:00:00Z",
      "updated_at": "2026-09-13T02:00:00Z",
      "started_at": null,
      "completed_at": null
    }
  }
}
```

- Top-level keys are exactly `version` (int, = 1), `goal` (string ==
  `<goal-name>`), `tasks` (object). The task id is the **map key**, not a field
  inside the record.
- Per-task fields — the goal's full 11-field set: `id` (map key),
  `title`, `description`, `status`, `priority`, `assigned_to`, `dependencies`,
  `created_at`, `updated_at`, `started_at`, `completed_at`.
- `status` ∈ the 7-state enum verbatim:
  `pending | assigned | in_progress | blocked | completed | failed | cancelled`.
- `status` is **machine-owned**: changed only via sanctioned transitions through
  `scripts/state.sh` — never by hand-editing JSON, never parsed from Markdown.
  The tree itself stays Markdown (`README.md`, `00-overview.md`, `NN-*.md`);
  only machine state is JSON.

### `flag.json` — legacy planning state (verbatim format, compat note)

Pre-migration trees may keep the old verbatim format. It is **NOT
authoritative**, is not written for new goals, and its statuses map lossily to
the new enum: `pending→pending`, `in-progress→in_progress`, `done→completed`.
Remove it and port statuses into `tasks.json` on the next re-plan of that goal.

```json
{"goal":"<goal-name>","status":"pending|in-progress|done","tasks":{"01":"pending","02":"in-progress",...}}
```

- Keys: `goal` (string, must equal `<goal-name>`), `status` (one of
  `pending|in-progress|done`), `tasks` (object mapping each zero-padded task
  number to one of `pending|in-progress|done`).
- State meanings: `pending` = not started; `in-progress` = selected / dispatch
  active; `done` = verified complete.

Path summary, `state.sh` subcommands, the 7-state list, and the derived
`.tasks/agents.json` / `.tasks/sessions.json` / `.tasks/events.jsonl` surfaces:
[docs/OPERATIONS_REFERENCE.md §6 Machine state & JSON](OPERATIONS_REFERENCE.md#6-machine-state--json-reference).

## 5. Dependency ordering

- Tasks are ordered by dependency: foundational and externally-deciding tasks
  first; each task file declares `depends-on` explicitly over assumed ordering.
- Numbering is **stable**: never renumber existing tasks when re-planning; new
  tasks append with the next free number; a removed task leaves a gap noted in
  `00-overview.md` (numbers are never silently reused).
- The **next executable task** is the first `pending` task whose `depends-on`
  are all `completed`.

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
   one file per numbered task, and `tasks.json` with all tasks `pending`
   (structural fields only; § 7).
4. **verify deps** — run the validation invariant (§ 10) against the tree;
   confirm each task's `depends-on` are satisfied by earlier tasks; identify the
   next executable task.
5. **implement** — hands off: the Orchestrator reads the breakdown and
   dispatches specialists per task; `breakdowner` does not implement.

**Per-task lifecycle** — 7-state status in `tasks.json`, flipped only by the
Orchestrator through `scripts/state.sh` (`task status <NN> <status>`), with
verification before `completed`:

- `pending` — not started.
- `assigned` — named in `assigned_to`; work has not started.
- `in_progress` — the Orchestrator records the dispatch flip
  (`state.sh task status <NN> in_progress`) when it dispatches the task.
- `blocked` / `failed` / `cancelled` — pause / terminal-failure / terminal-discard.
- `completed` — set by the Orchestrator ONLY with verified-completion evidence,
  never by the implementing agent. Implementers report completion to the
  Orchestrator; they never self-flip `completed`.

**Next-task selection** — during create and re-plan, `breakdowner` reports the
next executable task (first `pending` task whose `depends-on` are all
`completed`); actual dispatch selection belongs to the Orchestrator.

**Living plan** — the tree is the single source of truth for task structure
(Markdown files) and task state (`tasks.json`). Re-planning that changes
structure (split, merge, add, rescope, invalidate) returns to `breakdowner`,
which updates the affected task files + `00-overview.md` + `tasks.json`
(structural fields) in one pass. During another agent's execution, `.tasks/` is
never mutated except through this route or the Orchestrator's two execution
flips (`task status <NN> in_progress` at dispatch; `task status <NN> completed`
on verified completion — both via `state.sh`).

**Never delete history** — the breakdown is never wholesale rewritten: task
numbers are appended, not renumbered; removed tasks leave noted gaps; prior task
files are superseded, not silently erased, so the plan's history stays
auditable.

## 7. Ownership of `.tasks/`

| Who | May read | May write |
|-----|----------|-----------|
| Breakdowner | yes (owns) | **YES — the only author of task structure + planning/re-planning state** (in `tasks.json`: structural fields only — `title`, `description`, `dependencies`, `priority` — at CREATE/UPDATE) |
| Orchestrator | yes | `tasks.json` execution flips ONLY via `state.sh`: `task status <NN> in_progress` at dispatch; `task status <NN> completed` only with verified-completion evidence; never edits task files / overview / structural fields |
| Workflow Architect | yes (reads README/overview/task files as input) | no — writes its model only in `AgentsReport/workflow-architect/` |
| Builder / Tester / Reviewer / all other agents | yes | no — implementers never self-flag `completed`; they report completion to the Orchestrator |
| state tool (`scripts/state.sh`) | yes | machine-state files ONLY: `.tasks/agents.json` (derived roster), `.tasks/sessions.json` (derived cursor), `.tasks/events.jsonl` (append-only log) — tool-owned, not planning state |

Rule: any `.tasks/` mutation that is not one of the Orchestrator's two
execution flips (which run through `state.sh` into `tasks.json`) is a re-plan
and must be performed by `breakdowner`. Machine-state files
(`.tasks/agents.json`, `.tasks/sessions.json`, `.tasks/events.jsonl`) are
tool-owned, not Breakdowner planning state.

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
4. `.tasks/<goal-name>/tasks.json` — machine task state, every task `pending`
   (structural fields only; § 4). Legacy `flag.json` only for pre-migration
   re-plans (compat note, § 4).
5. `AgentsReport/breakdowner/<YYYY-MM-DD>_<goal>.md` — TL;DR (≤10 lines) +
   `## Decision N:` sections ending `[DONE]/[PENDING]/[BLOCKED]`.

## 10. Validation invariant

For the tree `.tasks/<goal-name>/`, all six must hold:

1. `README.md`, `00-overview.md`, and `tasks.json` all exist (`flag.json` not
   required; optional legacy in pre-migration trees).
2. `tasks.json` parses as JSON and has exactly the top-level keys `version`,
   `goal`, `tasks`.
3. `tasks.json.goal == "<goal-name>"`.
4. Every `tasks` record's `status` ∈ {pending, assigned, in_progress, blocked,
   completed, failed, cancelled}; each record's keys ⊆ {title, description,
   status, priority, assigned_to, dependencies, created_at, updated_at,
   started_at, completed_at}; the set of `tasks` map keys equals the set of
   zero-padded numbers `NN` of existing files `NN-*.md` in the directory (no
   orphans, no missing).
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