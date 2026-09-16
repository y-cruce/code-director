# codex-director

English | [中文](README.zh-CN.md)

Make Claude Code hand off code reading, debugging, implementation, and code review to Codex. Claude keeps only three jobs: talking to the user, writing the task brief, and judging the result.

Use it when you run both Claude Code and Codex (ChatGPT subscription), Claude's quota or context is the tighter resource, and you want Claude to read fewer files and write less code.

## What it consists of

Four files and one config snippet:

| File | Purpose |
|---|---|
| `skills/codex-director/SKILL.md` | Working rules for the Claude main thread: what to delegate, how to write a brief, how to run things in parallel, how the review loop works |
| `skills/codex-director/scripts/codex-worker.sh` | All dispatch logic: picks the Codex command by MODE, prepends the director note, starts Codex through the plugin's `codex-companion.mjs`, waits, collects; `dispatch` starts a job in one call, `follow` blocks on a job's event stream until the director must act, `events` streams job events for a monitor |
| `agents/codex-task.md` | The subagent that carries one Codex task: it runs `dispatch`, then `follow`, and hands each actionable event back to the director verbatim. It is what makes a Codex task look like a Claude Code subagent: a row in the transcript, an entry in the tasks list, its own page with the live Codex trace, a completion notification |
| `docs/claude-md-snippet.md` | A routing rule for `CLAUDE.md` so that matching tasks always go through this path |

Flow:

```mermaid
sequenceDiagram
    participant U as User
    participant C as Claude main thread
    participant A as codex-task subagent (one per task)
    participant X as Codex

    U->>C: describes the task
    C->>C: loads codex-director, writes a brief
    par parallel dispatch, one background Agent call each
        C->>A: MODE: implement
        C->>A: MODE: investigate
    end
    A->>X: codex-worker.sh dispatch, then follow <job-id>
    Note over A: the running follow command is the task's page; the plugin's mod draws the live Codex trace in it
    A-->>C: DONE job=... + result (or QUESTION, NOTIFIED, STALLED, FAILED), as the agent's report
    C->>A: answers or reacts, then "continue" (the same page carries on)
    C->>X: MODE: adversarial-review (detached; reported by an event monitor)
    C->>A: MODE: continue, WRITE: yes (Codex fixes its own findings, same agent, same thread)
    A-->>C: DONE
    C->>C: runs tests, spot-checks file:line claims
    C->>U: reports
```

## Relationship to the official Codex plugin

