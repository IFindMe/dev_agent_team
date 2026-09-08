---
name: tdd
description: Test-Driven Development methodology — write tests first, implement to pass, refactor
version: "1.0"
owner: Builder + Tester
prerequisites: test framework identified, build system working
---

# Test-Driven Development

## When to use this skill

- Implementing new functionality where correctness can be verified
- Bug fixes where a regression test should exist
- Any change where the expected behavior is well-defined

## Core methodology

```text
RED    → write a failing test that captures the requirement
GREEN  → implement the minimum code to make the test pass
REFACTOR → improve the code while keeping all tests green
```

## Step-by-step procedure

### 1. Understand the requirement
- What behavior is expected?
- What inputs produce what outputs?
- What edge cases exist?
- What error conditions should be handled?

### 2. Write the test (RED)
- Write the smallest test that captures one aspect of the requirement
- Verify the test fails for the right reason (not a syntax error)
- Run the test to confirm it fails

### 3. Implement (GREEN)
- Write the minimum code to make the test pass
- Do not add behavior not captured by a test
- Run the test to confirm it passes

### 4. Verify (REFACTOR)
- Run the full test suite (not just the new test)
- Refactor if needed: extract methods, rename for clarity, remove duplication
- Verify tests still pass after each refactor step

### 5. Repeat
- Return to step 1 for the next aspect of the requirement
- Stop when all aspects are covered and tests pass

## Common pitfalls

- Writing tests after implementation (loses the design benefit)
- Writing too many tests at once (harder to isolate failures)
- Testing implementation details instead of behavior
- Skipping the refactor step (technical debt accumulates)
- Not running the full suite after changes

## Evidence requirements

- Test file with the new test(s)
- Test output showing RED → GREEN progression
- Full suite passing after completion

## Exit criteria

- All new tests pass
- Full existing suite passes
- Tests capture the behavior, not the implementation
- Each test is independently runnable
