Append the block below to `~/.codex/AGENTS.md` (applies to all projects) or to a project's `AGENTS.md` so the Codex main agent routes matching tasks through native delegation. Install the skill first with `bash ./install-codex.sh`.

```markdown
## Codex main agent delegation

For tasks that warrant delegation (reading code to understand it, debugging, implementation, review), the main agent first loads `~/.codex/skills/codex-director/SKILL.md` and follows it: write the brief, dispatch a complete task, verify the result, make the trade-offs, and finish delivery. Handle simple tasks and human-facing writing directly. A subagent that receives a brief from its parent acts as an executor and spawns further agents only when the parent explicitly assigns more delegation.

Dispatch through native `collaboration.spawn_agent` with `fork_turns: "none"` and a self-contained brief naming the directory, scope, context, and acceptance criteria. Run independent tasks in parallel within the host's concurrency limit; inherit the current model and reasoning settings by default. Give parallel writers isolated worktrees or directories.

Use `send_message` to add facts or decisions to a running agent; use `followup_task` for further work on the same problem, which also starts an idle agent's next turn. When current execution must stop before changing direction, `interrupt_agent` first, inspect existing changes, then assign the follow-up. Use `wait_agent` to wait for messages and `list_agents` to check status; after 15 minutes without progress, check liveness and blockers. Keep the same agent for the same problem; use a fresh agent for independent review.

Check a subagent's conclusions against the original evidence before adopting them; the main agent forwards cross-task facts, integrates changes, runs the required focused checks, and reports. Read, modify, commit, push, and deploy permissions follow the user's authorization; when information or authorization is missing, report it instead of inferring it.
```
