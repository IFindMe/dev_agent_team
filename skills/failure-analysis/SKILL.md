---
name: failure-analysis
description: Failure analysis methodology — analyzing system failures to identify patterns and prevent recurrence
version: "1.0"
owner: Detective
prerequisites: failure observed, evidence available
---

# Failure Analysis

## When to use this skill

- A failure has occurred and needs to be understood
- Recurring failures need pattern analysis
- Post-incident review is needed

## Step-by-step procedure

### 1. Collect evidence
- Gather all available evidence: logs, error messages, stack traces
- Note the timeline: when did it start, what changed
- Identify affected components and users

### 2. Classify the failure
- **Type**: tool / environment / assumption / plan / implementation / test / coordination
- **Severity**: critical / high / medium / low
- **Scope**: isolated / widespread
- **Frequency**: one-time / recurring

### 3. Root cause analysis
- Use the systematic debugging skill for individual failures
- For patterns: look across multiple failure records
- Ask: "What condition must be true for this failure to occur?"

### 4. Impact assessment
- What was the actual impact?
- What was the potential impact?
- Were there cascading effects?

### 5. Resolution
- How was it resolved (or is it still open)?
- Was the resolution verified?
- Are there residual risks?

### 6. Prevention
- What prevents this specific failure from recurring?
- What prevents the class of failures from recurring?
- Should a Toolsmith safeguard be created?
- Should a test be added?

## Common pitfalls

- Stopping at the symptom (not the cause)
- Blaming individuals instead of processes
- Documenting the fix without documenting the prevention
- Not checking for similar patterns elsewhere

## Evidence requirements

- Complete failure record in `memory/failures/`
- Root cause with evidence
- Prevention measures with verification

## Exit criteria

- Root cause identified
- Resolution verified
- Prevention documented
- Related failures checked for patterns
