---
name: verification-loop
description: Pre-PR verification methodology — ordered build, types, lint, tests with coverage, security grep, and diff review producing a VERIFICATION REPORT with a READY or NOT READY verdict
version: "1.1"
owner: Tester
prerequisites: working tree with changes to verify, shell access with bash, git, grep, jq, and python3 standard library
---

# Verification Loop

## When to use this skill

- After completing a feature or significant code change
- Before opening a pull request
- After a refactoring pass, before claiming the work is complete
- When quality gates must be demonstrated with evidence, not asserted

## Core methodology

```text
BUILD → TYPES → LINT → TESTS+COVERAGE → SECURITY-GREP → DIFF-REVIEW → REPORT + VERDICT
```

Run the six phases in order. A FAIL in an early phase stops the loop: fix the
issue, then restart from phase 1. Each phase records PASS, FAIL, or SKIP with a
one-line note. Every SKIP must state its condition; silent skips are not
allowed.

This skill is an advisory procedure only. It installs nothing, enforces
nothing, and adds no dependencies: it uses only the shell and tools already
present (bash, git, grep, jq, python3 standard library) plus the repo's own
documented scripts.

## Step-by-step procedure

### Phase 1: Build verification

Purpose: prove the changed tree still builds — or establish that the repo
defines no build step.

```bash
git status --short | head -20
ls Makefile package.json pyproject.toml go.mod Cargo.toml 2>/dev/null
# If the repo documents a build entrypoint, run it, e.g.:
# bash scripts/build.sh 2>&1 | tail -20
```

- PASS: the documented build succeeds.
- SKIP with note when: the repo documents no build step → record
  `Build: SKIP (no build step documented in repo)` and continue.
- FAIL stops the loop: fix the build before continuing.

### Phase 2: Type check

Purpose: surface type errors early. Many repos here have no single typecheck;
never invent one.

```bash
ls tsconfig.json mypy.ini setup.cfg 2>/dev/null
# If the repo configures a checker, run the repo's documented command, e.g.:
# bash scripts/typecheck.sh 2>&1 | head -30
# Portable stdlib-only fallback for Python trees:
python3 -m compileall -q <changed-dir> 2>&1 | head -20
```

- PASS: checker clean (or fallback clean).
- SKIP with note when: no checker is configured and no compiled language is
  present → record `Types: SKIP (no typecheck configured)` and continue.
- FAIL: reported errors block progress until fixed or explicitly waived with a
  written reason.

### Phase 3: Lint check

Purpose: catch whitespace errors and stray markers; prefer the repo's own
entrypoint over generic probes.

```bash
# If the repo documents a lint entrypoint, run it, e.g.:
# bash scripts/lint.sh 2>&1 | head -30
# Portable fallback (no new tools installed):
git diff --check
git diff --name-only | head -30
# git diff --check is tracked-only: also cover untracked shell files
# (never stash to check them — read directly from git status):
git status --short | awk '$1 == "??" {print $2}' | grep '\.sh$' | head -20
# For each untracked *.sh listed above, syntax-check it, e.g.:
# bash -n <untracked-file> 2>&1 | head -20
# And whitespace-scan untracked text paths, e.g.:
# grep -rn --exclude-dir=.git '[[:blank:]]$' <untracked-file-or-dir> 2>/dev/null | head -20
```

- PASS: entrypoint clean (or fallback clean on BOTH the tracked diff AND
  every untracked `*.sh` in scope). When untracked paths exist, name them in
  the PASS note; a PASS that checked tracked files only must carry the
  explicit caveat `untracked not covered`.
- SKIP with note when: the repo has no lint entrypoint AND the tree has no
  text changes to check → record `Lint: SKIP (no lint entrypoint, no text
  changes)` and continue.
- FAIL: fix or explicitly waive with reason before continuing.

### Phase 4: Test suite with coverage

Purpose: prove behavior with the repo's own suite — the canonical test
entrypoint for the repo under test (for example, a `test-all.sh` equivalent
where one exists) — plus coverage where the repo provides it.

```bash
# Discover candidate suites first, then run the aggregator:
ls scripts/test-*.sh 2>/dev/null
# Compare against what the aggregator actually invokes, e.g.:
# grep -o 'test-[A-Za-z0-9_-]*' scripts/test-all.sh | sort -u
# Run the repo's own suite, e.g.:
bash scripts/test-all.sh 2>&1 | tail -30
# Coverage where the repo provides it, e.g.:
# bash scripts/coverage.sh 2>&1 | tail -20
```

