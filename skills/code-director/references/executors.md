# Executors other than Codex

Use Antigravity (`agy`) by default for all frontend work; it specializes in frontend design and implementation. Other non-Codex executors are selected when the user names one. Set `executor` on `mcp__codex__dispatch` (the `EXECUTOR:` header on the Bash path); `executor` and `model` are passed through as written.

| `executor` | Agent | Extra fields |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `executor_mode` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP (`dsh --profile acp`); executable from `executor_command`, `$CODEX_DIRECTOR_DSH_COMMAND`, then PATH | `executor_args` (override the launch arguments), `executor_permissions` (`allow-once` or `ask`) |
| `antigravity` (alias `agy`) | Google's official `agy_acp_server.par` / `agy_acp_server` over ACP; executable from `executor_command`, `$CODEX_DIRECTOR_ANTIGRAVITY_COMMAND`, then PATH or `~/.local/bin/agy_acp_server.par` | `executor_args`, `executor_mode`, `executor_permissions` (`allow-once` or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `executor_command` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `executor_args` (an array of strings), `executor_mode` |

**Qoder.** `model` names Qoder's own model (`dfmodel`, `fast`, `ultimate`); without it a task runs on the default in Qoder's settings, and `continue` keeps the model its thread was created on. Qoder runs in its `yolo` permission mode by default, so a dispatched task never stalls on a prompt no human is watching; `executor_mode` overrides it.

**DSH.** Leave `model` out to keep its configured model; an explicit value must be an advertised ACP model id. DSH has no session modes, so do not send `executor_mode`. Its default `executor_permissions: allow-once` selects only the offered one-shot allow option; `ask` forwards permission choices to you. Continue with `continue`, the returned thread, and the same command and profile. When a round and its queue finish, the worker process closes; the next dispatch restores the conversation through `session/resume`, and the plugin replays its own saved events because DSH resume does not.

**Antigravity.** Install Google's binary from the [ACP registry](https://github.com/agentclientprotocol/registry/blob/main/antigravity-acp/agent.json), keeping `localharness_external` beside it. The server starts with no arguments. Complete its Google authentication before dispatching; it stores settings under `~/.gemini/antigravity-acp/`, separately from `agy`. New sessions default to `gemini-4-argon` with `high` thinking; `model` and `executor_effort` override these values, and selections must be advertised by the session. The plugin sets thinking through ACP's `thinking_level` option. Leave `executor_mode` out for the server default. The default permission policy is `allow-once`. Continue with the returned session id and the same executable; a resumed session keeps its model unless explicitly overridden.

`antigravity` is the canonical executor name and `agy` is an equivalent alias, including in dispatch fields and Bash headers. Both produce the same ACP launch configuration, so either can continue a session created under the other name. If an installed plugin's dispatch schema lacks both names, use `executor: "acp"`, the absolute server path as `executor_command`, `executor_args: []` and `executor_permissions: "allow-once"`. The updated Bash skill accepts either preset name with that plugin.

The helper must be discoverable on PATH or through `ANTIGRAVITY_HARNESS_PATH` (its absolute path); this also applies when the server executable is a symlink. The official runtime creates `skills/system/run-workflow/SKILL.md` in the workspace when opening a session, before any prompt.

Install the shared `codex-executor` skill under `~/.gemini/antigravity-cli/skills/codex-executor`; both the CLI and official ACP server read that user skill directory. Link the whole skill directory so its `scripts/context.sh` remains available. Dispatched tasks also receive the skill's absolute source path in the director note.

**What you lose off Codex:**

- Native `review` and `adversarial-review` modes are refused: they use Codex's own review, which has no ACP equivalent. Frontend reviews still go to agy as `investigate` tasks with a read-only review brief.
- `effort` does not reach the agent. Use `executor_effort` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`): agy defaults to `high`; other ACP executors default to `xhigh`, settling for `max` or `high` when the model has no `xhigh`.
- No `notify_director`, so no mid-run notes. Questions still arrive as `question_opened` through ACP elicitation.
- No mid-turn messages: use `delivery: "queue"` or `"interrupt"`. A plain message is refused (`midTurnSteer: false`).
- A thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- The live view shows fewer details: no streaming command output, file diff counts or sub-agent rows. The result footer prints `Session ID:` with no `codex resume` line.
