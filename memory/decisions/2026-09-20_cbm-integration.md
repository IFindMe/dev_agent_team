# ADR: CBM Integration — 5 Capabilities Adapted from codebase-memory-mcp
Date: 2026-09-20
Status: accepted
Tags: cbm-integration, tooling, code-intelligence

## Purpose
Adapt 5 concepts from the DeusData/codebase-memory-mcp C-native code intelligence engine into bash/jq/markdown infrastructure for dev_agent_team.

## Context
Analysis of CBM revealed transferable patterns: ADR section splicing, impact analysis BFS, architecture overview generation, dead code detection, and session coordination. User approved all 5 for implementation.

## Decision
Implement all 5 capabilities as standalone bash scripts with skills and tests:
1. ADR Management (scripts/adr.sh) — section-level CRUD for markdown ADRs
2. Impact Analysis (scripts/impact.sh) — grep-based blast radius mapper
3. Architecture Overview (scripts/arch-overview.sh) — filesystem heuristic architecture generator
4. Dead Code Detection (scripts/deadcode.sh) — orphaned code finder
5. Session Coordination (scripts/sessions.sh) — agent session registry with locks

## Consequences
- 5 new scripts (~1800 lines total)
- 5 new skills (13→18 total)
- 5 new test suites (109 new assertions)
- test-all.sh updated with 5 new suites (8→13 total)
- All 14 agent prompts updated: skill count 13→18
- All 13 test suites pass (192 total checks)

## Alternatives
- Integrate CBM as MCP server (rejected: adds external dependency)
- Port CBM C code to bash (rejected: unnecessary complexity)
- Use Python for all tools (rejected: inconsistent with existing bash infrastructure)
