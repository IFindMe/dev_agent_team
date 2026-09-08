# Improvement Proposals

Controlled self-improvement for the agent team. **No autonomous modification
of core agent behavior without human approval.**

## Structure

```
improvements/
├── README.md              # This file
├── pending/               # Proposals awaiting approval
│   └── YYYY-MM-DD_<id>.md
├── applied/               # Approved and implemented proposals
│   └── YYYY-MM-DD_<id>.md
└── rejected/              # Rejected proposals (kept for reference)
    └── YYYY-MM-DD_<id>.md
```

## Proposal format

```markdown
# IMPROVEMENT-NNNN: <title>

Date: YYYY-MM-DD
Proposed by: <agent>
Status: PENDING | APPROVED | REJECTED | APPLIED

## Observed problem

<what was noticed — repeated failure, inefficiency, missing capability>

## Evidence

<supporting evidence — failure records, metrics, examples>

## Root cause

<why this problem exists>

## Proposed change

<what specifically should change>

## Affected agents/skills

<which agents or skills would be modified>

## Risks

<what could go wrong>

## Expected benefit

<what improvement this would produce>

## Verification plan

<how to verify the change works as intended>

## Approval

- [ ] Human review
- [ ] Impact assessment
- [ ] Rollback plan
```

## How proposals are generated

At the end of substantial work, the Orchestrator (or any agent) may create a
proposal when it detects:

- Repeated failures of the same type
- Inefficient workflows that waste agent resources
- Missing skills that would prevent a class of problems
- Missing tests that would catch regressions
- Documentation gaps that cause confusion
- Architecture problems that slow down development
- Poor agent delegation patterns

## How proposals are processed

1. Proposal created in `pending/`
2. Orchestrator presents to user at a natural stopping point
3. Human reviews and decides: APPROVE, REJECT, or MODIFY
4. If approved: implement the change, move to `applied/`
5. If rejected: move to `rejected/` with reason
6. If modified: create a new proposal with the modification

## Rules

- **Never** modify core agent behavior without approval
- **Never** modify the orchestrator's decision logic without approval
- **Never** add new agents without approval
- **Always** preserve backward compatibility
- **Always** include a rollback plan
- **Always** document what was changed and why
