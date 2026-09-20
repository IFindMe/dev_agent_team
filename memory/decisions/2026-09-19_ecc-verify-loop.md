# Breakdown Report: `ecc-verify-loop` (2026-09-19)

> builds-on: improvements/pending/2026-09-19_verification-loop.md (APPROVED) ·
> AgentsReport/architect/2026-09-19_phase1-ecc-gate.md §B3 ·
> AgentsReport/_context/ecc-verify-loop.md · docs/TASK_BREAKDOWN_AGENT.md
> slot: exploit (plan the decided slice — no new design)

> TL;DR: Goal `ecc-verify-loop` decomposed into **5 tasks** (Tester×3, Maintainer×1,
> Reviewer×1) under `.tasks/ecc-verify-loop/`: 01 draft skill → fan-out 02/03/04 →
> fan-in 05 verdict. Kept 02 whole (≤5 cap). `tasks.json` via `state.sh`, all `pending`.
> Validation invariant **PASSES** (11/11 checks). Memory recall: no prior entries.
> Next: Orchestrator dispatches task 01 to Tester. No open structural items.

## Decision 1: Task granularity — 5 tasks, 02 kept whole

- Evidence: brief mandates 01..05 with "split 02a/02b if cleaner — keep total
  ≤5"; both 02 edits are trivial same-role single-row appends with no ordering.
- Action: 02 stays one task (`02-index-map-rows.md`); the no-split rationale is
  recorded in `00-overview.md` so re-plans don't re-litigate it.
- Result: 5 files, roles Tester/Tester/Tester/Maintainer/Reviewer. [DONE]

## Decision 2: Dependency shape — 01 → {02, 03, 04} → 05[03,04]

- Evidence: brief deps (02,03 after 01; 04 after 01 parallel-safe; 05 after
  03+04); context pack §3 (trial needs only the draft, counts need only the
  landing decision).
- Action: `tasks.json` deps 02:[01], 03:[01], 04:[01], 05:[03,04]; overview
  notes the Orchestrator dispatches 05 last (after 02 also complete) since 05
  reviews 01+02 artifacts.
- Result: `state.sh query pending` shows 01 unblocked head, correct fan-out. [DONE]

## Decision 3: Role purity + scope fence

- Evidence: proposal owners (Tester drafts, Reviewer verdicts, Maintainer
  counts follow-up); architect §B3 (no roster/routing change; ADOPT-2..4/ADAPT
  separate).
- Action: each task file names one role hint and an Out-of-scope section;
  global fence (ADOPT-2..4 + ADAPT + enforcement + Track-A
  `scripts/install.sh`) in README + overview + task 05.
- Result: no task asks an agent to do another role's job. [DONE]

## Decision 4: Machine state via `state.sh` (all `pending`)

- Evidence: `docs/TASK_BREAKDOWN_AGENT.md` §4/§6 (7-state enum, sanctioned
  transitions, CREATE with structural fields only).
- Action: 5× `task create` + `task deps add` under `--goal ecc-verify-loop`;
  no hand-edited JSON (one probe `deps 01 add` with zero args correctly errored
  and changed nothing; 01 deps remain `[]`).
- Result: `tasks.json` version 1, goal match, all `pending`. [DONE]

## Decision 5: Validation invariant before done

- Evidence: run output below (first run's 3 FAILs were a script bug counting
  reserved `00-overview.md` as a task file; re-ran excluding `00-`).
- Action: re-ran corrected script; all checks pass; `query pending` confirms
  dispatch order.
- Result: INVARIANT PASSES (11/11). [DONE]

## Decision 6: Memory store + handoff

- Evidence: `recall decisions verification-loop` / `recall lessons
  task-breakdown` → no entries (nothing to reconcile).
- Action: report written here; durable finding stored via `memory-lifecycle.sh
  store decisions` on this report; next executable task = 01 (Tester).
- Result: handoff ready; Orchestrator owns dispatch flips via `state.sh`. [PENDING]

## Created files

- `.tasks/ecc-verify-loop/README.md`
- `.tasks/ecc-verify-loop/00-overview.md`
- `.tasks/ecc-verify-loop/01-draft-skill.md`
- `.tasks/ecc-verify-loop/02-index-map-rows.md`
- `.tasks/ecc-verify-loop/03-trial-run.md`
- `.tasks/ecc-verify-loop/04-counts-12-to-13.md`
- `.tasks/ecc-verify-loop/05-reviewer-verdict.md`
- `.tasks/ecc-verify-loop/tasks.json` (via `state.sh`, all `pending`)
- `AgentsReport/breakdowner/2026-09-19_ecc-verify-loop.md` (this report)

## Validation evidence

```text
PASS 1-files-exist
PASS 2-keys-exact ['goal', 'tasks', 'version']
PASS 3-goal ecc-verify-loop
PASS 4-keys==files tasks=['01','02','03','04','05'] files=[01-draft-skill.md, 02-index-map-rows.md, 03-trial-run.md, 04-counts-12-to-13.md, 05-reviewer-verdict.md]
PASS 4-status / 4-fields / 4-all-pending
PASS 5-overview-lists-all listed=['01','02','03','04','05']
PASS 6-ascending-no-gaps ['01','02','03','04','05'] / 6-nonempty
PASS x-deps-earlier (all deps earlier)
INVARIANT: PASSES
query pending: 01 pending (head) → 02/03/04 blocked on 01 → 05 blocked on 03,04
```

## State record

```text
goal:                    Re-write APPROVED ADOPT-1 into .tasks/ecc-verify-loop/ (5 role-pure tasks, ordered deps, valid invariant) + report
hypothesis:              5-task fan-out (01 head, 02/03/04 parallel, 05 fan-in) is the smallest valid decomposition within the ≤5 cap
evidence:                Approved proposal + context pack + architect §B3 + SKILLS.md/orchestrator.md formats + ECC source (129 lines, shape only) + agora-phase1 tree precedent
actions_taken:           Wrote README/00-overview/01-05 + tasks.json via state.sh (creates+deps) + corrected invariant re-run + this report
result:                  Tree complete, invariant PASSES, all pending, next executable = 01
verification:            11/11 invariant checks + state.sh query pending order (see above)
confidence:              high
remaining_unknowns:      None structural; implementation unknowns belong to tasks 01-05
recommended_next_action: Orchestrator dispatches task 01 to Tester with the brief in 01-draft-skill.md
```

Tool calls used: ~20/30 cap. Cost notes: one wasted batch (6 empty writes),
one invariant re-run (script bug, fixed). No broad exploration; brief-named
files only (+ architect §B3 grep, agora-phase1 precedent peek, memory recall).
