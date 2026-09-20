# agora/ — shared append-only contribution DAG (Phase 1)

Parallel agent sessions share one DAG so search is not duplicated and later
work builds on earlier work. Git history of `contributions.jsonl` IS the
transport (light path only — no bundle, no service, no daemon).

> **Views are derived, JSONL is truth.** `agora.sh analyze` output is a
> read-only projection. If a view looks stale or surprising, re-read the log.

## Schema

One JSON object per line in `contributions.jsonl`:

```json
{"id":"<64-hex sha256>","parents":["<id>",...],"type":"<enum>",
 "title":"<short claim>","body_ref":"<repo path>",
 "tags":["<k>",...],"created_by":"<actor>","ts":"<UTC ISO-8601>"}
```

- `id` = sha256 of the canonical payload line
  `jq -cS '{parents,type,title,body_ref,tags,created_by,ts}'`.
  `verify` recomputes every id — **a committed line is never edited**;
  a correction is a NEW line whose `parents[]` cites the old one.
- `type` enum: `setup | result | insight | hypothesis | report |
  verification | endorsed`.
  `wip` is **rejected** — in-progress pointers live in
  `.tasks/<goal>/tasks.json` status only, never in the DAG.
- `type=verification` MUST carry exactly one weight tag:
  `+20` (accept), `+10` (weak-accept), `-20` (refute).
  `endorsed` carries weight 0. All other types weight 1 per citing child.
- `body_ref` is a repo-relative path pointer (light path). `AgentsReport/`
  bodies are same-worktree-visible; cross-machine durability requires a
  committed mirror (Phase 2 rule — not this directory's problem yet).

## Publish discipline

```sh
scripts/agora.sh publish --type <type> --title <title> \
  [--body-ref <path>] [--tags <csv>] [--parents <csv>] [--by <actor>]
```

1. Before writing, run `scripts/agora.sh log` / `analyze` to find candidate
   parents; every finding cites `builds-on: <ids>` in its report header.
2. One append per contribution, via the tool (atomic under lock).
   There are NO edit/delete subcommands — by design, not omission.
3. On push conflict: `git pull --rebase` and retry (the line is
   content-addressed, so a rebase never changes its id). The Orchestrator
   serializes parallel publishes.

## Views (all read-only)

```sh
scripts/agora.sh analyze leaders | most-built-on | leaves | underexplored \
  | unverified | contested | open-hypotheses | clusters
scripts/agora.sh verify   # schema + id/no-mutation + parents-integrity
```

| View | Definition |
|---|---|
| leaders | top S(u): weighted citing-children count, self-citation excluded |
| most-built-on | highest children count (in-degree) |
| leaves | zero children (research frontier) |
| underexplored | ≤1 child, oldest first |
| unverified | non-verification type with no verification child |
| contested | has a −20 verification child |
| open-hypotheses | hypothesis with no verification child |
| clusters | shared-tag groups (keyword overlap — NOT embeddings) |

## Scoring (read-only, advisory — Phase 1)

- S(u) = Σ weights of DIRECT citing children, excluding self-citation
  (same author as the cited node).
- U(v) = S(v)/n(v) + C·√(ln(N+1)/n(v)), n(v) = children+1, N = DAG size.
- Constants are **TUNABLE** and live in exactly one place: the `TUNABLE`
  block at the top of `scripts/agora.sh`. They are provisional at this
  repo's scale — revisit from pilot duplication-rate data.
- No enforcement: scores never block or reroute work in Phase 1.
  Enforcement needs an `improvements/pending/` proposal + human approval.

## Files

- `contributions.jsonl` — source of truth (committed).
- `index.db` (if ever derived) and `*.tmp` — derived/scratch, gitignored,
  never trusted over the JSONL. (Maintainer owns `.gitignore`.)