This depends on the Codex plugin for Claude Code. Every call to Codex goes through its `codex-companion.mjs` script. The recommended install is [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc), a fork of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) that adds `task --thread <id>` (submitted upstream as [#719](https://github.com/openai/codex-plugin-cc/pull/719)); nothing else in the plugin is changed. This repo adds a layer of delegation rules and a dispatch script on top.

The plugin ships its own forwarder, `codex:codex-rescue`. The differences:

| | Official codex-rescue | codex-director (this repo) |
|---|---|---|
| Trigger | User runs `/codex:rescue`, or Claude asks for help when stuck | Claude delegates by default according to the rules; the user never has to mention Codex |
| Writes files by default | Yes (`--write`) | Depends on MODE: `investigate` is read-only, only `implement` writes |
| Long runs | Waits in the foreground and gets killed at Claude Code's 10-minute Bash limit | Starts Codex in the background; the `codex-task` subagent follows it in 9-minute slices and reports each actionable event, so Codex can run as long as it needs |
| Review input | Working-tree mode inlines the content of every untracked file into the prompt; repos with many untracked files exceed Codex's input limit | Uses branch mode when a base ref is given; otherwise counts untracked files and, above 3, falls back to a read-only task that reviews via git itself |
| Output | Verbatim | Verbatim, read with `result <job-id>` |
| Language | English | All prompts and rules are in English; neither Codex nor Claude is forced to answer in a particular language |

## Install

Prerequisites:

1. Claude Code (tested with 2.1.259)
2. Codex CLI installed and logged in (tested with 0.152.1): `npm install -g @openai/codex && codex login`
3. The Codex plugin for Claude Code, installed from this fork of the official plugin: [y-cruce/codex-plugin-cc](https://github.com/y-cruce/codex-plugin-cc). It is upstream 1.0.6 plus `task --thread <id>` ([openai/codex-plugin-cc#719](https://github.com/openai/codex-plugin-cc/pull/719)), which codex-director needs to keep one Codex thread per problem. In a terminal:

   ```bash
   claude plugin uninstall codex@openai-codex   # only if the official one is installed
   claude plugin marketplace add y-cruce/codex-plugin-cc
   claude plugin install codex@y-cruce-codex
   ```

   Then run `/codex:setup` in Claude Code and confirm it reports ready. The official plugin also works, but without `--thread` codex-worker can only resume the most recent thread (see "Thread continuity").

Install this repo:

```bash
git clone https://github.com/y-cruce/codex-director.git
cd codex-director
./install.sh
```

The script copies the agent, the skill, and the worker script into `~/.claude/`. Then append the snippet from `docs/claude-md-snippet.md` to `~/.claude/CLAUDE.md` and run `/reload-plugins` in Claude Code, or start a new session.

## Usage

No new commands. Talk to Claude as usual:

```
This endpoint returns 500 occasionally, find out why
Make order export asynchronous and send an email when it finishes
Review the changes on this branch
```

Claude loads codex-director, writes a brief, spawns a `codex-task` subagent with it, acts on the agent's reports, spot-checks, and reports. You can also name it directly: "ask codex to look into X".

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

Required header: `NAME` is a few words describing the task, truncated to 80 characters. It appears after `JOB:` in dispatch/collect output and, with a plugin supporting `task --label`, beside the job ID in status and events; older plugins print a note and launch without the label. Review commands carry the label as well.

Optional headers: `EFFORT` (`medium` / `high` / `xhigh`, default high), `MODEL` (defaults to the model in your Codex config), `BASE` (base ref for review modes), `THREAD` (the Codex thread a `continue` must resume), `SIBLINGS` (one line naming other running Codex tasks, shown to Codex), `CWD` (repository to run in).

### Thread continuity

Codex has a very large context window, and a thread keeps everything Codex has read so far. Follow-ups on the same problem are faster and more accurate inside the same thread, so the skill keeps **one Codex thread per problem**:

- Every task result comes back with a `THREAD: <id>` line.
- Any later dispatch about the same problem (more investigation, a follow-up question, implementing what was found, fixing review findings) uses `MODE: continue` with that `THREAD:` in the header.
- codex-worker checks the requested thread against the one the plugin is about to resume and refuses with `THREAD_MISMATCH` rather than silently continuing the wrong thread.

With a plugin that supports `task --thread <id>` ([openai/codex-plugin-cc#719](https://github.com/openai/codex-plugin-cc/pull/719)), codex-worker resumes exactly the requested thread, so problems can be interleaved freely. Older plugin versions can only resume the most recent finished task thread of the current Claude session in the repo; there codex-worker falls back to a candidate check, and Claude avoids starting other task-class jobs in that repo between two `continue` calls.

### Checking progress

While Codex is running, `/codex:status` lists the running and recently finished jobs in the current repo with their current phase. `/codex:result <job-id>` shows the full output of one job.

## Design decisions

**Codex output is never compressed.** Claude reads Codex's result with `result <job-id>`, unchanged. Claude's context is saved by the division of labor itself (Claude does not read files or write code), not by truncating or summarizing Codex's answer.

**One thread per problem, review only when it earns its cost.** For code changes, `implement` runs first (or `investigate` then `continue` with the implementation when the affected area is unclear). When the implementation comes back, Claude judges whether an `adversarial-review` is worth its cost for this particular change and says so either way. Findings go back to the same thread via `continue` to fix, up to three rounds.

**Parallel writes use worktrees.** Only one `implement` runs per checkout at a time. To have Codex produce two approaches, give each route its own `git worktree` and pass it as `CWD:`, and Claude picks one.

**Detached start, events instead of waits.** Task runs use native background jobs; `dispatch` checks startup for up to 10 seconds, returning early once the job is running with a thread ID or has finished. A job that fails during this check returns `STATUS: failed` with an `ERROR:` line; later completion, questions, and notes come back through the `codex-task` subagent's `follow`. Reviews start as a detached process and are reported by an event monitor.

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

For automatic corrections, write a prompt file and SendMessage the task's agent `MESSAGE_FILE: <absolute path>` (optionally add `INTERRUPT: yes`). The agent forwards it with its saved job id and repository, then resumes following from its cursor without printing the file. Alternatively run `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt]`: success prints only `MESSAGED job=<id>`; failure prints `MESSAGE_FAILED job=<id> <reason>` and exits nonzero; an unsupported plugin prints `MESSAGE_UNSUPPORTED:` and exits 2.

**Anything else sent to the agent is forwarded to Codex.** Text that is not routing is written to a file by the agent and delivered verbatim, so a correction never dies in the agent's inbox; the file form stays preferable for anything long or containing code. A bare `continue` only resumes following, and a new round requires the `DISPATCH_FILE:` / `CWD:` / `NAME:` triple. If the last report was `QUESTION`, the message must explicitly state that it has already been answered through `answer`; otherwise the agent returns `MESSAGE_REFUSED job=<id> question pending, answer it first`, because only `answer` with the question id resolves a structured question. On refusal, answer first; on failure, fix the error or update the plugin before resending.

For a structured question, the director receives a `QUESTION` report from the `codex-task` agent (or a `QUESTION` event from the monitor on that path) while Codex remains active. It supplies an answers-map JSON file, such as `{"<question-id>":{"answers":["..."]}}`, through `/codex:answer <job-id> --request-id <id> --answers-file <path>`, using the question IDs from status as keys. Questions time out after 10 minutes. `/codex:status <job-id>` exposes pending messages, questions, notifications, and interruption state.

From Bash, use `codex-worker.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the pending request, exact question IDs, and nonempty answers before sending, then checks status again; success prints `ANSWERED job=<id> request=<id>`, and failure prints `ANSWER_FAILED` with details and exits 1. `--cwd` can appear anywhere after `answer` and defaults to the current directory; relative answers-file paths resolve against that directory.

**One subagent per task, the same page for its whole life.** The director writes the dispatch text to a file and spawns a background `codex-task` agent per task whose prompt is only that file's path and the repository. The agent runs `codex-worker.sh dispatch` on the file, then blocks on `codex-worker.sh follow <job-id>`, which waits quietly (the plugin's mod draws the live Codex trace on that row) and exits when the director must act: `DONE`, `FAILED`, `QUESTION`, `NOTIFIED` or `STALLED`, each preceded by a `CURSOR:` line. The agent's report is the job id and that terminal line; it keeps the cursor to itself. The director reads the result with `result <job-id>`, so it never passes through the agent's context. After a direct `answer` / `message` call, the director messages the agent `answered, continue` / `continue`; `MESSAGE_FILE:` delivery resumes following automatically. It follows again from the cursor, so nothing is replayed or skipped and the task keeps its one page. Bash's 10-minute limit is handled inside the agent (`follow --max-seconds 540`, then `--after <cursor>`).

**An event monitor is still available.** `codex-worker.sh events --cwd <repo>` streams the same events (`DONE`, `FAILED`, `QUESTION`, `QUESTION_PENDING`, `NOTIFIED`, `STALLED`) for a Claude Code Monitor; it is the path for review modes, which start detached without a job id, and for headless runs. The plugin repeats `QUESTION_PENDING` every 2 minutes while a question is unanswered. The stream exits on its own after an hour without an active job, printing a final `IDLE_EXIT` line.

Codex knows who started it. For `investigate` and `implement`, the worker script prepends a short note to the brief: Codex was started by a director agent rather than a human, `request_user_input` questions go to the director, other Codex tasks may be running (listed from the director's `SIBLINGS:` header) and Codex must not coordinate with them itself. On plugins that expose the `notify_director` tool, Codex can also send the director a one-line note without stopping; it arrives as a `NOTIFIED` event while the job keeps running. Codex tasks never talk to each other; the director relays.

All command selection, review fallbacks, and the director note live in `skills/codex-director/scripts/codex-worker.sh` (`dispatch` is `launch` plus `collect`), so the logic can be tested with `bash -n` and a stub companion.

Native next-turn queues are distinct from these mid-turn controls. Update the installed plugin and restart the Claude session to use the new broker; editing this checkout does not update installed copies.

## License

MIT
