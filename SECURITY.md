# Security model

## Supported configuration format

This package targets OpenCode V2 agent Markdown frontmatter:

- `permissions` is an ordered list of `action`, `resource`, and `effect` rules.
- The first rule denies all actions.
- Specific capabilities are added later.
- Later matching rules take precedence, so ordering is security-sensitive.

Do not translate these files back to legacy singular `permission` maps or legacy `bash`/`task` actions.

References:

- [OpenCode V2 agents](https://opencode.ai/v2/docs/agents)
- [OpenCode V2 permissions](https://dev.opencode.ai/v2/docs/permissions/)

## Role policy

| Role | Project reads | Project edits | Shell | Subagents |
|---|---|---|---|---|
| Orchestrator | Denied | Denied | Denied | Named specialists only; may ask the user clarifying questions |
| Explorer | Allowed; secrets denied | Report directory only | Approval-gated; read-only Git commands allowlisted | Denied |
| Detective | Allowed; secrets denied | Report directory only | Approval-gated; read-only Git commands allowlisted | Denied |
| Architect | Allowed; secrets denied | Report directory only | Approval-gated; read-only Git commands allowlisted | Denied |
| Designer | Allowed; secrets denied | Report directory only | Denied | Denied |
| Builder | Allowed; secrets denied | Approval-gated | Approval-gated | Denied |
| Tester | Allowed; secrets denied | Test paths and reports | Approval-gated | Denied |
| Reviewer | Allowed; secrets denied | Report directory only | Approval-gated; read-only Git commands allowlisted | Denied |
| Toolsmith | Allowed; secrets denied | Tooling, tests, CI paths | Approval-gated | Denied |
| Maintainer | Allowed; secrets denied | Approval-gated | Approval-gated | Denied |
| Writer | Allowed; secrets denied | Documentation paths | Denied | Denied |
| Tracker | Allowed; secrets denied | Task-state and report paths | Task-state helper; other shell commands approval-gated | Denied |
| Philosopher | No general repository access | `philosophy.md` and reports | Denied | Denied; may ask the user questions |
| Workflow Architect | Allowed; secrets denied | Report directory only | Denied | Denied |

## Important limitations

1. **Prompts are not enforcement.** Role text explains intent; OpenCode permissions constrain available actions. Keep both aligned.
2. **Permissions are not an OS sandbox.** Run agents with an unprivileged account and restrict the filesystem/network at the OS or container boundary for untrusted repositories.
3. **Shell commands are powerful.** Approval-gated shell access must be reviewed. Avoid blanket shell approvals for agents that only need reads.
4. **External paths are denied.** Tracker has one narrow exception for the default global task-state helper under `~/.config/opencode/scripts/`; do not add broad external-directory access to make a workflow convenient.
5. **Secrets remain out of scope.** Environment files are denied to read/edit tools. Do not print secrets through shell commands or include them in reports.
6. **Subagents have their own permissions.** Do not assume a restrictive parent automatically constrains a child; every specialist has its own explicit policy.
7. **User approvals can broaden access.** Review any persistent/“always” approval carefully; restart or inspect the OpenCode session configuration after changing trust policy.
8. **Review is not a substitute for tests.** Run deterministic checks and an independent review before accepting implementation changes.

## Reporting vulnerabilities

Do not include credentials, tokens, private keys, or personal data in GitHub issues. Report security concerns privately to the repository owner.
