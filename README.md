# code-director

English | [中文](README.zh-CN.md)

Make Claude Code hand off code reading, debugging, implementation, and code review to an executor agent -- Codex, qodercli, or anything else that speaks ACP. Claude keeps only three jobs: talking to the user, writing the task brief, and judging the result.

Use it when you run Claude Code alongside at least one executor (Codex on a ChatGPT subscription, qodercli, or another ACP agent) and you want Claude's context and output spent on judgement rather than on reading files and writing code.

## Codex main agent edition

Use [codex-director](skills/codex-director/SKILL.md) when Codex itself is the main agent. It delegates complete tasks through native `collaboration` tools, continues the same agent for follow-ups, receives questions and results through its mailbox, and verifies the returned work. Parallel writers use isolated directories; assigned executors do not recursively enter director mode.

Install from this checkout:

```bash
bash ./install-codex.sh
```

The installer links `codex-director` and `codex-executor` under `${CODEX_HOME:-$HOME/.codex}/skills` to this checkout and preserves any conflicting existing installation. Keep the checkout in place. The skill is available on the next Codex turn; invoke it with `$codex-director`, or describe a coding task that benefits from delegation. The host must expose native `collaboration` tools. This edition runs through those tools without an app-server or Claude plugin; small tasks stay with the main agent.

For a persistent routing rule, add the block in [docs/agents-md-snippet.md](docs/agents-md-snippet.md) to `~/.codex/AGENTS.md` or the target project's `AGENTS.md`. It covers native dispatch, follow-ups, concurrency, and verification.

## Claude Code edition: what it consists of

The Claude Code edition installs a skill with two scripts, a Codex skill for its executors, and one config snippet:

| File | Purpose |
|---|---|
| `skills/code-director/SKILL.md` | Working rules for the Claude main thread: what to delegate, how to write a brief, how to run things in parallel, how the review loop works |
| `skills/code-director/scripts/dispatch.sh` | All dispatch logic: picks the executor and its command by MODE, prepends the director note, starts the run through the plugin's `codex-companion.mjs`, waits, collects; `dispatch` starts a job in one call, `follow` blocks on a job's event stream until the director must act, `events` streams job events for a monitor |
| `skills/code-director/scripts/context.sh` | Repository conclusions and discovery of rules and memory the executor needs |
| `skills/codex-executor/SKILL.md` | Codex skill a dispatched task follows: working rules, the shared-context procedure and the reply format |
| `docs/claude-md-snippet.md` | A routing rule for `CLAUDE.md` so that matching tasks always go through this path |

Flow:

```mermaid
sequenceDiagram
    participant U as User
    participant C as Claude main thread
    participant P as Codex plugin tasks pane
    participant X as Codex

    U->>C: describes the task
    C->>C: loads code-director, writes a brief
    par parallel dispatch, one Bash call each
        C->>X: dispatch.sh dispatch (MODE: implement)
        C->>X: dispatch.sh dispatch (MODE: investigate)
    end
    Note over P: the pane draws every job and arms one events Monitor per active repository
    X-->>P: job.completed (or question.opened, director.notified, job.failed)
    P-->>C: Monitor notification reaches the current turn
    C->>X: answers or reacts through the worker
    C->>X: MODE: adversarial-review (detached; reported by an event monitor)
    C->>X: MODE: continue, WRITE: yes (Codex fixes its own findings, same thread)
    X-->>P: job.completed
    C->>C: runs tests, spot-checks file:line claims
    C->>U: reports
```

## Shared context

Executors follow the `codex-executor` skill, which loads only for a task a main agent assigned; the director note names it, and a non-Codex executor gets its path to read. Before starting an investigation or implementation, executors run `context.sh rules` and read the listed rules and memory index, then `find` for related conclusions. The Claude route locates the startup directory from its transcript, with a session-ID fallback; when that information is unavailable, repository rules and conclusions still work. The Codex main agent names the same skill in each new executor message. Executors save a repository map if absent, check cited file:line evidence, run relevant checks, and return saved entry IDs and suggested memories. The main agent owns memory writes, summaries, entry verification and communication between tasks.

