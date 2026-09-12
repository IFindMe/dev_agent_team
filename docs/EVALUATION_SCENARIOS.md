# Agent Team Evaluation Scenarios

Runtime evaluation scenarios for the adaptive, evidence-driven architecture.
Structural readiness is checked mechanically by
`scripts/test-agent-architecture.sh`; these scenarios evaluate **actual
behavior** in a live opencode session.

## How to run

1. Install the team (`./scripts/install.sh`), restart opencode, verify
   `opencode agent list` shows 14 agents.
2. Create or clone the fixture described for the scenario.
3. Invoke the orchestrator with the scenario's prompt.
4. Score the run using the rubric below. Record scores and notes in
   `AgentsReport/evaluation/<YYYY-MM-DD>_scenario-N.md`.
5. Do not interfere mid-run except where the scenario explicitly calls for it
   (e.g. introducing a tool failure). Interference neutralizes recovery metrics.

## Metrics

Score each metric 0–3 and record **evidence** (transcript actions, files
changed, commands run, tests executed):

| Metric | 0 (bad) | 3 (good) |
|--------|---------|----------|
| M1 success | goal not met | goal met and verified |
| M2 unnecessary work | files/agents/tools touched with no decision value | minimum sufficient work only |
| M3 repeated actions | same action retried blindly ≥3× | no repeated action without new information |
| M4 verification quality | claims accepted without evidence | independent verification with reproducible commands |
| M5 correct agent selection | wrong agent or agent called without purpose | correct agent(s), or no agent when self-service sufficed |
| M6 cost/context growth | context bloat, huge reports, many agents | small reports, cheap actions, low token growth |
| M7 recovery quality | failure loop or silent BLOCK | classification → different action → progress |

Pass/fail alone is insufficient: a run that passes tests after chaotic behavior
scores low on M2/M3/M6/M7.

## Scenarios

### S1 — Trivial one-file task
**Fixture:** any small repo with a typo in one file.
**Prompt:** "Fix the typo in `README.md` line 12."
**Expect:** no agent dispatches; direct inspect → edit → verify → report.
**Watch for:** unnecessary Explorer dispatch (M2), large report (M6).

### S2 — Medium multi-file task
**Fixture:** small codebase; rename a function used in 3 files.
**Prompt:** "Rename `compute` to `compute_total` across the codebase."
**Expect:** search (A2) → self or Builder edit → targeted verification (build/test).
**Watch for:** full-agent pipeline applied to a rename (M5), verification skipped (M4).

### S3 — Architecture-changing task
**Fixture:** codebase with a stable monolith boundary.
**Prompt:** "Split the X module into its own library."
**Expect:** estimate → Explorer evidence → Architect decision → Builder → Tester → Reviewer; `.opencode/architecture` updated.
**Watch for:** Builder touching architecture unasked (M5), no review (M4).

### S4 — Failing test investigation
**Fixture:** repo with one failing test that is genuinely broken (not a test bug).
**Prompt:** "Test `test_parse` fails — fix it."
**Expect:** Detective establishes root cause BEFORE Builder edits anything.
**Watch for:** Builder fixing without root cause (M5), symptom-only fix (M4).

### S5 — Unknown repository
**Fixture:** fresh clone with no `.opencode/`.
**Prompt:** "What does this project do and how do I run it?"
**Expect:** bootstrap `.opencode/` → read AGENTS.md/skills → Explorer if needed → concise answer.
**Watch for:** bootstrap skipped (M5), full-dump answer (M2).

### S6 — Repository with stale `.opencode`
**Fixture:** `.opencode/.bootstrap-meta` fingerprint stale (manifest changed) or a skill fact disproven.
**Prompt:** "Rebuild the package."
**Expect:** staleness detected → refresh/enrich → correct build command used → stale fact corrected by owner.
**Watch for:** acting on stale docs without checking (M4), no knowledge update (M5).

### S7 — Tool failure
**Fixture:** normal task but a command fails once for an environmental reason (e.g. missing binary).
**Prompt:** "Run the test suite."
**Expect:** classify failure (tool/environment) → verify prerequisites → different action or BLOCKED; NOT three identical retries.
**Watch for:** blind retry loop (M3/M7).

### S8 — Misleading hypothesis
**Fixture:** bug whose initial plausible cause is wrong (e.g. network timeout looks like a config bug).
**Prompt:** "Why does connect() fail?"
**Expect:** hypothesis → test → evidence contradicts → NEW plan/hypothesis.
**Watch for:** fixing the visible symptom without evidence (M4/M7).

### S9 — Task that should NOT require multiple agents
**Fixture:** any trivial doc/typo task in a known repo.
**Prompt:** "Add a one-line comment above function `foo`."
**Expect:** 0–1 agents max; direct edit; report.
**Watch for:** full pipeline (M5/M6).

### S10 — Task requiring re-planning
**Fixture:** requested change turns out much larger than described.
**Prompt:** "Add an option flag to the CLI" where the parser lacks option support.
**Expect:** estimate → expand scope with reason → architecture if needed → staged implementation. Record why scope expanded.
**Watch for:** ignoring the scope change (M7) or silently redesigning (M2).

### S11 — Handoff / context reset
**Fixture:** use the persisted-state mechanism: start a medium task, stop mid-way, resume next session.
**Prompt (resume):** "Continue the half-done refactor from AgentsReport/builder/…"
**Expect:** state record in AgentsReport used to resume without rediscovery.
**Watch for:** restarting from scratch (M2/M6), lost failed attempts (M7).

### S12 — Tests pass but implementation is incomplete
**Fixture:** a change that passes existing tests but misses a stated requirement (e.g. only one of two call sites updated).
**Prompt:** "Refactor logging to the new logger."
**Expect:** Tester writes/adjusts coverage to catch the gap, or Reviewer flags it; change is not accepted on green tests alone.
**Watch for:** lucky-pass acceptance on existing tests only (M4).

## Reporting template

```text
Scenario: S<n>
Status: COMPLETE | PARTIAL | BLOCKED
M1 success:          0-3   evidence:
M2 unnecessary work: 0-3   evidence:
M3 repeated actions: 0-3   evidence:
M4 verification:     0-3   evidence:
M5 agent selection:  0-3   evidence:
M6 cost/context:     0-3   evidence:
M7 recovery:         0-3   evidence:
Agents dispatched:   <list>
Tool calls approx:   <count>
Notes / weaknesses observed:
```

## When to run

- After any change to the agent definitions or the orchestration guidance
  (e.g. this upgrade), run at least S1, S4, S5, S7, S9, S11.
- Before a release/commit of the team package, run all 12.
- A regression in any metric vs. the previous score should be investigated
  before shipping.