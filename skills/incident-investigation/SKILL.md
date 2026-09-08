---
name: incident-investigation
description: Incident investigation — structured response to production or system incidents
version: "1.0"
owner: Detective
prerequisites: incident reported, system accessible
---

# Incident Investigation

## When to use this skill

- A production system is failing
- Users are reporting issues
- Monitoring alerts are firing

## Step-by-step procedure

### 1. Triage
- How severe is the incident?
- What is the current impact?
- Is it getting worse?

### 2. Stabilize
- Can we restore service quickly?
- Is there a safe rollback?
- What is the minimal fix?

### 3. Investigate
- Use systematic debugging methodology
- Collect evidence while the incident is live
- Note timeline of observations

### 4. Resolve
- Apply the fix
- Verify the fix works
- Monitor for regression

### 5. Review
- Document what happened
- Identify root cause
- Propose prevention measures
- Record in `memory/failures/`

## Common pitfalls

- Jumping to fix without understanding
- Not collecting evidence during the incident
- Blaming individuals instead of processes
- Not following up on prevention

## Exit criteria

- Service restored
- Root cause identified
- Prevention measures proposed
- Incident recorded in memory
