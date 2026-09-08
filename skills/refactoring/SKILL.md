---
name: refactoring
description: Refactoring principles — improving code structure without changing behavior
version: "1.0"
owner: Builder + Maintainer
prerequisites: tests exist and pass, behavior is well-understood
---

# Refactoring

## When to use this skill

- Code works but is hard to understand or maintain
- Duplication exists that should be extracted
- Naming is unclear or misleading
- Structure doesn't match the conceptual model

## Core principle

**Refactoring changes structure, not behavior.** If you don't have tests, write
them first. If you can't verify behavior is preserved, don't refactor.

## Step-by-step procedure

### 1. Verify baseline
- Run the full test suite
- Confirm all tests pass
- Note the test output (baseline for comparison)

### 2. Identify the refactor
- What specific structural improvement?
- What is the expected benefit?
- Is this the smallest useful refactor?

### 3. Make the change
- One small step at a time
- Run tests after each step
- If tests fail, revert and try a smaller step

### 4. Verify
- Run the full test suite again
- Compare output to baseline
- Verify no behavior change

### 5. Document
- Note what was refactored and why
- Update relevant documentation if public interfaces changed

## Common pitfalls

- Refactoring while fixing a bug (mixes two changes)
- Not having tests before refactoring
- Making large changes in one step
- Renaming things that don't need renaming
- "While I'm here" scope creep

## Exit criteria

- Full test suite passes
- No behavior change (same inputs, same outputs)
- Code is clearer/simpler than before
- Change is small enough to review
