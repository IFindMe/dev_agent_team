# IMPROVEMENT-0001: Add verification-loop skill (ECC ADOPT-1 port)

Date: 2026-09-19
Proposed by: orchestrator (from architect decision 2026-09-19_phase1-ecc-gate.md Part B + explorer inventory 2026-09-19_ecc-inventory.md)
Status: APPROVED

## Observed problem

No consolidated pre-PR verification checklist exists. Tester/Reviewer own adjacent gates (test strategy, adversarial verdict) but neither enumerates the ordered build→types→lint→tests+coverage→security-grep→diff-review sequence with a PASS/FAIL verification report and READY/NOT READY verdict.

## Evidence

- `AgentsReport/explorer/2026-09-19_ecc-inventory.md`: ECC (`https://github.com/affaan-m/ECC.git` @ `07756ce`, v2.2.1, MIT) `skills/verification-loop/SKILL.md` (129 lines) ranked ADOPT-1 — genuine gap vs our 12 skills, pure Markdown, zero deps.
- `AgentsReport/architect/2026-09-19_phase1-ecc-gate.md` Part B [DECIDED]: ranking confirmed, ADOPT-1 first (smallest slice, immediate Tester/Reviewer value).
- `AgentsReport/reviewer/2026-09-19_agora-gate.md`: Phase 1 gate ACCEPT — verification discipline is proven valuable on this repo.

## Root cause

The skill set grew around roles (tdd, code-review, security-review) but never captured the cross-cutting pre-merge verification sequence as one reusable procedure, so each agent re-derives it per task.

## Proposed change

1. Create `skills/verification-loop/SKILL.md` — opencode-ported methodology (shell phases, report format), rewritten from ECC source (no verbatim copy of harness-specific paths).
2. Add 1 index row in `skills/SKILLS.md` + Tester row entry in the agent-skill map (`agents/orchestrator.md`).
3. Follow-up (Maintainer, separate): update `12 skills` prose counts (README.md, docs/OPERATIONS_REFERENCE.md, docs/AGENT_ARCHITECTURE.md, agents/orchestrator.md) 12→13.

## Affected agents/skills

- New skill owned by Tester (primary) / Reviewer (verdict consumer).
- Index owned by Orchestrator. No existing skill modified. No roster or routing change.

## Risks

- Context-load growth 12→13 skills (measured later by ADOPT-3 context-budget; single small skill is negligible).
- Porting drift from ECC source (mitigated: Reviewer verdict + trial run gate).

## Expected benefit

One canonical pre-PR checklist usable by Tester/Reviewer/Builder immediately; fewer re-derived verification steps per task.

## Verification plan

- Reviewer ACCEPT on draft skill.
- Trial run on one past task shows PASS/FAIL report.
- `bash scripts/test-all.sh` stays 8/8 (T05 counts ≥5 dynamically — additive safe, verified 2026-09-19).

## Approval

- [x] Human review — user instruction 2026-09-19 ("implement those what you learnt")
- [x] Impact assessment — additive only, no existing file semantics changed (see above)
- [x] Rollback plan — delete `skills/verification-loop/`, revert index/map rows (3 edits); re-run `test-all.sh`
