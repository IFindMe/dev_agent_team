# Prompt-based install

If you are already inside an opencode session, you do not need to touch a
terminal yourself: paste the prompt below to the primary agent (e.g.
`orchestrator`) and it will fetch this repository, run the installer, and
verify the result for you.

Paste-ready prompt:

```text
Install my agent team from the dev_agent_team repo:
1. Clone git@gitea.skink-platy.ts.net:admin/dev_agent_team.git into ~/projects/dev_agent_team.
2. Run bash ~/projects/dev_agent_team/scripts/install.sh to copy the 12 agents into ~/.config/opencode/agents (existing files are backed up automatically).
3. Verify by running `opencode agent list` and confirm exactly 12 agents are registered.
4. Report which agents were new and whether anything failed.
```
