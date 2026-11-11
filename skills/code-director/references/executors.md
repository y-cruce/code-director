# Executors other than Codex

Use Antigravity (`agy`) for frontend work unless the user chooses another executor. Omitted `executor` uses `$CODEX_DIRECTOR_EXECUTOR`, else Codex; explicitly use `executor: "codex"` when required. Reviews stay on Codex. `continue` ignores this default and restores its thread's executor, command and arguments; explicit mismatches are rejected. Set `executor` on `mcp__codex__dispatch` (the `EXECUTOR:` Bash header).

| `executor` | Agent | Extra fields |
|---|---|---|
| `codex` | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `executor_mode` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP (`dsh --profile acp`); executable from `executor_command`, `$CODEX_DIRECTOR_DSH_COMMAND`, then PATH | `executor_args` (override the launch arguments), `executor_permissions` (`allow-once` or `ask`) |
| `antigravity` (alias `agy`) | Google's official `agy_acp_server.par` / `agy_acp_server` over ACP; executable from `executor_command`, `$CODEX_DIRECTOR_ANTIGRAVITY_COMMAND`, then PATH or `~/.local/bin/agy_acp_server.par` | `executor_args`, `executor_mode`, `executor_permissions` (`allow-once` or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `executor_command` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `executor_args` (an array of strings), `executor_mode` |

For running corrections, use the same default `delivery: "steer"` as Codex when the job reports `midTurnSteer: true`. Qoder and DSH/agy with the extensions below support this. `queue` means a later turn; ACP transport alone is no reason to select it. A finished job is continued with `continue`.

**Qoder.** `model` names Qoder's own model (`dfmodel`, `fast`, `ultimate`); without it a task runs on the default in Qoder's settings, and `continue` keeps the model its thread was created on. Qoder runs in its `yolo` permission mode by default, so a dispatched task never stalls on a prompt no human is watching; `executor_mode` overrides it.

For mid-turn messages, Qoder advertises its private `agentCapabilities._meta.qoder.promptQueueing` capability. A supporting plugin sends another `session/prompt` to the same session while the current prompt is running; Qoder can consume it at a loop boundary. Use default `delivery: "steer"` only when the plugin reports `midTurnSteer: true`. `queue` is for an intended next turn. If an older plugin lacks steering, choose queue or interrupt by the correction's intent. Submission does not prove model consumption. Qoder does not implement the `_session/steering` extension.

**DSH.** Leave `model` out to keep its configured model; an explicit value must be an advertised ACP model id. DSH has no session modes, so do not send `executor_mode`. Its default `executor_permissions: allow-once` selects only the offered one-shot allow option; `ask` forwards permission choices to you. Continue with `continue`, the returned thread, and the same command and profile. When a round and its queue finish, the worker process closes; the next dispatch restores the conversation through `session/resume`, and the plugin replays its own saved events because DSH resume does not.

The original DSH ACP adapter allows only one in-flight prompt per session and rejects a second with `a prompt is already in flight for this session`. Its core/API has steer; the local `dsh-plugins/acp-steering` extension exposes it separately through `_session/steering`, while ordinary prompts retain the existing guard. Use steer when that extension advertises support and the plugin reports `midTurnSteer: true`; otherwise use queue or interrupt.

DSH has no native question tool in this profile. Use `node "$CODEX_ACP_COMPANION_PATH" ask-director --question "Question" --options '["First","Second"]'`. It uses the same pending-question, answer and ten-minute timeout path as ACP native questions and prints the answer, including free text, to stdout. With dsh bash, use `timeoutMs:600000`; the default is 120000 ms, capped at 600000 ms. A composition with jobs promotes a still-running foreground command on timeout; collect it with `job_output`, not a new question. Without jobs the shell may kill it at that limit, slightly before the companion's deadline; report the shell outcome and check status.

**Antigravity.** It specializes in frontend design and implementation. Install Google's binary from the [ACP registry](https://github.com/agentclientprotocol/registry/blob/main/antigravity-acp/agent.json), keeping `localharness_external` beside it. The server starts with no arguments. Complete its Google authentication before dispatching; it stores settings under `~/.gemini/antigravity-acp/`, separately from `agy`. Leave `executor_mode` out for the server default. The default permission policy is `allow-once`. Continue with the returned session id and the same executable.

