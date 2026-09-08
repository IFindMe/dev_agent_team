---
name: systematic-debugging
description: Systematic debugging methodology — hypothesis-driven root cause investigation
version: "1.0"
owner: Detective
prerequisites: symptom observed, reproducible failure available
---

# Systematic Debugging

## When to use this skill

- A test fails, a feature breaks, or behavior diverges from expectation
- The root cause is not immediately obvious
- Multiple possible causes exist

## Core methodology

```text
SYMPTOM → OBSERVE → HYPOTHESIZE → TEST → TRACE → ELIMINATE → ROOT CAUSE
```

## Step-by-step procedure

### 1. Reproduce the symptom
- Confirm you can trigger the failure reliably
- Record the exact command, input, and output
- Note the environment (OS, versions, state)

### 2. Observe the evidence
- Read error messages carefully (every word matters)
- Check logs, stack traces, and output
- Note what changed since the last working state

### 3. Form hypotheses
- List possible causes (aim for 3-5)
- Rank by likelihood based on evidence
- For each hypothesis: what would be true if this were the cause?

### 4. Test hypotheses
- Design the cheapest test for the most likely hypothesis
- Use binary elimination: each test should rule out at least one hypothesis
- Record what you actually observed vs. what you expected

### 5. Trace the failure
- Follow the execution path from symptom to cause
- Add strategic print/log statements if needed
- Narrow down: which component, which function, which line?

### 6. Eliminate alternatives
- Explicitly state why other hypotheses are ruled out
- Document the evidence for each elimination

### 7. Establish root cause
- State the root cause with confidence level (high/medium/low)
- Provide supporting evidence (file:line, command output)
- Identify what conditions make this cause trigger

## Common pitfalls

- Fixing the symptom without understanding the cause
- Jumping to the most obvious hypothesis without testing it
- Changing multiple things at once (can't isolate what fixed it)
- Accepting "it works now" without understanding why
- Not recording what was eliminated

## Evidence requirements

- Reproduction steps
- Hypotheses with evidence for/against
- Root cause statement with confidence level
- Eliminated alternatives with reasoning

## Exit criteria

- Root cause identified with evidence
- Alternative hypotheses eliminated with reasoning
- Confidence level stated (high/medium/low)
- Report handed off to appropriate agent for resolution