Conclusions are Markdown files under `<git-common-dir>/agent-context/entries/`, shared by all worktrees of that repository and outside tracked files. They record a commit, file blobs and source thread; `find` and `show` mark changed or missing files "可能过期" (possibly stale). Entries start `unverified`. The director checks evidence before verifying or retracting them. Verification changes status and preserves the original file hashes.

From a repository, use the Claude tool path below, or `${CODEX_HOME:-$HOME/.codex}/skills/codex-director/scripts/context.sh` on the Codex route:

```bash
CONTEXT=~/.claude/skills/code-director/scripts/context.sh
bash "$CONTEXT" rules --from /main-agent/startup --memory /path/to/memory/MEMORY.md
bash "$CONTEXT" find --kind repo-map
bash "$CONTEXT" find routing
bash "$CONTEXT" show <id>
printf '%s\n' 'Conclusion with path/to/file:line evidence.' | bash "$CONTEXT" save --kind code-path --title 'Routing path' --files path/to/file
bash "$CONTEXT" verify <id>
bash "$CONTEXT" retract <id> --reason 'Evidence no longer supports this conclusion'
bash "$CONTEXT" find --all
```

All commands accept `--cwd /path/to/repo`; `--files` paths are relative to that directory. `rules` accepts optional `--from` and `--memory`: it lists `CLAUDE.md` files above the target repository, including common ancestors of sibling worktrees and directories between startup and repository root, plus in-repository `CLAUDE.md` files where neither `AGENTS.md` nor `AGENTS.override.md` is present, and an existing memory index. Each listed `CLAUDE.md` is followed by existing whole-line `@path` imports, resolved relative to its directory with `~/` supported; imports expand one level and rule paths are deduplicated in order. Ancestor `AGENTS.md` and `AGENTS.override.md` files appear only when imported. Use `--source` to override the automatic `CODEX_THREAD_ID` source, and `--supersedes <id>` when saving a correction. Retracted entries are hidden unless `find --all` is used. Before dispatching new work the director searches for prior conclusions and continues their source thread when it belongs to this checkout; reviews keep a fresh thread.

## Relationship to the official Codex plugin

