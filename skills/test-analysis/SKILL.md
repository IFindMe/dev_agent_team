---
name: test-analysis
description: Test analysis — evaluating test quality, coverage gaps, and test strategy
version: "1.0"
owner: Tester
prerequisites: test suite exists
---

# Test Analysis

## When to use this skill

- Evaluating test quality before accepting changes
- Identifying coverage gaps
- Designing test strategy for new features

## Core methodology

```text
EXAMINE TESTS → ASSESS COVERAGE → EVALUATE QUALITY → IDENTIFY GAPS → PRIORITIZE → RECOMMEND
```

## Analysis dimensions

### Coverage
- What code paths are exercised?
- What branches are tested?
- What error conditions are covered?

### Quality
- Do tests verify behavior (not implementation)?
- Are tests independent (no ordering dependencies)?
- Are tests deterministic (no flakiness)?
- Are assertions meaningful (not just "no crash")?

### Completeness
- Are edge cases tested?
- Are boundary conditions covered?
- Are error paths tested?
- Are integration points verified?

### Maintainability
- Are tests readable?
- Are tests well-organized?
- Are tests fast enough for the feedback loop?

## Common pitfalls

- Testing implementation details (breaks on refactor)
- Writing tests that always pass (no real verification)
- Missing the failure path (happy path only)
- Slow tests that discourage running them
- Flaky tests that erode confidence

## Exit criteria

- Coverage gaps identified with severity
- Test quality assessment complete
- Recommendations for improvement prioritized
