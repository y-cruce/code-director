# codex-director

English | [中文](README.zh-CN.md)

Make Claude Code hand off code reading, debugging, implementation, and code review to Codex. Claude keeps only three jobs: talking to the user, writing the task brief, and judging the result.

Use it when you run both Claude Code and Codex (ChatGPT subscription), Claude's quota or context is the tighter resource, and you want Claude to read fewer files and write less code.

## What it consists of

Two installed files and one config snippet:

| File | Purpose |
|---|---|
| `skills/codex-director/SKILL.md` | Working rules for the Claude main thread: what to delegate, how to write a brief, how to run things in parallel, how the review loop works |
| `skills/codex-director/scripts/codex-worker.sh` | All dispatch logic: picks the Codex command by MODE, prepends the director note, starts Codex through the plugin's `codex-companion.mjs`, waits, collects; `dispatch` starts a job in one call, `follow` blocks on a job's event stream until the director must act, `events` streams job events for a monitor |
| `docs/claude-md-snippet.md` | A routing rule for `CLAUDE.md` so that matching tasks always go through this path |

Flow:

```mermaid
sequenceDiagram
    participant U as User
    participant C as Claude main thread
    participant P as Codex plugin tasks pane
    participant X as Codex

    U->>C: describes the task
    C->>C: loads codex-director, writes a brief
    par parallel dispatch, one Bash call each
        C->>X: codex-worker.sh dispatch (MODE: implement)
        C->>X: codex-worker.sh dispatch (MODE: investigate)
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

## Relationship to the official Codex plugin

This depends on the Codex plugin for Claude Code. Every call to Codex goes through its `codex-companion.mjs` script. The recommended install is [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc), a fork of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) that includes `task --thread <id>` (submitted upstream as [#719](https://github.com/openai/codex-plugin-cc/pull/719)), background task control, durable observation, the tasks pane, and multi-executor support. This repo adds the delegation rules and dispatch script that use those capabilities. The old `codex-rescue` and `codex-task` forwarding agents are no longer part of the workflow.

## Install

Prerequisites:

1. Claude Code (tested with 2.1.259)
2. Codex CLI installed and logged in (tested with 0.152.1): `npm install -g @openai/codex && codex login`
3. The Codex plugin for Claude Code, installed from this fork of the official plugin: [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc). codex-director uses its `task --thread <id>`, tasks pane, Monitor integration, and live controls. In a terminal:

   ```bash
   claude plugin uninstall codex@openai-codex   # only if the official one is installed
   claude plugin marketplace add y-cruce/codex-plugin-cc
   claude plugin install codex@y-cruce-codex
   ```

   Then run `/codex:setup` in Claude Code and confirm it reports ready.

Install this repo:

```bash
git clone https://github.com/y-cruce/codex-director.git
cd codex-director
./install.sh
```

The script copies the skill and worker script into `~/.claude/` and removes forwarding agents left by older versions. Then append the snippet from `docs/claude-md-snippet.md` to `~/.claude/CLAUDE.md` and run `/reload-plugins` in Claude Code, or start a new session.

## Usage

No new commands. Talk to Claude as usual:

```
This endpoint returns 500 occasionally, find out why
Make order export asynchronous and send an email when it finishes
Review the changes on this branch
```

Claude loads codex-director, writes a brief, dispatches it, acts on the events the tasks pane raises, spot-checks, and reports. You can also name it directly: "ask codex to look into X".

### Brief format

What Claude hands to the worker script. A few header lines carry control parameters; after a blank line comes the body Codex reads:

```
MODE: implement
NAME: worker answer subcommand
EFFORT: high

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

`EXECUTOR` picks which agent runs a task-class mode (`investigate`, `implement`, `continue`). It defaults to `codex`, so nothing changes unless you set it.

