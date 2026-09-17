---
name: codex-director
description: A way of working where Codex is the default executor and Claude only directs. Load this skill for any task that involves reading code to understand current behavior, finding the root cause of a bug, implementing a change from requirements, reviewing a diff, or getting a second opinion, and whenever the user says "ask codex", "let codex look", or "use codex". Follow the process to dispatch work to Codex; Claude only writes the brief, judges the result, and makes the calls.
---

# Codex director mode

Premise: Codex quota is effectively unlimited. The scarce resource is the Claude main thread's context and output. Therefore:

- **Do not read files to understand code.** To learn "where is X handled" or "why does this happen", write a brief and dispatch it to Codex. Let Codex read and report back. (Trivial lookups are the exception; see "What not to delegate".)
- **Do not write large implementations yourself.** Specify what is needed, let Codex write it, and review.
- **Dispatching several routes is fine.** Run investigation and implementation in parallel for the same problem, or have Codex propose two approaches and pick one.
- **You do four things only**: talk to the user, break the task down and write briefs, judge Codex's results, and make the calls.

## Dispatching

All dispatch logic lives in `~/.claude/skills/codex-director/scripts/codex-worker.sh` (which Codex command to run, the director note, sandbox flags, review fallbacks). A task-class dispatch (`investigate`, `implement`, `continue`) goes through the `codex-task` subagent so the task is visible like any Claude Code subagent: an Agent row in the transcript, an entry in the tasks list, its own page with the live Codex trace (drawn by the Codex plugin's mod inside the running `follow` command), and a completion notification. One dispatch is two calls. First write the dispatch text to a file with the Write tool (in your scratchpad directory, one file per task, for example `<scratchpad>/codex/locate-answer-validation.md`; the script copies it into its own work directory, so several files in one folder can be dispatched at the same time):

```
MODE: investigate
NAME: locate answer validation path
EFFORT: high
CWD: /abs/path/to/repo

<brief>
```

Then one `Agent` call in the background, `subagent_type` `codex-task`, `description` the task's `NAME`, whose prompt is exactly three lines:

```
DISPATCH_FILE: <that file's absolute path>
CWD: /abs/path/to/repo
NAME: locate answer validation path
```

The agent labels every shell call with that name, so the tasks list shows `Codex · <NAME> · following` instead of a generic activity.
The brief never passes through the agent's prompt or a shell command, so the task's page shows it nowhere but in your own Write row. The subagent runs `codex-worker.sh dispatch` on that file, then `codex-worker.sh follow <job-id>`, and stays on the job until an event you must act on. Its report (delivered as the agent's completion notification) is machine output: `JOB: <id>`, then one terminal line: `DONE job=<id> [<name>] thread=<id>`, `FAILED job=<id> [<name>] thread=<id> <reason>`, `QUESTION job=<id> [<name>] request=<id> <first question>`, `QUESTION_PENDING job=<id> [<name>] request=<id> still unanswered: <first question>`, `NOTIFIED job=<id> thread=<id> [pending_request=<n>] <note>` or `STALLED job=<id> [<name>] thread=<id> <n>m without progress`. A dispatch that fails at launch comes back as the raw `STATUS: failed` / `ERROR:` output instead; fix the dispatch and spawn again. Put parallel dispatches in one message as separate Agent calls. Do not poll. Keep the agent's id together with the job id, its repository and its thread: you continue the same agent later.

The building block is still there for scripts and headless runs: `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh dispatch <<'INPUT' ... INPUT` returns within seconds with `STATUS: started`, `JOB:`, `NAME:`, `THREAD:` and sometimes a `NOTE:` line, and `codex-worker.sh follow <job-id> --cwd <repo> [--after <cursor>]` blocks and prints the same event stream the subagent reads.

A Codex task may run for any length of time. Do not re-dispatch because it is taking long. `/codex:status` lists jobs and `/codex:status <job-id>` shows pending messages, questions, notifications, and interruption state.

### Waiting: the subagent reports, you act, you send it back

The `codex-task` agent ends its turn whenever the job produced something you must act on, and its report reaches you as that agent's completion notification. Each report is one event and arrives on its own schedule; it is not user input. The bracketed name in the terminal line is the `NAME:` you gave at dispatch; use it, not the job id, when you tell the user which task an event belongs to.

- `DONE`: run `node "$(bash ~/.claude/skills/codex-director/scripts/codex-worker.sh companion)" result <job-id> --cwd <repo>` in a foreground Bash call and judge the output as usual (the agent follows with `--quiet`, so the result never passes through its context). The agent stays available for a `continue` on the same problem (below).
- `QUESTION`: run `status <job-id> --cwd <repo> --json` on the same companion to read the questions, answer them (below), then SendMessage the agent `answered, continue`. It follows the job again from its cursor; the same page continues.
- `QUESTION_PENDING`: that request was already reported once, and it is still unanswered. Run `status <job-id> --cwd <repo> --json` and look at `job.live.questions`: answer it if it is really pending (the earlier answer was not accepted), and if the list is empty just SendMessage `continue`. Never answer twice blindly.
- `NOTIFIED`: react (below), then SendMessage the agent `continue`. The job never paused. A `pending_request=<n>` field means a structured question was open when the note was written: answer that request first with `answer`, then `continue`; sending a `message` while it is pending is refused.
- `STALLED`: run `status <job-id>` at once and look at the owner process and the time of the last progress entry; a job whose owner has exited is dead even if the store still says running, so report it and re-dispatch instead of waiting. If it is alive, SendMessage the agent `continue`. Never let a silent job sit unchecked for an hour.
- `FAILED`: report the reason to the user; the agent is done with that job.
- `MESSAGE_REFUSED`: answer the pending structured question with `answer` and its question id first, then resend the message stating that it has been answered.
- `MESSAGE_FAILED` / `MESSAGE_UNSUPPORTED:`: forwarding failed; fix the reported error or update the plugin, then resend `MESSAGE_FILE:`. The agent has stopped following; do not assume delivery.

A job's history is kept whole, so a `continue` message after any of these replays nothing and skips nothing. The agent handles Bash's 10-minute limit itself (it re-follows on `TIMEOUT` without telling you), and it never answers Codex on your behalf.

Alternative when the Agent tool is not available (SDK, headless) or for review modes, which start detached without a job id: arm one Monitor per repository with the command `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh events --cwd <repo>` (description: "Codex job events in <repo>"; a worktree counts as its own repository) before the first dispatch there, dispatch with the `dispatch` subcommand, and read the same event lines from the monitor (`DONE`, `FAILED`, `QUESTION`, `NOTIFIED`, `STALLED`, plus `QUESTION_PENDING` in two forms: `request=<id> still unanswered: <first question>` when a request that was already reported comes up again, and `request=<id> <n>m unanswered, expires in <m>m: <first question>` every 2 minutes while a question stays unanswered). On `DONE` read the output with `result <job-id>`. Stop the monitor with TaskStop when every job it watched has reported; it also exits on its own after an hour without an active job, ending with `IDLE_EXIT`, after which the next dispatch needs a fresh monitor.

Sandbox: every Codex task runs without a sandbox (full read/write access and network), which is the user's standing policy; codex-worker passes `--sandbox danger-full-access` unless the header says otherwise. Read-only intent for `investigate` is stated in the brief, not enforced by the sandbox, so keep writing "read-only, do not modify files" into investigation briefs. `SANDBOX: network` (workspace-write plus network) or `SANDBOX: default` (the plugin's own read-only / workspace-write choice) narrow it for a single task; use them only when the user asks. On plugins without the `--sandbox` option the task runs in the plugin's default sandbox and cannot open sockets; a Codex report that tests could not run there is not a test failure.

Prompt format: a few header lines, a blank line, then the brief body. `NAME: <a few words>` is required in every dispatch: say what the task does in three to eight words a reader can tell apart from the other tasks (for example `NAME: worker answer subcommand`, `NAME: root cause of brand fallback`), never a job id, a mode name, or a generic word like "task"; the name is stored on the job, printed as `<job-id> [<name>]` in status listings and after `job=<id>` in every monitor line. codex-worker refuses a dispatch without it (`NAME_REQUIRED`). Add `CWD: <absolute path>` when Codex must run in a repository other than the current directory (the script inherits your working directory otherwise). Add `SIBLINGS: <one line>` when other Codex tasks you started are still running: name each with its job ID and a few words on what it does. codex-worker copies the line into the note it prepends for Codex (see "What Codex knows about you" below).

```
MODE: investigate
NAME: <what this task does>
EFFORT: high

<brief>
```

### MODE and effort

Codex runs on `gpt-6-astra` by default (set in `~/.codex/config.toml`, together with a default effort of `high`). On this model, **medium or high is enough for nearly every task**; do not set `MODEL` unless the user asks for a specific model.

| Goal | MODE | EFFORT | Notes |
|---|---|---|---|
| Scan the codebase to answer a question, locate entry points, small well-scoped edits | investigate / implement | medium | Fast; the default for anything narrow |
| Trace call chains, understand a module, implement a change from requirements | investigate / implement | high | The default for anything that spans several files |
| Find the root cause of a bug or odd behavior | investigate | high | Start here; escalate to xhigh only if the high round comes back inconclusive |
| Any follow-up on a problem that already has a thread | continue | unset | Put `THREAD: <id>` in the header; writes files only with `WRITE: yes` |
| Standard code review | review | unset | Prefer providing `BASE: <ref>`, see below |
| Challenge the approach and assumptions | adversarial-review | unset | Body is the focus text; prefer providing `BASE: <ref>` |

Picking the effort:

- **medium**: the answer lives in one or two files, or the edit is a few lines at a known location and you only delegate because the code is unfamiliar.
- **high**: everything else. Multi-file investigation, implementation from requirements, first root-cause pass.
- **xhigh**: reserved. Use it only when a `high` round already ran and came back without a clear answer, or the problem is known to be non-deterministic (concurrency, ordering, intermittent failures) and needs long reasoning over many interacting paths. Do not start a task at xhigh; when escalating, prefer `continue` in the same thread with `EFFORT: xhigh` in the header so Codex keeps what it already read.

### Review modes and untracked files

Review modes (`review`, `adversarial-review`) do not go through the `codex-task` agent: they start detached with an empty `JOB:`, so dispatch them with the `dispatch` subcommand and read their `DONE` or `FAILED` line from a Monitor (see the alternative above). Without `BASE`, the plugin uses working-tree mode and inlines the content of every untracked file into the prompt. Repos with many untracked files exceed Codex's input limit and the review fails. Two options:

- **Preferred**: commit the change to a branch first and put `BASE: <base branch>` in the header so only the committed diff is compared.
- If committing is not possible, do nothing special. codex-worker counts untracked files and, above 3, automatically falls back to a read-only task that performs the review, adding a NOTE line to its return. In that case **list the changed files in the brief body** so Codex knows what to look at.

### Thread continuity: keep one Codex thread per problem

Codex has a very large context window, and a thread keeps everything Codex has read and concluded so far. Follow-ups on the same problem are faster and more accurate when they land in the same thread, so **once a problem has a thread, every later dispatch about that problem uses `continue`**: further investigation, follow-up questions, implementing what the investigation found, and fixing review findings. Start a fresh `investigate` or `implement` only for a different problem, or when the thread has clearly gone wrong.

How it works:

- Every task-class result comes back with a `THREAD: <id>` line. Remember it together with the problem it belongs to.
- Put `THREAD: <id>` in the header of every `continue` for that problem. With a plugin that supports `task --thread` (see openai/codex-plugin-cc PR #719), codex-worker resumes exactly that thread, so several problems can be interleaved freely in one repo. With an older plugin, codex-worker verifies the thread against the one the plugin is about to resume and refuses with `THREAD_MISMATCH` otherwise; in that case, while a problem is in progress, do not dispatch other task-class jobs (`investigate`, `implement`, or a review that falls back to a task) in the same repo between two `continue` calls, because only the most recent thread can be resumed. Reviews in branch or working-tree mode are review-class and do not affect this.
- A thread belongs to the checkout it was created in. `continue` with `CWD:` pointing at a different worktree is rejected by the plugin (`Thread ... is not tracked for this repository`); to carry the work into a worktree, dispatch a fresh task there with a complete brief.
- `continue` starts a later turn after the previous job finishes. While the job is still running, use the live controls below instead of dispatching another task.
- A `continue` brief can be short: state what changed since last time and what to do next. Codex already has the background.
- Send a `continue` to the problem's existing `codex-task` agent with SendMessage (write the `MODE: continue` dispatch text with `THREAD:` to a new file, then message the agent the same three `DISPATCH_FILE:` / `CWD:` / `NAME:` lines) when that agent is still around; its page then holds the whole history of the problem. Spawn a new agent only when it is gone.

On an older plugin, parallel routes are therefore for independent problems or one-shot work, not for a problem you intend to keep iterating on.

### Live corrections and questions

**Nothing sent to the agent reaches Codex until the agent's next tool round.** The host queues messages for a busy agent and never interrupts a running tool, and the agent sits inside `follow` for up to nine minutes, so a message you send it can wait that long. Your own Bash calls are not blocked by it. Route by urgency first:

| Intent | Channel |
|---|---|
| Stop or redirect Codex now | Run `codex-worker.sh message <job-id> <prompt-file> --cwd <repo> --interrupt` yourself |
| End the job now | `cancel <job-id>` on the selected companion, yourself |
| Answer a structured question | `answer` with the request id and exact question ids, yourself |
| A correction that can wait for the agent's next round | SendMessage the task's agent `MESSAGE_FILE: <absolute path>` |
| Keep the agent following | SendMessage `continue` |
| Start a new round | SendMessage the `DISPATCH_FILE:` / `CWD:` / `NAME:` triple |

For the unhurried path, write the correction to a file and SendMessage `MESSAGE_FILE: <absolute path>` (optionally `INTERRUPT: yes`). The agent supplies its saved job id and repository, forwards the file without reading it, and resumes following after delivery. Everything you send it that is not routing is forwarded as well, inline text included; keep inline text short and free of code, since the agent writes it through a shell heredoc. If its last report was `QUESTION` or `QUESTION_PENDING`, first answer it and say "Already answered through answer" in the same message, or the agent returns `MESSAGE_REFUSED`.

For direct Bash delivery, use `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt]`. It prints only `MESSAGED job=<id>` on success, or `MESSAGE_FAILED job=<id> <reason>` on failure; unsupported plugins return `MESSAGE_UNSUPPORTED:` and exit 2. Keep the job ID with its repository and thread. Success means accepted for the next model request, not that the instruction has already been followed. The slash command `/codex:message <job-id> <text>` remains user-facing shorthand. Use the worker for automatic `message` and `answer` calls; `status` and `result` still use the selected companion with `--cwd <repo>`. Do not invoke these commands as skills.

Use `/codex:message <job-id> --interrupt <text>` when the current approach must stop. It cancels the turn and continues the same job and thread with the new instruction, retaining its original write permission. Report the returned partial changes; interruption does not undo files. Do not use this to escalate a read-only task's permissions.

On `STATUS: waiting-for-answer`, the Codex job remains running. Read the returned questions. Answer from already established facts, or ask the user when a choice or authorization is missing. Never infer permission from a factual answer. Then:

1. Take the question ids from the `status --json` output: `job.live.questions[]` lists each pending request with its `requestId` and `questions[]`, and every question has an `id`. Those ids are the only valid keys of the answers file; never make a key up or copy one from an example.
2. Write the answers file as a JSON map keyed by those ids: `{"<question-id>":{"answers":["<answer text>"]},...}`, one entry per question of the request, each with a nonempty array of nonempty strings. The broker rejects the whole request if any key is missing or unknown.
3. Deliver it with `bash ~/.claude/skills/codex-director/scripts/codex-worker.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the keys against the pending question before forwarding, forwards, and then confirms the question is gone. Run it alone in a foreground Bash call, never through a pipe or `grep`: a pipe hides the error line and replaces the exit code. It ends with one line, `ANSWERED job=<id> request=<id>` on success or `ANSWER_FAILED job=<id> request=<id> <reason>` otherwise; on `ANSWER_FAILED` fix the file and retry, the question is still pending. Do not send an ordinary message to answer a structured request.

After `ANSWERED`, SendMessage the agent `answered, continue`; it reports the next event (on the Monitor path, the monitor does). An answered request is never reported as `QUESTION` again. A `QUESTION_PENDING` line arriving after you answered means the request is still open, so the answer was not accepted: run `status <job-id> --json` and answer again; if `job.live.questions` is empty, the request is closed and you only need to `continue`. Questions time out after 10 minutes by default and interrupt the turn; report that outcome without inventing an answer. Ordinary prose questions that already ended a turn still use `continue` in the same thread. Old plugins without `message` require an update; do not pretend that live delivery succeeded.

### Notifications from Codex

On plugins that expose the `notify_director` tool, Codex can send you a one-line note while it keeps working. It reaches you as the agent's `NOTIFIED` report (or a `NOTIFIED` line on the Monitor path); the job is still running. The line carries `pending_request=<n>` when a structured question was open at the moment the note was written; answer that request before anything else, because a `message` sent while it is pending is refused. Read the note and decide: start parallel work that it makes possible (for example, a test-writing task once the root cause is known), send the job a `message` if the note changes what it should do, or do nothing. Delivered notes are acknowledged and do not come back again; `/codex:status <job-id>` shows notes that have not been delivered yet. Codex is told to use the tool only for conclusions that change the plan, blockers, or a finished phase, so treat a note as worth reading, not as routine progress.

### What Codex knows about you

For `investigate` and `implement`, codex-worker prepends a fixed note to your brief: Codex was started by a director agent, not a human; `request_user_input` questions are addressed to you; `notify_director` exists (when the plugin supports it); other Codex tasks may be running and Codex must not coordinate with them itself but tell you instead. The `SIBLINGS:` header fills in the list of running tasks. Consequences for you:

- Codex tasks never talk to each other. You are the only relay. When a new task overlaps the area of a running one, send the running job a one-line `message` saying what has started, and put the running job in the new task's `SIBLINGS:` line. Most dispatches need neither.
- A `request_user_input` from Codex is a question to you. Answer from established facts; ask the user only for choices or authorization you do not have.
- Do not repeat the note's content in the brief; write the brief as before.

### Isolate tasks that write files

Only one `implement` per checkout at a time. To run parallel edits (for example, two approaches by Codex), give each route its own worktree (`git worktree add <path> <branch>`) and put that path in `CWD:`; compare afterwards and merge the one you pick. Read-only tasks need no isolation.

## Brief template

The brief is for Codex, which has none of your conversation context. Write it completely and concretely.

```
## Goal
One sentence describing the finished state.

## Context
Key facts from the user's words; known entry files and related modules; what was tried before and why it failed.

## Constraints
- Things not to touch (config, public interfaces, unrelated files)
- Style: match surrounding code, minimal change, no incidental refactoring
- External systems: state one of "read-only, do not call" or "calling is allowed"

## Acceptance
- What counts as done: which tests must pass, which command must run, which questions must be answered
- Output requirements: conclusion + evidence (file:line) + uncertainties listed separately

## Known files (optional)
path/to/a.py  -- entry point
path/to/b.py  -- suspect
```

## Standard pipeline (code changes)

1. Write the brief. If the requirement is ambiguous, ask the user first; do not let Codex guess.
2. Dispatch `implement`. If the affected area is unclear, dispatch `investigate` first and then `continue` in that thread with the implementation (rather than a separate parallel route, so the thread keeps what it learned).
3. When the implementation returns, **decide whether a review is worth it**. Review is not a fixed step; it is your call, made on the returned result. Weigh how much could go wrong if the change is subtly wrong against what a review costs (a brief, a wait, and one more round of context), and dispatch `adversarial-review` only when the risk justifies it (intent of the change and your main concerns as the body; prefer `BASE:`, since a fallback review is task-class and would become the most recent thread). When you skip it, go straight to wrap-up and tell the user in one line that you skipped the review and why.
4. If you reviewed: for high or medium findings, dispatch `continue` with `THREAD:` and `WRITE: yes` so Codex fixes them in the same thread, then judge again whether another review round is needed. At most three rounds; step in yourself if it is still not clean.
5. Wrap up: run the tests or verification command, spot-check one or two `file:line` claims from Codex, then report to the user.

Read-only tasks (questions, investigations): one `investigate` route is enough. Follow-up questions from the user about the same topic go to `continue` with the same `THREAD:`.

## What not to delegate to Codex

**Simple tasks: do them yourself.** Delegating costs a brief, a dispatch, and a wait of at least a minute. If you can finish the task in about three tool calls without needing to understand unfamiliar code, delegating is slower than doing it. Examples: looking up one value in a file you already know, a single grep, a one-line or few-line fix at a known location, renaming, editing a config entry, running a command and reporting its output, answering from what is already in the conversation. Dispatch Codex only when the task needs reading or writing code beyond that.

- Requirements that are still undecided and need a trade-off confirmed with the user.
- Operations on live environments (production servers, ssh to remote hosts, changing configuration of running services): Codex can read scripts and propose a plan, but you perform the execution.
- Talking to the user.
- **Writing documents and artifacts (HTML pages, reports, session summaries, READMEs and other human-facing output) is done by you, not Codex.** Dispatch `investigate` first if you need facts or material; write the document yourself. This rule constrains your division of labor only; do not write it into briefs. Codex updating comments, a README, or adding an explanation while coding is its own business; do not add restrictions such as "do not write documentation".

## When the session gets long

When the context is long and early information starts getting lost, run `/codex:transfer` to turn the whole session into a Codex thread, give the user the resulting `codex resume <id>`, and let the user decide whether to continue in Codex or start a new session.

## After receiving a result

You read Codex's text with the companion's `result <job-id>`; it comes back unchanged.

- Spot-check one or two `file:line` references before trusting them; Codex is also wrong sometimes.
- On `STATUS: failed` or `CODEX_FAILED`: report the most useful log lines to the user. Do not take over and redo the whole task yourself.
- Do not auto-apply every review finding; decide first which ones are real.
