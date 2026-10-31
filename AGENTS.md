# Repository contribution instructions

This repository distributes OpenCode agent definitions and small supporting tools.

## Source of truth

- Agent prompts live in `agents/*.md`.
- Keep OpenCode V2 Markdown frontmatter current: use `permissions` rules with `action`, `resource`, and `effect`.
- Do not reintroduce legacy `permission`, `bash`, or `task` frontmatter keys.
- The Orchestrator is the only primary agent and the only agent allowed to launch named subagents.

## Validation

Run:

```sh
python3 scripts/validate.py
python3 -m unittest discover -s tests -v
```

Keep tests dependency-free and deterministic. Do not commit generated `.tasks/` state or `.opencode/reports/`.

## Security

Permission rules are defense in depth, not a sandbox. Never give read-only roles project edit permission. Keep external-directory access denied and secrets excluded from read permissions.
