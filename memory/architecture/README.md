# Current Architecture

This directory contains the current architectural state of the project, updated by Architect and Maintainer.

## Files

- `component-map.md` — current component relationships
- `constraints.md` — architectural constraints and rules
- `interfaces.md` — key interfaces and contracts

## Ownership

- **Architect** owns architecture decisions and boundary definitions
- **Maintainer** audits architecture against reality and corrects drift
- **Reviewer** verifies architecture documentation is consistent with code

## Lifecycle

Architecture records are updated when:
- New components or boundaries are established
- Interfaces change
- Constraints are added or relaxed
- Architecture decisions are made (link from `decisions/`)

Architecture records are NOT updated for:
- Task-specific implementation details
- Temporary workarounds
- Feature-specific code paths
