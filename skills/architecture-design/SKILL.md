---
name: architecture-design
description: Architecture decision process — structured approach to system design decisions
version: "1.0"
owner: Architect
prerequisites: requirements understood, constraints identified
---

# Architecture Design

## When to use this skill

- Deciding system boundaries, interfaces, or component ownership
- Evaluating architectural alternatives
- Establishing new patterns or constraints

## Core methodology

```text
UNDERSTAND → IDENTIFY DECISION → GENERATE OPTIONS → EVALUATE → DECIDE → RECORD
```

## Step-by-step procedure

### 1. Understand the context
- What problem are we solving?
- What are the constraints (technical, organizational, time)?
- What existing architecture does this interact with?

### 2. Identify the decision
- What exactly needs to be decided?
- What are the boundaries of this decision?
- Who are the stakeholders?

### 3. Generate options
- Aim for 2-4 concrete options
- Each option should be distinct (not variations of the same idea)
- For each: what does it optimize for? What does it sacrifice?

### 4. Evaluate options
For each option, assess:
- **Fit**: does it solve the stated problem?
- **Complexity**: how much does it add?
- **Reversibility**: how hard is it to change later?
- **Risk**: what could go wrong?
- **Evidence**: what supports this choice?

### 5. Decide
- Choose one option with clear rationale
- State what is explicitly out of scope
- Identify what would make you revisit this decision

### 6. Record
- Write an ADR in `memory/decisions/`
- Update `memory/architecture/` if boundaries change
- Link to related decisions

## Common pitfalls

- Deciding without evidence (opinion-driven design)
- Over-architecting for imagined future needs
- Not recording the decision (lost institutional knowledge)
- Ignoring existing patterns (inconsistency)
- Making reversible decisions with irreversible processes

## Evidence requirements

- Problem statement with constraints
- Options considered with trade-offs
- Decision rationale
- Recording in ADR format

## Exit criteria

- Decision made and recorded
- Alternatives documented with rationale
- Impact on existing architecture assessed
- Stakeholders can find the decision