`antigravity` is the canonical executor name and `agy` is an equivalent alias, including in dispatch fields and Bash headers. Both produce the same ACP launch configuration, so either can continue a session created under the other name. If an installed plugin's dispatch schema lacks both names, use `executor: "acp"`, the absolute server path as `executor_command`, `executor_args: []` and `executor_permissions: "allow-once"`. The updated Bash skill accepts either preset name with that plugin.

The helper must be discoverable on PATH or through `ANTIGRAVITY_HARNESS_PATH` (its absolute path); this also applies when the server executable is a symlink. The official runtime creates `skills/system/run-workflow/SKILL.md` in the workspace when opening a session, before any prompt.

The plugin adds the exact untracked path `/skills/system/run-workflow/SKILL.md` to the repository's local `info/exclude`, resolved by Git. This intentionally writes local Git metadata even for a read-only task; linked worktrees share that exclusion. Tracked files and sibling skills are not hidden. New and resumed agy sessions include HOME alongside the existing additional directories. This expands file-tool read and write scope without changing cwd or disabling edit approval.

agy native `interaction_*` questions are carried as permission requests but are always forwarded as questions, never auto-approved. Ordinary tool permissions still follow allow-once/ask. New-session effort defaults in the driver to Carbon high or Opus medium; `continue` does not impose a default effort.

Install the shared `codex-executor` skill under `~/.gemini/antigravity-cli/skills/codex-executor`; both the CLI and official ACP server read that user skill directory. Link the whole skill directory so its `scripts/context.sh` remains available. Dispatched tasks also receive the skill's absolute source path in the director note.

**ACP steering extensions.** A server advertises these at the initialize response's top-level `_meta.steering.supported: true`. The plugin sends `_session/steering` with the current session, prompt and `_meta.steering.idleBehavior: "promptRequired"`. `injected` confirms insertion, not model consumption; `promptRequired` consumes nothing and asks the client to deliver a normal prompt later. A null or unrecognized outcome does not establish insertion. Unmodified DSH/Antigravity servers lack this advertisement; their local extensions must be installed before this route is available.

Plugin 1.4.103 includes Antigravity's proxy at `<plugin-root>/scripts/agy-acp/acp-proxy.mjs`; select that executable through `executor_command` or `CODEX_DIRECTOR_ANTIGRAVITY_COMMAND`. It requires the existing official ACP 1.4.4 runtime. Setup details are in the plugin's `scripts/agy-acp/README.md`. DSH's patch is maintained in [dsh-plugins/acp-steering](https://github.com/y-cruce/dsh-plugins/tree/main/acp-steering).

**What you lose off Codex:**

- Native `review` and `adversarial-review` modes are refused: they use Codex's own review, which has no ACP equivalent. Frontend reviews still go to agy as `investigate` tasks with a read-only review brief.
- `effort` does not reach the agent. ACP uses `executor_effort` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`) with values advertised by the agent.
- ACP notes use `node "$CODEX_ACP_COMPANION_PATH" notify-director "message"`; they produce the same `director.notified` event as Codex and continue working. agy/Qoder use native questions; dsh uses `ask-director`. Question and permission requests expire after ten minutes and interrupt the active turn. Only Monitor mode sends periodic unanswered-question reminders.
- Mid-turn support is agent-specific: use default steering for Qoder or DSH/agy with their extensions when `midTurnSteer: true`. If a server lacks the capability, queue only when the instruction may wait for a later turn, or interrupt when active work must stop.
- A thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- ACP interrupt preserves edits but reports no partialChanges. Active ACP queue starts a separate job per instruction and returns `queuedJobId`; active Codex queue stays in the same job. Idle queue returns a new job for either executor. Steer is rejected while a question is pending; queue is allowed.
- Default full access already permits writes even without `write:true`. Express read-only intent in the brief. ACP does not enforce Codex sandbox flags; its own permissions/modes apply, and Qoder ask does not remove its default bypass mode.
- The live view depends on the agent: command-output deltas and a complete turn diff may be unavailable, and Qoder sub-agent rows do not provide Codex's full child-thread events. Missing usage or an agent-reported zero does not prove zero consumption. The result footer prints `Session ID:` with no `codex resume` line. Claude transcript transfer remains Codex-only; there is no session/load fallback or numeric/boolean form conversion.