Confirm the changed area is exercised by at least one suite: map each
in-scope change to the suite(s) covering it. Name any blind spot (a changed
area no suite exercises, or a candidate `scripts/test-*.sh` the aggregator
never invokes) in the Tests line note and as an entry in Issues to Fix.

Record: total tests, passed, failed, skipped, and coverage percent (or
`coverage n/a` when the repo offers none).

- PASS: suite green (and coverage meets the repo's stated threshold, if any).
- SKIP with note when: the repo has no test suite → record `Tests: SKIP (no
  test suite found)`. A SKIP here forces a NOT READY verdict unless the task
  scope explicitly excludes tests — record that justification.
- FAIL stops the loop: fix, then restart from phase 1.

### Phase 5: Security grep

Purpose: catch leaked secrets and credential files with portable shell tools
only. Review every finding; do not bulk-ignore.

```bash
grep -rniE 'password|passwd|secret|api[_-]?key|token' --exclude-dir=.git . 2>/dev/null | grep -viE 'placeholder|example' | head -10
grep -rn 'BEGIN .*PRIVATE KEY' --exclude-dir=.git . 2>/dev/null | head -10
git diff --name-only | head -30
```

- PASS: no findings, or every finding reviewed and explained in the report.
- SKIP with note when: the change touches docs only, with no code or config
  → record `Security: SKIP (docs-only change, no code or config touched)`.
- FAIL: any unreviewed finding blocks READY.

### Phase 6: Diff review

Purpose: confirm the diff contains exactly the intended change, nothing more.

```bash
git status --short
git diff --stat
git diff --name-only
# git diff shows tracked changes only: ?? lines in git status are invisible
# to both git diff commands above. Review every in-scope untracked path
# directly, e.g.:
# wc -l <untracked-file> 2>/dev/null
# sha256sum <untracked-file> 2>/dev/null
# ls -R <untracked-dir> 2>/dev/null | head -30
```

Read every changed file and check for unintended changes, missing error
handling, and untested edge cases. Interpret `git status --short` first:
`M` = tracked modification (covered by git diff), `??` = untracked path
(never covered by git diff — spot-check each one the change owns with a
line count and hash above so drift beside the tracked diff is visible).

- PASS: diff matches intent; every file reviewed.
- SKIP is not available for this phase: there is always a diff to review. An
  empty diff means there is nothing to verify — say so and stop.
- FAIL: unrelated files in the diff → split the change and restart the loop.

## Output contract

After running all phases, produce a verification report:

```text
VERIFICATION REPORT
===================

Build:     [PASS/FAIL/SKIP + one-line note]
Types:     [PASS/FAIL/SKIP + one-line note]
Lint:      [PASS/FAIL/SKIP + one-line note]
Tests:     [PASS/FAIL/SKIP] (X/Y passed, Z skipped, C% coverage or coverage n/a)
Security:  [PASS/FAIL/SKIP] (X findings, all reviewed / none)
Diff:      [X files changed, Y insertions(+), Z deletions(-)]

Overall:   [READY / NOT READY] for PR

Issues to Fix:
1. ...
2. ...

Skips (with justification):
- ...
```

Verdict semantics:

- READY: every applicable phase PASS; any SKIP carries a written
  justification; zero unresolved FAILs; all security findings reviewed; diff
  contains only intended changes.
- NOT READY: any FAIL; or a Tests SKIP without scope justification; or any
  unreviewed security finding; or unrelated changes in the diff.
- After NOT READY: list Issues to Fix in order, fix them, and restart the loop
  from phase 1.

## Common pitfalls

- Running phases out of order (a green test suite means little if the build
  entrypoint itself is broken)
- Silent skips that hide an inapplicable phase instead of justifying it
- Treating the portable fallbacks as a substitute for the repo's own
  suite — fallbacks are a floor, not a ceiling
- Bulk-ignoring security-grep findings instead of reviewing each one
- Verifying a diff that mixes unrelated changes (split first, verify after)
- Claiming READY with a FAIL outstanding

## Evidence requirements

- The VERIFICATION REPORT block with all six phase lines plus the verdict
- Phase outputs cited as command plus result (expected vs actual), not pasted
  in full
- Every SKIP accompanied by its one-line justification
- Every FAIL accompanied by its entry in Issues to Fix

## Exit criteria

- All six phases recorded as PASS or justified SKIP
- VERIFICATION REPORT emitted with a READY or NOT READY verdict
- READY claimed only when the verdict semantics above are fully met
- No new dependencies installed and no enforcement mechanism added
