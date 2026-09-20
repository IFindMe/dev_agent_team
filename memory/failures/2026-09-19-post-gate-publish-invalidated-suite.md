# Failure: post-gate publish to a gate fixture invalidated the suite

Context: Agora Phase 1 gate ACCEPT recorded on a 3-contribution seed; orchestrator then published 2 legitimate closure contributions to the same live seed before the suite was hermetic.
Failure: `scripts/test-agora.sh` fell 45/45 → 43/45 (T15 S=21 vs S=2, T17 tip absent); trial verdict NOT READY; unplanned rework (tasks 06-10) plus a `state.sh` bug fix.
Root cause: coordination, not product — gate fixtures were live shared state; the DAG's append-only growth (D1, by design) collided with value-pinned assertions and with a verdict scoped to a frozen seed.
Rule: freeze gate fixtures at verdict time; route any post-gate append through re-verdict (Reviewer gate-reopen conditions); require hermetic `/tmp` fixtures for value assertions (see lessons/testagora-lesson.md). Publishing to the shared DAG stays encouraged — but never to a fixture a green suite pins.
Relevance: any future gate whose evidence reads live append-only state (DAG, events.jsonl, tasks.json counts).
