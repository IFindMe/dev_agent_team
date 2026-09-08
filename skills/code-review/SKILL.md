---
name: code-review
description: Code review process — systematic review of changes for quality, correctness, and maintainability
version: "1.0"
owner: Reviewer
prerequisites: implementation completed, tests passing
---

# Code Review

## When to use this skill

- Before accepting a completed implementation
- When reviewing a pull request or change set
- When verifying scope compliance

## Core methodology

```text
READ CHANGES → CHECK CORRECTNESS → CHECK SCOPE → CHECK TESTS → CHECK DESIGN → CHECK SAFETY → VERDICT
```

## Review checklist

### Correctness
- [ ] Does the code do what it claims?
- [ ] Does it handle edge cases?
- [ ] Are error paths handled?
- [ ] Are there off-by-one errors?

### Scope compliance
- [ ] Does the change match the approved scope?
- [ ] Is there unauthorized scope expansion?
- [ ] Are only the files that should change actually changed?

### Tests
- [ ] Do tests verify the behavior (not implementation)?
- [ ] Are edge cases tested?
- [ ] Is there regression test coverage?
- [ ] Do tests pass?

### Design
- [ ] Is the code consistent with existing patterns?
- [ ] Are interfaces clean and minimal?
- [ ] Is there unnecessary complexity?
- [ ] Would a future developer understand this?

### Safety
- [ ] Are there security implications?
- [ ] Are there performance implications?
- [ ] Are there race conditions?
- [ ] Are secrets or credentials handled safely?

### Documentation
- [ ] Are public APIs documented?
- [ ] Are non-obvious decisions explained?
- [ ] Is the change self-documenting?

## Common pitfalls

- Rubber-stamping (approving without reading)
- Nitpicking style when correctness matters
- Not testing the change locally
- Accepting "it works" without evidence
- Missing scope creep

## Exit criteria

- All checklist items addressed (pass or explain why not)
- Findings categorized: BLOCKING / REQUIRED / SUGGESTED / NOTE
- Verdict: ACCEPT / ACCEPT_WITH_NOTES / CHANGES_REQUIRED / BLOCKED
