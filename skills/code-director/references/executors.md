# Executors other than Codex

Use these only when the user names one. Set `executor` on `mcp__codex__dispatch` (the `EXECUTOR:` header on the Bash path); `executor` and `model` are passed through as written.

| `executor` | Agent | Extra fields |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `executor_mode` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP (`dsh --profile acp`); executable from `executor_command`, `$CODEX_DIRECTOR_DSH_COMMAND`, then PATH | `executor_args` (override the launch arguments), `executor_permissions` (`allow-once` or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `executor_command` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `executor_args` (an array of strings), `executor_mode` |

**Qoder.** `model` names Qoder's own model (`dfmodel`, `fast`, `ultimate`); without it a task runs on the default in Qoder's settings, and `continue` keeps the model its thread was created on. Qoder runs in its `yolo` permission mode by default, so a dispatched task never stalls on a prompt no human is watching; `executor_mode` overrides it.

**DSH.** Leave `model` out to keep its configured model; an explicit value must be an advertised ACP model id. DSH has no session modes, so do not send `executor_mode`. Its default `executor_permissions: allow-once` selects only the offered one-shot allow option; `ask` forwards permission choices to you. Continue with `continue`, the returned thread, and the same command and profile. When a round and its queue finish, the worker process closes; the next dispatch restores the conversation through `session/resume`, and the plugin replays its own saved events because DSH resume does not.

**What you lose off Codex:**

- `review` and `adversarial-review` are refused: they use Codex's own review, which has no ACP equivalent.
- `effort` does not reach the agent. Its own rung comes from `executor_effort` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`), which defaults to `xhigh`, settling for `max` or `high` when the model has no `xhigh`. Leave it out unless you want the agent to think less.
- No `notify_director`, so no mid-run notes. Questions still arrive as `question_opened` through ACP elicitation.
- No mid-turn messages: use `delivery: "queue"` or `"interrupt"`. A plain message is refused (`midTurnSteer: false`).
- A thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- The live view shows fewer details: no streaming command output, file diff counts or sub-agent rows. The result footer prints `Session ID:` with no `codex resume` line.
