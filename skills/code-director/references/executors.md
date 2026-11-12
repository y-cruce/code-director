# Executors other than Codex

Use Antigravity (`agy`) for frontend work unless the user chooses another executor. Omitted `executor` uses `$CODEX_DIRECTOR_EXECUTOR`, else Codex; explicitly use `executor: "codex"` when required. Reviews stay on Codex. `continue` ignores this default and restores its thread's executor, command and arguments; explicit mismatches are rejected. Set `executor` on `mcp__codex__dispatch` (the `EXECUTOR:` Bash header).

| `executor` | Agent | Extra fields |
|---|---|---|
| `codex` | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `executor_mode` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP; executable from `executor_command`, `$CODEX_DIRECTOR_DSH_COMMAND`, executable `~/.local/share/dsh-fork/dsh`, then PATH `dsh`; defaults are `acp-fork` for the optional isolated launcher and `acp` for PATH | `executor_args`, `executor_mode` (`default` or `plan` on the community profile), `executor_permissions` (`allow-once` or `ask`) |
| `antigravity` (alias `agy`) | CLI `agy acp`; executable from `executor_command`, `$CODEX_DIRECTOR_ANTIGRAVITY_COMMAND`, then `~/.local/bin/agy` or PATH | `executor_args`, `executor_mode`, `executor_permissions` (`allow-once` or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `executor_command` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `executor_args` (an array of strings), `executor_mode` |

For running corrections, use the same default `delivery: "steer"` as Codex when the job reports `midTurnSteer: true`. Qoder and agy support this natively; DSH uses the extension below. `queue` means a later turn; ACP transport alone is no reason to select it. A finished job is continued with `continue`.

**Qoder.** `model` names Qoder's own model (`dfmodel`, `fast`, `ultimate`); without it a task runs on the default in Qoder's settings, and `continue` keeps the model its thread was created on. Qoder runs in its `yolo` permission mode by default, so a dispatched task never stalls on a prompt no human is watching; `executor_mode` overrides it.

For mid-turn messages, Qoder advertises its private `agentCapabilities._meta.qoder.promptQueueing` capability. A supporting plugin sends another `session/prompt` to the same session while the current prompt is running; Qoder can consume it at a loop boundary. Use default `delivery: "steer"` only when the plugin reports `midTurnSteer: true`. `queue` is for an intended next turn. If an older plugin lacks steering, choose queue or interrupt by the correction's intent. Submission does not prove model consumption. Qoder does not implement the `_session/steering` extension.

**DSH.** Lookup order is explicit `executor_command`, `$CODEX_DIRECTOR_DSH_COMMAND`, executable `~/.local/share/dsh-fork/dsh`, then `dsh` on PATH. The isolated installation is optional: when selected, it defaults to `["--profile","acp-fork"]`; otherwise PATH defaults to `["--profile","acp"]`. Explicit `executor_args` overrides either default. Explicit executable overrides retain the `acp-fork` argument default; supply `executor_args` when that executable uses another profile. PATH's legacy ACP profile has no session modes, so `executor_mode` is rejected on that fallback.

The optional fork-capable launcher sets `DSH_HOME=~/.local/share/dsh-fork/home` and runs dsh `0.2.2-rc.1` from `~/.local/share/dsh-fork/runtime`, with Cordis `4.1.0` and community plugin `@8kugames/dsh-zed-acp` `0.3.10`. Its modes are `default` and `plan`; omit `executor_mode` for the profile default. Leave `model` out to keep the selected profile's configured model; an explicit value must be an advertised ACP model id. The default `executor_permissions: allow-once` selects only an offered one-shot allow option; `ask` forwards permission choices to you. Continue with the returned thread and omit launch overrides: its recorded command and arguments are restored, including the old launcher for existing DSH threads. After the worker closes, continuation uses `session/resume` and the plugin replays its saved events.

The community plugin implements `_session/steering` and advertises it under `agentCapabilities._meta.steering`. Steering appends to the active turn; the original `session/prompt` response still ends that turn. It also provides `session/load`, whole-session `session/fork` and inclusive forking at an assistant reply. The companion has no task-fork entry point yet. Tasks using the community adapter use its built-in steering; the old global `dsh-plugins/acp-steering` patch is needed for steering with the original ACP adapter.

For director questions use `node "$CODEX_ACP_COMPANION_PATH" ask-director --question "Question" --options '["First","Second"]'`. It uses the same pending-question, answer and ten-minute timeout path as ACP native questions and prints the answer, including free text, to stdout. With dsh bash, use `timeoutMs:600000`; the default is 120000 ms, capped at 600000 ms. A composition with jobs promotes a still-running foreground command on timeout; collect it with `job_output`, not a new question. Without jobs the shell may kill it at that limit, slightly before the companion's deadline; report the shell outcome and check status.

To opt into the fork-capable adapter, install the pinned runtime outside `~/.dsh`, then install the plugin into its own home:

```sh
npm install --prefix "$HOME/.local/share/dsh-fork/runtime" --save-exact @deepseek-ai/dsh@0.2.2-rc.1
node "$HOME/.local/share/dsh-fork/runtime/node_modules/@deepseek-ai/dsh-subprocess-local/scripts/ensure-spawn-helper.mjs"
DSH_HOME="$HOME/.local/share/dsh-fork/home" "$HOME/.local/share/dsh-fork/runtime/node_modules/.bin/dsh" plugin --profile acp-fork add @8kugames/dsh-zed-acp@0.3.10
```

Create the executable `~/.local/share/dsh-fork/dsh` with:

```sh
#!/bin/sh
DSH_FORK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export DSH_HOME="$DSH_FORK_ROOT/home"
exec node "$DSH_FORK_ROOT/runtime/node_modules/@deepseek-ai/dsh/lib/bin.js" "$@"
```

Keep credentials and provider/model configuration in this new home. Copy credentials privately if reusing the existing account; copy only the provider and default-model rows needed by the new profile. Existing profile patches can contain installers that rewrite the global adapter. The new runtime owns only its new session store. To roll back a new dispatch, specify the original `dsh` as `executor_command` and `["--profile","acp"]` as `executor_args`; continue each existing thread with its recorded launcher. Both homes and runtimes must remain available while their threads are in use.

**Antigravity.** It specializes in frontend design and implementation. Use the installed CLI's `agy acp` (verified with 1.5.6); it reuses the CLI login and MCP configuration. The preset prefers `~/.local/bin/agy` over PATH terminal wrappers, and defaults arguments to `["acp"]`. The subprocess inherits the companion's network environment. Leave `executor_mode` out for the server default, or select `default`, `accept-edits`, `auto` or `plan`. Permissions default to `allow-once`. Continue restores the recorded executable and arguments.

`antigravity` is the canonical executor name and `agy` is an equivalent alias, including in dispatch fields and Bash headers. Both produce the same ACP launch configuration, so either can continue a session created under the other name. If an installed plugin's dispatch schema lacks both names, use `executor: "acp"`, the absolute server path as `executor_command`, `executor_args: ["acp"]` and `executor_permissions: "allow-once"`. The updated Bash skill accepts either preset name with that plugin.

The CLI reads `~/.gemini/config/mcp_config.json` itself, including HTTP `serverUrl` entries. No separate helper or MCP alias conversion is needed.

New and resumed agy sessions include HOME and linked skill directories alongside the existing additional directories. The appended system prompt directs shell commands to the task's cwd. The CLI no longer generates the old workflow skill; the plugin no longer writes its Git exclusion.

agy native form questions always wait for the director, including under allow-once. Ordinary tool permissions still follow allow-once/ask. New-session effort defaults in the driver to Carbon high or Opus medium; `continue` does not impose a default effort.

Install the shared `codex-executor` skill under `~/.gemini/antigravity-cli/skills/codex-executor`; both the CLI and official ACP server read that user skill directory. Link the whole skill directory so its `scripts/context.sh` remains available. Dispatched tasks also receive the skill's absolute source path in the director note.

**agy steering.** The CLI accepts a concurrent `session/prompt` as input to the active conversation. It settles the previous prompt on steering; the driver waits for the latest response before completing the same job and turn. Submission does not separately acknowledge acceptance or model consumption.

An unfinished execute tool prevents steer; choose queue or interrupt. If the CLI returns `end_turn` before finite commands finish, the job stays running, reads their statuses through `session/load`, and automatically prompts the agent to finish the original task once they complete. Repeated waits share 30 minutes; timeout reports the remaining commands. Native `IsDaemon: true` commands are excluded. This recovery is agy-only; DSH retains the original prompt boundary.

**ACP steering extensions.** A server advertises these with `_meta.steering.supported: true` at the initialize response's top level or under `agentCapabilities`. The plugin sends `_session/steering` with the current session, prompt and `_meta.steering.idleBehavior: "promptRequired"`. `injected` confirms insertion, not model consumption; `promptRequired` consumes nothing and asks the client to deliver a normal prompt later. A null or unrecognized outcome does not establish insertion. The DSH community plugin includes this extension; other servers need their corresponding extension.

The task-control endpoint is exposed in the ACP executor's environment and permits answer and approval calls; this relies on the executor not invoking those interfaces on its own.

Antigravity CLI setup and rollback details are in the plugin's `scripts/agy-acp/README.md`. DSH's community adapter is [@8kugames/dsh-zed-acp](https://github.com/8kugames/dsh-zed-acp).

**What you lose off Codex:**

- Native `review` and `adversarial-review` modes are refused: they use Codex's own review, which has no ACP equivalent. Frontend reviews still go to agy as `investigate` tasks with a read-only review brief.
- `effort` does not reach the agent. ACP uses `executor_effort` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`) with values advertised by the agent.
- ACP notes use `node "$CODEX_ACP_COMPANION_PATH" notify-director "message"`; they produce the same `director.notified` event as Codex and continue working. agy/Qoder use native questions; dsh uses `ask-director`. Question and permission requests expire after ten minutes and interrupt the active turn. Only Monitor mode sends periodic unanswered-question reminders.
- Mid-turn support is agent-specific: use default steering for Qoder, agy or DSH with its extension when `midTurnSteer: true`. If a server lacks the capability, queue only when the instruction may wait for a later turn, or interrupt when active work must stop.
- A thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- ACP interrupt preserves edits but reports no partialChanges. Active ACP queue starts a separate job per instruction and returns `queuedJobId`; active Codex queue stays in the same job. Idle queue returns a new job for either executor. Steer is rejected while a question is pending; queue is allowed.
- Default full access already permits writes even without `write:true`. Express read-only intent in the brief. ACP does not enforce Codex sandbox flags; its own permissions/modes apply, and Qoder ask does not remove its default bypass mode.
- The live view depends on the agent: command-output deltas and a complete turn diff may be unavailable, and Qoder sub-agent rows do not provide Codex's full child-thread events. Missing usage or an agent-reported zero does not prove zero consumption. The result footer prints `Session ID:` with no `codex resume` line. Claude transcript transfer remains Codex-only; there is no session/load fallback or numeric/boolean form conversion.
