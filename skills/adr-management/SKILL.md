---
name: adr-management
description: Architecture Decision Record management with section-level CRUD and cross-references
version: "1.0"
owner: Toolsmith
prerequisites: memory/decisions/ directory exists
---

# ADR Management Skill

## When to use this skill

- Recording architectural decisions for traceability
- Querying past decisions and their rationale
- Linking decisions that supersede or depend on each other
- Validating ADR completeness before acceptance
- Exporting ADRs for machine consumption or reporting

## Core methodology

```text
UNDERSTAND → CREATE → POPULATE → REVIEW → LINK → MAINTAIN
```

ADR files live in `memory/decisions/` as individual markdown files (`ADR-<id>.md`).
Each ADR has fixed sections. Section-level splicing replaces the body of one
section without touching others.

## Step-by-step procedure

### 1. Understand
- What decision needs recording?
- What context and alternatives exist?
- Is there a prior ADR this supersedes?

### 2. Create
- Generate a unique `<id>` (typically 0001, 0002, ...)
- Set initial status to `proposed`
- Add relevant tags for discoverability

### 3. Populate
- Fill each section with substantive content
- `Purpose`: why this decision was made
- `Context`: what situation required this decision
- `Decision`: what was decided
- `Consequences`: what follows from this decision
- `Alternatives`: what else was considered
- `References`: files, links, related ADRs

### 4. Review
- Validate all required sections are present (Purpose, Decision, Consequences)
- Ensure status reflects the actual state
- Check tags are consistent

### 5. Link
- If this ADR supersedes a prior one, use `adr.sh supersedes`
- Both files are updated: old gets `Superseded-by`, new gets `Supersedes`
- Cross-reference via tags for related ADRs

### 6. Maintain
- Update status as the decision evolves (proposed → accepted → deprecated)
- Use `set` to splice section bodies when context changes
- Periodic `validate` to ensure completeness

## CLI Reference

```bash
scripts/adr.sh create <id> --title "..." [--status proposed] [--tags "tag1,tag2"]
scripts/adr.sh get <id> [--section <name>]
scripts/adr.sh set <id> <section> --body "text"
scripts/adr.sh set <id> <section> --body-ref <file>
scripts/adr.sh list [--status <status>] [--tag <tag>]
scripts/adr.sh search <query>
scripts/adr.sh supersedes <old-id> <new-id>
scripts/adr.sh validate <id>
scripts/adr.sh export
```

## Common pitfalls

- Creating ADRs without filling required sections (use `validate` first)
- Forgetting to update status when a decision is accepted
- Not linking superseded ADRs (leads to stale decisions)
- Using IDs that conflict with existing ADRs
- Not tagging ADRs (makes search harder)

## Evidence requirements

- ADR file exists in `memory/decisions/`
- All required sections are populated
- Status matches actual decision state
- Cross-references are bidirectional (supersedes + superseded-by)

## Exit criteria

- ADR created with all required sections
- Status is accurate
- Tags are meaningful
- Cross-references are bidirectional
- `validate` passes with no MISSING sections
