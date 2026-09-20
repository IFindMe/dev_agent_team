# Breakdowner Rework Plan — trial-forced rework (2026-09-19)

> builds-on: `AgentsReport/tester/2026-09-19_verify-loop-trial.md` (NOT READY, D1–D3) · live `bash scripts/test-agora.sh` 43/45 (T15 S=21 vs S=2, T17 tip absent; seed 3→5 post-gate publishes) · `AgentsReport/reviewer/2026-09-19_agora-gate.md:48` (gate-reopen conditions)
> slot: explore-known (re-plan from evidence, no new design)

## TL;DR

- Goal: plan the rework forced by trial findings with valid state.
- Structure chosen: append 06 + 07 + 08 to open `.tasks/ecc-verify-loop/` (no new tree; terminal `agora-phase1` untouched).
- Tasks: 06 skill D1–D3 fix (Tester) · 07 test-agora G3 hermetic fix (Tester) · 08 Reviewer re-verdict (skill + test-agora) · then 05 unblocked.
- Open items: validation invariant run (see Verification); Orchestrator dispatch order 06/07 → 08 → 05.

## Decision 1: placement — append to ecc-verify-loop, not a new micro-tree [DONE]

Chose append 06/07/08 to `.tasks/ecc-verify-loop/`. Alternatives rejected: (a) appending to `agora-phase1` would reopen a fully-terminal goal (all 5 `completed` — terminal states have no outgoing transitions); (b) a new micro-tree would fragment one coherent rework and lose the 05-unblock dependency. The rework is causally inside `ecc-verify-loop` (trial task 03 produced all findings; 05 still `pending` so the goal is open and owns the follow-up). Cross-goal file note is explicit in task 07 (`scripts/test-agora.sh` created under `agora-phase1` task 04; that tree untouched). Smallest valid structure wins. [DONE]

## Decision 2: task 06 scope — skill D1–D3 fix only [DONE]

Tester fixes D1 (untracked-aware diff review), D2 (untracked-aware lint signal), D3 (suite-discovery step) in `skills/verification-loop/SKILL.md` only. No script, seed, or count edits. Depends-on 03 (defect evidence lives in the trial report; 01 transitively via 03). [DONE]

## Decision 3: task 07 scope — hermetic G3, clarified T30 [DONE]

Tester rewrites G3 (`scripts/test-agora.sh:182-231`) to hermetic fixtures: isolated `/tmp` `AGORA_DIR` probe graph with pinned S-values, following the existing G4 pattern (`test-agora.sh:234-297`), so live seed appends never break the suite. Keeps G5 repo-mutation guard; T30 sha-guard role clarified (seed MAY grow via publish; guard asserts no non-publish mutation — defined precisely in the task). Depends-on 03; parallel-safe with 06. [DONE]

## Decision 4: task 08 — single Reviewer re-verdict, then 05 unblocked [DONE]

One Reviewer task 08 (skill re-verdict + test-agora re-gate) instead of two: same role, same gate moment, no ordering between the two verdict halves. Depends-on 06, 07. Pending task 05 gains an 08 dependency (now 03, 04, 08) — legal: 05 is `pending` (mutable), not terminal. Explicitly out everywhere: ADOPT-2..4, enforcement, new features. [DONE]

## Verification

Ran the `docs/TASK_BREAKDOWN_AGENT.md` §10 invariant against `.tasks/ecc-verify-loop/` (all six hold) — [DONE]:

1. `README.md`, `00-overview.md`, `tasks.json` all exist (`ls` confirmed). [DONE]
2. `tasks.json` parses (`python3 -m json.tool` exit 0) with exactly top-level keys `version`, `goal`, `tasks`. [DONE]
3. `tasks.json.goal == "ecc-verify-loop"`. [DONE]
4. Every record's `status` ∈ 7-state enum, keys ⊆ the 11-field set, and `tasks` map keys `01–08` == numbered files `01…08` (`00-overview.md` correctly excluded as reserved `00`). [DONE]
5. `00-overview.md` lists every numbered task `01–08`; each listed task has its file on disk. [DONE]
6. Numbers zero-padded ascending `01–08`, no gaps, no removals; ≥1 task exists. [DONE]

Plus brief-required checks: `json.tool` OK; keys==files OK; overview-lists-all OK; ascending-no-gaps OK. First checker FAIL was a script bug (it counted `00-overview.md` as task `00`); re-ran with `00` excluded → PASS. `.tasks/agora-phase1/` untouched (file list + `json.tool` re-verified post-edit). No source/skill/script edits made (planning-only fence kept). [DONE]

## Next executable task

`06` — first `pending` task whose `depends-on` are all `completed` (01–03 `completed`; 06 needs only 03). `07` is parallel-safe with 06 (same single dep, disjoint files). Then `08` (needs 06+07), then `05` (needs 03+04+08; 04 still `in_progress` under Maintainer). Orchestrator dispatches 06/07 next. [DONE]
