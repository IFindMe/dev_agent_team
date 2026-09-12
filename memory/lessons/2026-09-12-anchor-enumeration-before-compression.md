# Lesson-0001: Enumerate ALL byte-asserted anchors across ALL test suites before compressing agents/*.md

Date: 2026-09-12
Author: orchestrator
Context: Semantic compression of agents/orchestrator.md (66,782 → 54,932 chars, behavior preserved)
Recurring: yes (any future compression of agents/*.md)

## What was learned

When compressing or extracting content from any `agents/*.md` prompt, the compression brief must
enumerate every `grep -qF` / byte-exact string asserted against that file across **ALL** test
suites — not only the suites the brief happens to name. In this task the Architect's anchor matrix
covered test-agent-architecture T01–T09/T13–T15/T17, test-integration I06–I08/I11/I12, memory
T08/T09, repo T05 — but omitted test-path-resolution T01's canonical runtime sentence, which is
asserted against `agents/*.md` by a different suite. The compression removed the sentence's
second/third clauses to docs/OPERATIONS_REFERENCE.md, leaving only the first clause, and
`test-path-resolution T01` failed (suite went 7/8). Tester caught it; the fix restored the full
byte-exact sentence.

## Application

- Before any compression of a prompt file: run `grep -rn 'grep.*agents\|-qF' scripts/test-*.sh`
  (and inspect each suite's anchor list) to build the full byte-string inventory — every string any
  suite asserts must survive verbatim in the compressed file or remain reachable exactly as asserted.
- Include `test-path-resolution`, `test-install`, `test-runtime` in the inventory even when the
  compression brief names only "the document suites".
- Verify `test-path-resolution T01` (and the full `scripts/test-all.sh`) green pre-commit.

## Evidence

- Failure record: memory/failures/2026-09-12-path-resolution-t01-anchor-gap.md (now closed)
- scripts/test-path-resolution.sh T01 greps agents/*.md for the full canonical runtime sentence
- scripts/test-agent-architecture.sh asserts 62 anchors; compression preserved all 67/67 byte-asserted
  strings; `bash scripts/test-all.sh` → 8/8 PASS (105 checks)