This depends on the Codex plugin for Claude Code. Every call to Codex goes through its `codex-companion.mjs` script. The recommended install is [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc), a fork of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) that includes `task --thread <id>` (submitted upstream as [#719](https://github.com/openai/codex-plugin-cc/pull/719)), background task control, durable observation, the tasks pane, and multi-executor support. This repo adds the delegation rules and dispatch script that use those capabilities. The old `codex-rescue` and `codex-task` forwarding agents are no longer part of the workflow.

## Install

Prerequisites:

1. Claude Code (tested with 2.1.259)
2. Codex CLI installed and logged in (tested with 0.152.1): `npm install -g @openai/codex && codex login`
3. The Codex plugin for Claude Code, installed from this fork of the official plugin: [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc). code-director uses its `task --thread <id>`, tasks pane, Monitor integration, and live controls. In a terminal:

   ```bash
   claude plugin uninstall codex@openai-codex   # only if the official one is installed
   claude plugin marketplace add y-cruce/codex-plugin-cc
   claude plugin install codex@y-cruce-codex
   ```

   Then run `/codex:setup` in Claude Code and confirm it reports ready.

Install this repo:

```bash
git clone https://github.com/y-cruce/code-director.git
cd code-director
./install.sh
```

The script links `~/.claude/skills/code-director`, and `${CODEX_HOME:-$HOME/.codex}/skills/codex-executor` for the dispatched tasks, to this checkout, so later edits and `git pull` take effect without reinstalling, and removes forwarding agents left by older versions. It also adds the Codex plugin's dispatch tools (`mcp__codex__dispatch`, `message`, `answer`, `result`, `status`, `tasks`, `cancel`) to `permissions.allow` in `~/.claude/settings.json`, so they run without a prompt; it keeps everything else in the file, does nothing if the rules are already there, and leaves a file that is not valid JSON untouched. Keep the checkout where it is; moving or deleting it breaks the link. Then append the snippet from `docs/claude-md-snippet.md` to `~/.claude/CLAUDE.md` and run `/reload-plugins` in Claude Code, or start a new session.

## Usage

No new commands. Talk to Claude as usual:

```
This endpoint returns 500 occasionally, find out why
Make order export asynchronous and send an email when it finishes
Review the changes on this branch
```

Claude loads code-director, writes a brief, dispatches it, acts on the events the tasks pane raises, spot-checks, and reports. You can also name it directly: "ask codex to look into X".

With the plugin's `mcp__codex__tasks` tool, Claude can find a thread to continue or check what this session has running in one call. It lists this session's threads across repositories, newest first, with the name, thread id (`pending` until known), executor, status, latest job and repository. Queued follow-up rounds share one line with their thread. Optional `query` filters names without regard to case, `cwd` limits the repository, `limit` sets the cap (default 20, range 1–100), and `all: true` includes other sessions' tasks created in the last 3 days with their session ids marked. Set `days` to a positive integer to widen that window. This session's threads have no age limit. Older matches are counted at the end. The first listing migrates older unindexed jobs once; later listings read this session's index. Indexes idle for 7 days expire; job records and state directories remain available.

### Brief format

What Claude hands to the worker script. A few header lines carry control parameters; after a blank line comes the body Codex reads:

```
MODE: implement
NAME: worker answer subcommand

## Goal
...
## Context
...
## Constraints
...
## Acceptance
...
```

| MODE | What it does | Writes files |
|---|---|---|
| `investigate` | Read code, trace call chains, find root causes | No |
| `implement` | Implement according to the brief | Yes |
| `continue` | Continue the previous Codex thread | Only with `WRITE: yes` in the header |
| `review` | The plugin's standard review | No |
| `adversarial-review` | Challenge-style review; the body is the focus text | No |

### Executors

`EXECUTOR` picks which agent runs a task-class mode (`investigate`, `implement`, `continue`). It defaults to `$CODEX_DIRECTOR_EXECUTOR`, else `codex`. The skill sends every task to Codex on the model in your Codex config (`gpt-6-sol`), and uses `MODEL: luna` for bulk mechanical work whose result tests or the diff can confirm. Set `CODEX_DIRECTOR_EXECUTOR=qoder` to move everything to Qoder when Codex quota runs out; briefs stay the same.

| EXECUTOR | Agent | Extra headers |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; the binary is found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `EXECUTOR_MODE` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP (`dsh --profile acp`); override its executable with `EXECUTOR_COMMAND` or `CODEX_DIRECTOR_DSH_COMMAND` | `EXECUTOR_ARGS`, `EXECUTOR_PERMISSIONS` (`allow-once` by default, or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `EXECUTOR_COMMAND` (required), `EXECUTOR_ARGS` (a JSON array), `EXECUTOR_MODE` |

DSH uses persistent ACP sessions. Dispatch with `EXECUTOR: dsh`; continue with `MODE: continue`, `THREAD: <the returned session id>` and the same executor command/profile. A finished round can close its process: the next dispatch restores model context with `session/resume`, while the plugin keeps the event history. `message --queue` waits for the current prompt; `--interrupt` cancels it before starting a replacement. DSH has no session modes or mid-turn steering. Its default permission policy selects only `allow_once`; `EXECUTOR_PERMISSIONS: ask` forwards the offered choices to the director. An omitted `MODEL` keeps DSH's configured model. Set `CODEX_DIRECTOR_EXECUTOR=dsh` to choose it by default; no installation or authentication is performed by dispatch.

`MODEL` names the executor's own model; `MODEL: luna` is the one name that works on both: `gpt-6-luna` at `max` effort on Codex, `dfmodel` on Qoder. A Qoder task without `MODEL` runs on the default model in Qoder's own settings. Qoder runs in its `yolo` permission mode unless `EXECUTOR_MODE` says otherwise, so a dispatched task never stalls on a prompt no human is watching.

`review` and `adversarial-review` stay Codex-only; the worker refuses them with another executor. A non-Codex agent has no `request_user_input` or `notify_director`, so the director note leaves both out for it.

Required header: `NAME` is a few words describing the task, truncated to 80 characters. It appears after `JOB:` in dispatch/collect output and, with a plugin supporting `task --label`, beside the job ID in status and events; older plugins print a note and launch without the label. Review commands carry the label as well.

Optional headers: `EFFORT` (`medium` / `high` / `xhigh` / `max`; left out, a new task runs at `model_reasoning_effort` from your Codex config and a `continue` keeps its thread's last level), `MODEL` (defaults to the model in your Codex config), `BASE` (base ref for review modes), `THREAD` (the Codex thread a `continue` must resume), `SIBLINGS` (one line naming other running Codex tasks, shown to Codex), `CWD` (repository to run in).

### Thread continuity

Codex has a very large context window, and a thread keeps everything Codex has read so far. Follow-ups on the same problem are faster and more accurate inside the same thread, so the skill keeps **one Codex thread per problem**:

- Every task result comes back with a `THREAD: <id>` line.
- Any later dispatch about the same problem (more investigation, a follow-up question, implementing what was found, fixing review findings) uses `MODE: continue` with that `THREAD:` in the header.
- dispatch.sh checks the requested thread against the one the plugin is about to resume and refuses with `THREAD_MISMATCH` rather than silently continuing the wrong thread.

With a plugin that supports `task --thread <id>` ([openai/codex-plugin-cc#719](https://github.com/openai/codex-plugin-cc/pull/719)), dispatch.sh resumes exactly the requested thread, so problems can be interleaved freely. Older plugin versions can only resume the most recent finished task thread of the current Claude session in the repo; there dispatch.sh falls back to a candidate check, and Claude avoids starting other task-class jobs in that repo between two `continue` calls.

### Checking progress

While Codex is running, `/codex:status` lists the running and recently finished jobs in the current repo with their current phase. `/codex:result <job-id>` shows the full output of one job. The tasks pane follows the end of a growing trace while you stay at the bottom and stops following when you scroll up; a finished task remains in the pane for three minutes. `/codex:tasks refresh` rebuilds the pane from disk and `/codex:tasks forget <n | name>` hides one row; the director does the same from Bash with `dispatch.sh pane refresh` and `dispatch.sh pane forget <n | name | task id>`, and `dispatch.sh pane list` shows each row's pane status beside its status on disk. None of these touch job files.

With a plugin supporting these features and Claude Code 2.1.299 or later, pending questions, failures and completions use your notification channel. Both the task name and status are clickable; sessions without a drawing surface explain why the pane cannot be shown. In the target position of `/codex:tasks`, `/codex:tasks forget` or `/codex:message`, type part of a name or ID and press Tab to insert the matching ID. Message suggestions include only running tasks; use `/codex:answer` for pending questions.

## Design decisions

**Codex output is never compressed.** Claude reads Codex's result with `result <job-id>`, unchanged. Claude's context is saved by the division of labor itself (Claude does not read files or write code), not by truncating or summarizing Codex's answer.

**One thread per problem, review only when it earns its cost.** For code changes, `implement` runs first (or `investigate` then `continue` with the implementation when the affected area is unclear). When the implementation comes back, Claude judges whether an `adversarial-review` is worth its cost for this particular change and says so either way. Findings go back to the same thread via `continue` to fix. A problem gets at most one review round; after the fixes Claude verifies with tests and wraps up without reviewing again.

**Parallel writes use worktrees with copy-on-write files.** The director creates one directory per writer, including itself, and passes its absolute path as `CWD:`. With a plugin shipping `scripts/worktree.mjs`, prefer:

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree /abs/source-repo /abs/new-worktree worker/topic
```

The helper registers independent Git metadata and pins source HEAD. It clones unchanged tracked files on supported filesystems (APFS on macOS, requiring Python 3 for native `clonefile`), uses Git for source edits or missing files, and reports `clonedFiles`, `copiedFiles` and `checkoutFiles`; ordinary copies do not prove disk savings. Untracked dependencies, outputs and session data are not copied. Keep the source stable during creation. Older plugins use `git worktree add -b worker/topic /abs/new-worktree <base-sha>` instead.

Plugin 1.4.45 adds nested Git submodules and checked removal. Each submodule gets independent Git metadata and objects at the commit recorded by its parent; local source repositories are preferred, otherwise Git clones from the configured URL with its normal access requirements. Missing pinned commits are fetched from that URL even if the source is initialized. Existing object files use copy-on-write where possible, reported as `clonedObjectFiles` / `copiedObjectFiles`; no object hard links or alternates remain on success. The `submodules` receipt lists paths, commits, local/remote sources and `fetchedFromRemote`. Initialization may add normal submodule registrations to the main repository's shared config. Failed access or verification retains the incomplete directory; do not dispatch into it. Detection uses Git's gitlink entries, not merely the presence of `.gitmodules`.

Executors work only in the assigned directory, check symlinks and absolute paths before builds, and keep writable dependencies and outputs separate. Commit submodule changes before updating the parent's gitlink and report commits that need preservation. After integration and stopping tasks, the director runs `dispatch.sh worktree remove /abs/source-repo /abs/worktree`; it refuses removal for uncommitted, untracked or ignored files and new submodule commits outside the recorded initial refs and remote-tracking refs. Only after those checks does it use Git's force flag required for initialized submodules. The parent branch is retained. Pane expiry does not reclaim directories, and a worktree must remain while its thread still needs `continue`. Read-only source investigations may use a shared checkout at a pinned SHA; tests that write files need isolation too.

**Detached start, events instead of waits.** Task runs use native background jobs; `dispatch` checks startup for up to 10 seconds, returning early once the job is running with a thread ID or has finished. A job that fails during this check, or a launch the companion rejects, returns `STATUS: failed` with an `ERROR:` line; later completion, questions, and notes come back through the plugin's tasks pane. Reviews start as a detached process and are reported by an event monitor.

**Decision logic lives in shell, not in the model's judgment.** For review modes, the choice between branch mode, working-tree mode, and the fallback is a fixed script. Claude pastes the brief into `dispatch.sh dispatch` and fills in nothing else.

**Simple tasks are not delegated.** Anything Claude can finish in about three tool calls without understanding unfamiliar code (a lookup, a grep, a few-line fix at a known place, running a command) is done directly; a dispatch costs a brief and at least a minute of waiting.

**Claude writes the documents.** Human-facing documents and pages are not delegated; Codex only gathers material. This rule constrains Claude's side only and is not written into briefs, so Codex updating comments or a README while coding is left alone.

## Known limitations

- Edits to the skill in `~/.claude/skills/` do not take effect in the current session until `/reload-plugins` or a new session.
- The plugin's `review` mode does not accept focus text; only `adversarial-review` does.
- `continue` starts a later turn. For an active task use `message` or `answer`; older plugins without live controls must wait for completion.
- The plugin keeps one shared Codex runtime per Claude session and plugin install path, and that runtime holds a writer lock on every thread it created. After switching the plugin install (for example from `codex@openai-codex` to `codex@y-cruce-codex`), start a new Claude session; threads created under the old install are held by the old runtime until it exits.
- Tested on macOS only. The scripts use `python3` and standard shell tools; Linux should work but is untested.

## Live Corrections and Answers

For Codex, follow-up messages default to native steering (`turn/steer`): `/codex:message <job-id> <text>` appends input to the active turn for a later model request. The director's `mcp__codex__message` also defaults to `steer` when `delivery` is omitted (plugin 1.4.100 or later); older versions require `delivery: "steer"`. Use `--queue` only when the user explicitly wants the next turn; Codex sends all waiting messages together in arrival order when that turn starts. ACP executors (qoder/dsh) use `queue` because they do not support mid-turn steering. `--interrupt` cancels the current turn and continues with the new direction. Existing edits remain and write permissions do not change. Acceptance does not prove that the instruction has already been followed.

For automatic corrections, run `bash ~/.claude/skills/code-director/scripts/dispatch.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt|--queue]`: success prints only `MESSAGED job=<id>` (with `queued=<id>` appended for `--queue`: the job the queued turn will run as); failure prints `MESSAGE_FAILED job=<id> <reason>` and exits nonzero; an unsupported plugin prints `MESSAGE_UNSUPPORTED:` and exits 2. There is no relay agent: the director sends every correction through this worker call. The two flags are two different intents and cannot be combined: `--interrupt` when the current turn must stop, `--queue` when the correction should become the next turn once this one ends. Both work on Codex and on an ACP agent. With no flag the message joins the running Codex turn, which an ACP agent refuses.

A new round on the same problem is another `dispatch` with `MODE: continue` and its `THREAD:`. If a structured question is pending, answer it through `answer` before sending an ordinary message; the worker refuses messages while that request is open.

For a structured question, the director receives a `question.opened` line from the tasks pane (or a `QUESTION` event from the monitor on that path) while Codex remains active. A request is reported as `QUESTION` only once and only while it is still open; an answered request is never reported again, and a request that comes up a second time while still unanswered arrives as `QUESTION_PENDING`, telling the director to check status rather than answer blindly. It supplies an answers-map JSON file, such as `{"<question-id>":{"answers":["..."]}}`, through `/codex:answer <job-id> --request-id <id> --answers-file <path>`, using the question IDs from status as keys. Questions time out after 10 minutes. `/codex:status <job-id>` exposes pending messages, questions, notifications, and interruption state.

From Bash, use `dispatch.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the pending request, exact question IDs, and nonempty answers before sending, then checks status again; success prints `ANSWERED job=<id> request=<id>`, and failure prints `ANSWER_FAILED` with details and exits 1. `--cwd` can appear anywhere after `answer` and defaults to the current directory; relative answers-file paths resolve against that directory.

**Nothing waits on a job.** The director writes the dispatch text to a file, runs `dispatch.sh dispatch` on it, and moves on; the call returns in seconds with the job id and thread. The plugin's tasks pane watches every job the session started, draws its live Codex trace, and automatically arms one `events` Monitor per repository with a live job. Its background notification can report completion, questions, notes and failures during the current turn. Events of a job a subagent dispatched go to that subagent. A monitored repository is excluded from the pane's prompt-submit path, so the same event does not wake the director twice. `/codex:tasks` opens or closes the pane, and `/codex:tasks <number | name>` switches between tasks. `dispatch.sh follow <job-id>` still blocks on one job's event stream for scripts, headless runs, and the times the director means to wait.

The host ends an automatically armed Monitor after thirty minutes; the pane re-arms it while a live job remains. Review dispatch starts detached and does not immediately return a job id, but the pane discovers its job file by Claude session and can display it; the Monitor reliably supplies the terminal job id. When the pane is absent (SDK, headless, or hooks unavailable), arm `dispatch.sh events --cwd <repo>` yourself before dispatch. A manual stream repeats `QUESTION_PENDING` every 2 minutes and exits after an hour without an active job with `IDLE_EXIT`. Unknown `events` and `follow` options are rejected with the supported options named.

Codex knows who started it. For `investigate` and `implement`, the worker script prepends a short note to the brief: Codex was started by a director agent rather than a human, `request_user_input` questions go to the director, other Codex tasks may be running (listed from the director's `SIBLINGS:` header) and Codex must not coordinate with them itself. On plugins that expose the `notify_director` tool, Codex can also send the director a one-line note without stopping, but only when the director must act or relay something to another running task, never for progress; it arrives as a `NOTIFIED` event while the job keeps running, carrying `pending_request=<id>` when a structured question was open at that moment so the director answers it instead of sending a message. Codex tasks never talk to each other; the director relays.

All command selection, review fallbacks, and the director note live in `skills/code-director/scripts/dispatch.sh` (`dispatch` is `launch` plus `collect`), so the logic can be tested with `bash -n` and a stub companion.

Native next-turn queues are distinct from these mid-turn controls. Update the installed plugin and restart the Claude session to use the new broker; editing this checkout does not update installed copies.

## License

MIT