| EXECUTOR | Agent | Extra headers |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; the binary is found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `EXECUTOR_MODE` (a Qoder session mode, e.g. `yolo`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `EXECUTOR_COMMAND` (required), `EXECUTOR_ARGS` (a JSON array), `EXECUTOR_MODE` |

`MODEL` names the executor's own model. On Qoder, `dfmodel` is the default — cheap and fast, the one to run many tasks on at once — and `ultimate` is the strong model for a hard problem. Qoder runs in its `yolo` permission mode unless `EXECUTOR_MODE` says otherwise, so a dispatched task never stalls on a prompt no human is watching.

`review` and `adversarial-review` stay Codex-only; the worker refuses them with another executor. A non-Codex agent has no `request_user_input` or `notify_director`, so the director note leaves both out for it.

Required header: `NAME` is a few words describing the task, truncated to 80 characters. It appears after `JOB:` in dispatch/collect output and, with a plugin supporting `task --label`, beside the job ID in status and events; older plugins print a note and launch without the label. Review commands carry the label as well.

Optional headers: `EFFORT` (`medium` / `high` / `xhigh`, default high), `MODEL` (defaults to the model in your Codex config), `BASE` (base ref for review modes), `THREAD` (the Codex thread a `continue` must resume), `SIBLINGS` (one line naming other running Codex tasks, shown to Codex), `CWD` (repository to run in).

### Thread continuity

Codex has a very large context window, and a thread keeps everything Codex has read so far. Follow-ups on the same problem are faster and more accurate inside the same thread, so the skill keeps **one Codex thread per problem**:

- Every task result comes back with a `THREAD: <id>` line.
- Any later dispatch about the same problem (more investigation, a follow-up question, implementing what was found, fixing review findings) uses `MODE: continue` with that `THREAD:` in the header.
- codex-worker checks the requested thread against the one the plugin is about to resume and refuses with `THREAD_MISMATCH` rather than silently continuing the wrong thread.

With a plugin that supports `task --thread <id>` ([openai/codex-plugin-cc#719](https://github.com/openai/codex-plugin-cc/pull/719)), codex-worker resumes exactly the requested thread, so problems can be interleaved freely. Older plugin versions can only resume the most recent finished task thread of the current Claude session in the repo; there codex-worker falls back to a candidate check, and Claude avoids starting other task-class jobs in that repo between two `continue` calls.

### Checking progress

While Codex is running, `/codex:status` lists the running and recently finished jobs in the current repo with their current phase. `/codex:result <job-id>` shows the full output of one job. The tasks pane follows the end of a growing trace while you stay at the bottom and stops following when you scroll up; a finished task remains in the pane for fifteen minutes.

## Design decisions

**Codex output is never compressed.** Claude reads Codex's result with `result <job-id>`, unchanged. Claude's context is saved by the division of labor itself (Claude does not read files or write code), not by truncating or summarizing Codex's answer.

**One thread per problem, review only when it earns its cost.** For code changes, `implement` runs first (or `investigate` then `continue` with the implementation when the affected area is unclear). When the implementation comes back, Claude judges whether an `adversarial-review` is worth its cost for this particular change and says so either way. Findings go back to the same thread via `continue` to fix, up to three rounds.

**Parallel writes use worktrees.** Only one `implement` runs per checkout at a time. To have Codex produce two approaches, give each route its own `git worktree` and pass it as `CWD:`, and Claude picks one.

**Detached start, events instead of waits.** Task runs use native background jobs; `dispatch` checks startup for up to 10 seconds, returning early once the job is running with a thread ID or has finished. A job that fails during this check returns `STATUS: failed` with an `ERROR:` line; later completion, questions, and notes come back through the plugin's tasks pane. Reviews start as a detached process and are reported by an event monitor.

**Decision logic lives in shell, not in the model's judgment.** For review modes, the choice between branch mode, working-tree mode, and the fallback is a fixed script. Claude pastes the brief into `codex-worker.sh dispatch` and fills in nothing else.

**Simple tasks are not delegated.** Anything Claude can finish in about three tool calls without understanding unfamiliar code (a lookup, a grep, a few-line fix at a known place, running a command) is done directly; a dispatch costs a brief and at least a minute of waiting.

**Claude writes the documents.** Human-facing documents and pages are not delegated; Codex only gathers material. This rule constrains Claude's side only and is not written into briefs, so Codex updating comments or a README while coding is left alone.

## Known limitations

- Edits to the skill in `~/.claude/skills/` do not take effect in the current session until `/reload-plugins` or a new session.
- The plugin's `review` mode does not accept focus text; only `adversarial-review` does.
- `continue` starts a later turn. For an active task use `message` or `answer`; older plugins without live controls must wait for completion.
- The plugin keeps one shared Codex runtime per Claude session and plugin install path, and that runtime holds a writer lock on every thread it created. After switching the plugin install (for example from `codex@openai-codex` to `codex@y-cruce-codex`), start a new Claude session; threads created under the old install are held by the old runtime until it exits.
- Tested on macOS only. The scripts use `python3` and standard shell tools; Linux should work but is untested.

## Live Corrections and Answers

With a plugin version supporting live controls, `/codex:message <job-id> <text>` appends input to the running turn. Add `--interrupt` to cancel that turn and continue the same job and thread with the new direction. Existing edits remain and write permissions do not change. Acceptance means queued for a later model request, not that the instruction has already been followed.

For automatic corrections, run `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt]`: success prints only `MESSAGED job=<id>`; failure prints `MESSAGE_FAILED job=<id> <reason>` and exits nonzero; an unsupported plugin prints `MESSAGE_UNSUPPORTED:` and exits 2. There is no relay agent: the director sends every correction through this worker call. Use `--interrupt` when the current turn must stop, or omit it when the correction can wait for Codex's next model request.

A new round on the same problem is another `dispatch` with `MODE: continue` and its `THREAD:`. If a structured question is pending, answer it through `answer` before sending an ordinary message; the worker refuses messages while that request is open.

For a structured question, the director receives a `question.opened` line from the tasks pane (or a `QUESTION` event from the monitor on that path) while Codex remains active. A request is reported as `QUESTION` only once and only while it is still open; an answered request is never reported again, and a request that comes up a second time while still unanswered arrives as `QUESTION_PENDING`, telling the director to check status rather than answer blindly. It supplies an answers-map JSON file, such as `{"<question-id>":{"answers":["..."]}}`, through `/codex:answer <job-id> --request-id <id> --answers-file <path>`, using the question IDs from status as keys. Questions time out after 10 minutes. `/codex:status <job-id>` exposes pending messages, questions, notifications, and interruption state.

From Bash, use `codex-worker.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the pending request, exact question IDs, and nonempty answers before sending, then checks status again; success prints `ANSWERED job=<id> request=<id>`, and failure prints `ANSWER_FAILED` with details and exits 1. `--cwd` can appear anywhere after `answer` and defaults to the current directory; relative answers-file paths resolve against that directory.

**Nothing waits on a job.** The director writes the dispatch text to a file, runs `codex-worker.sh dispatch` on it, and moves on; the call returns in seconds with the job id and thread. The plugin's tasks pane watches every job the session started, draws its live Codex trace, and automatically arms one `events` Monitor per repository with a live job. Its background notification can report completion, questions, notes, failures, and a fifteen-minute `STALLED` condition during the current turn. A monitored repository is excluded from the pane's prompt-submit path, so the same event does not wake the director twice. `/codex:tasks` opens the pane and switches between tasks. `codex-worker.sh follow <job-id>` still blocks on one job's event stream for scripts, headless runs, and the times the director means to wait.

The host ends an automatically armed Monitor after thirty minutes; the pane re-arms it while a live job remains. Review dispatch starts detached and does not immediately return a job id, but the pane discovers its job file by Claude session and can display it; the Monitor reliably supplies the terminal job id. When the pane is absent (SDK, headless, or hooks unavailable), arm `codex-worker.sh events --cwd <repo>` yourself before dispatch. A manual stream repeats `QUESTION_PENDING` every 2 minutes, emits `STALLED` after 15 minutes without progress, and exits after an hour without an active job with `IDLE_EXIT`. Unknown `events` and `follow` options are rejected with the supported options named.

Codex knows who started it. For `investigate` and `implement`, the worker script prepends a short note to the brief: Codex was started by a director agent rather than a human, `request_user_input` questions go to the director, other Codex tasks may be running (listed from the director's `SIBLINGS:` header) and Codex must not coordinate with them itself. On plugins that expose the `notify_director` tool, Codex can also send the director a one-line note without stopping; it arrives as a `NOTIFIED` event while the job keeps running, carrying `pending_request=<id>` when a structured question was open at that moment so the director answers it instead of sending a message. Codex tasks never talk to each other; the director relays.

All command selection, review fallbacks, and the director note live in `skills/codex-director/scripts/codex-worker.sh` (`dispatch` is `launch` plus `collect`), so the logic can be tested with `bash -n` and a stub companion.

Native next-turn queues are distinct from these mid-turn controls. Update the installed plugin and restart the Claude session to use the new broker; editing this checkout does not update installed copies.

## License

MIT
