---
name: code-director
description: A way of working where another coding agent executes and Claude only directs. Load this skill for any task that involves reading code to understand current behavior, finding the root cause of a bug, implementing a change from requirements, reviewing a diff, or getting a second opinion, and whenever the user says "ask codex", "let codex look", "use codex", or names another executor such as qoder. Follow the process to dispatch the work; Claude only writes the brief, judges the result, and makes the calls.
---

# Code director mode

Premise: the scarce resource is the Claude main thread's context and output. Therefore:

- **Do not read files to understand code.** To learn "where is X handled" or "why does this happen", write a brief and dispatch it to Codex. Let Codex read and report back. (Trivial lookups are the exception; see "What not to delegate".)
- **Do not write large implementations yourself.** Specify what is needed, let Codex write it, and review.
- **Dispatching several routes is fine.** Run investigation and implementation in parallel for the same problem, or have Codex propose two approaches and pick one.
- **You do four things only**: talk to the user, break the task down and write briefs, judge Codex's results, and make the calls.

## Dispatching

All dispatch logic lives in `~/.claude/skills/code-director/scripts/dispatch.sh` (which Codex command to run, the director note, sandbox flags, review fallbacks). One dispatch is two calls. First write the dispatch text to a file with the Write tool (in your scratchpad directory, one file per task, for example `<scratchpad>/codex/locate-answer-validation.md`; the script copies it into its own work directory, so several files in one folder can be dispatched at the same time):

```
MODE: investigate
NAME: locate answer validation path
EFFORT: high
CWD: /abs/path/to/repo

<brief>
```

Then one foreground Bash call that starts it and returns in seconds:

```
bash ~/.claude/skills/code-director/scripts/dispatch.sh dispatch < <that file's absolute path>
```

It prints `STATUS: started`, `JOB:`, `NAME:`, `THREAD:` and sometimes a `NOTE:` line, or `STATUS: failed` / `ERROR:` when the dispatch itself is wrong — fix it and dispatch again. Several dispatches go in one message as separate Bash calls. Keep each job id together with its repository and its thread.

The brief never passes through a shell command, so it appears nowhere but in your own Write row.

Nothing waits on the job. The Codex plugin's tasks pane watches every job this session started and draws its live trace. For each repository with a live job, it automatically arms one Monitor running `dispatch.sh events`; the Monitor's background notification can reach you while a turn is still running. `/codex:tasks` opens the pane, `/codex:tasks <n>` or `/codex:tasks <part of a name>` switches to one, and Tab walks the list at its foot, the trace following wherever it lands.

A Codex task may run for any length of time. Do not re-dispatch because it is taking long. `/codex:status` lists jobs and `/codex:status <job-id>` shows pending messages, questions, notifications, and interruption state.

### Waiting: the pane and Monitor wake you, you act

Nothing blocks on a job. The Monitor prints one line when a job produces an event you must act on; its task notification can arrive during the current turn. The pane keeps the trace current at the same time. If no Monitor covers that repository, the pane can submit a compact `Codex tasks` prompt once the session is idle. Use the `NAME:` you gave at dispatch, not the job id, when telling the user which task something belongs to. Five kinds arrive:

- `DONE` / `job.completed`: run `node "$(bash ~/.claude/skills/code-director/scripts/dispatch.sh companion)" result <job-id> --cwd <repo>` in a foreground Bash call and judge the output as usual.
- `FAILED` / `job.failed` / `job.cancelled`: report the reason to the user.
- `QUESTION` / `question.opened`: run `status <job-id> --cwd <repo> --json` on the same companion to read the questions and answer them (below). The job stays alive, waiting.
- `NOTIFIED` / `director.notified`: a one-line note from Codex while it keeps working; react if it changes the plan. The job never paused.
- `STALLED`: the job has produced no progress for fifteen minutes. Inspect `status <job-id>`; the event does not mark the job failed.

The Monitor can deliver while you are mid-turn. A repository covered by a Monitor is excluded from the pane's prompt-submit path, so one event does not wake you twice. The pane does not report a job that was already over the first time it saw it, and it says each ending once.

To watch a job's trace as it runs, `/codex:tasks` opens the pane and `/codex:tasks <n>` or a fragment of its name switches to one. To block on a single job instead, `dispatch.sh follow <job-id> --cwd <repo> [--after <cursor>]` prints the same events and returns on the first one that needs you; it is a tool for when you want to wait, not the normal path.

The pane arms its Monitor automatically, one per repository, and re-arms it whenever it ends while a live job remains there -- the host ends one after thirty minutes, and the stream ends itself once the repository has been quiet. When the pane is not running (SDK, headless, or hooks unavailable), arm one yourself before the first dispatch with `bash ~/.claude/skills/code-director/scripts/dispatch.sh events --cwd <repo>` (description: "Codex job events in <repo>"; a worktree counts as its own repository). Read `DONE`, `FAILED`, `QUESTION`, `NOTIFIED`, `STALLED`, and the two `QUESTION_PENDING` forms from it; on `DONE` read the output with `result <job-id>`. A manually armed stream exits after an hour without an active job, ending with `IDLE_EXIT`, so arm a fresh one before the next dispatch. Defaults are `--poll-ms` 2s, `--stall-ms` 15m, `--question-remind-ms` 2m and `--exit-idle-ms` 1h. Current plugins reject unknown `events` and `follow` flags, name the supported options, and exit non-zero.

Sandbox: every Codex task runs without a sandbox (full read/write access and network), which is the user's standing policy; dispatch.sh passes `--sandbox danger-full-access` unless the header says otherwise. Read-only intent for `investigate` is stated in the brief, not enforced by the sandbox, so keep writing "read-only, do not modify files" into investigation briefs. `SANDBOX: network` (workspace-write plus network) or `SANDBOX: default` (the plugin's own read-only / workspace-write choice) narrow it for a single task; use them only when the user asks. On plugins without the `--sandbox` option the task runs in the plugin's default sandbox and cannot open sockets; a Codex report that tests could not run there is not a test failure.

Prompt format: a few header lines, a blank line, then the brief body. `NAME: <a few words>` is required in every dispatch: say what the task does in three to eight words a reader can tell apart from the other tasks (for example `NAME: worker answer subcommand`, `NAME: root cause of brand fallback`), never a job id, a mode name, or a generic word like "task"; the name is stored on the job, printed as `<job-id> [<name>]` in status listings and after `job=<id>` in every monitor line. dispatch.sh refuses a dispatch without it (`NAME_REQUIRED`). Add `CWD: <absolute path>` when Codex must run in a repository other than the current directory (the script inherits your working directory otherwise). Add `SIBLINGS: <one line>` when other Codex tasks you started are still running: name each with its job ID and a few words on what it does. dispatch.sh copies the line into the note it prepends for Codex, which only `investigate` and `implement` get, so the header does nothing on a `continue` or a review (see "What Codex knows about you" below).

```
MODE: investigate
NAME: <what this task does>
EFFORT: high

<brief>
```

### Executors

`EXECUTOR` picks the agent that runs a task-class mode (`investigate`, `implement`, `continue`). **Choose it by how hard the task is**, the same judgement the effort table below asks for:

| Task | Executor |
|---|---|
| Low to medium difficulty: the work lives in one or two files, the change follows a plan that is already settled, or the question is answered by reading a known area. Implementation counts, not just reading. | `EXECUTOR: qoder` on its default `dfmodel` |
| Hard: find a root cause, reason across many files, design the change as well as write it, or an edit whose blast radius you cannot bound | leave `EXECUTOR` out and Codex runs it |
| Many independent tasks at once | `EXECUTOR: qoder`, which is cheap enough to run in bulk |
| `review` and `adversarial-review` | Codex only; the worker refuses another executor |

`dfmodel` is cheap and fast, so a medium task costs little there and several can run at once. Codex has no quota worth managing, so it takes everything that needs the stronger reasoning. When a task sits on the line, send it to Codex: a wrong answer costs more than the credits saved. `MODEL: ultimate` puts a hard task on Qoder's strong model, which is worth it only when you have a reason to keep that thread on Qoder.

The user's own instruction wins over this table, and `CODEX_DIRECTOR_EXECUTOR` sets the default when the header is absent.

| EXECUTOR | Agent | Extra headers |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; the binary is found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `EXECUTOR_MODE` (a Qoder session mode, e.g. `yolo`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `EXECUTOR_COMMAND` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `EXECUTOR_ARGS` (a JSON array), `EXECUTOR_MODE` |

`MODEL:` names the executor's own model. On Qoder two are worth knowing:

| MODEL | When |
|---|---|
| `dfmodel` | Qoder's default. Cheap and fast, so it is the one to run many tasks on at once. |
| `ultimate` | The strong model. Use it for a hard or subtle problem, not for bulk work. |

Leave `MODEL` out and Qoder runs `dfmodel`. Qoder runs in its `yolo` permission mode by default, matching the standing policy that a dispatched task never stalls on a prompt no human is watching; `EXECUTOR_MODE:` overrides it.

What you lose when the executor is not Codex:

- `review` and `adversarial-review` are refused: they use Codex's own review, which has no ACP equivalent.
- `EFFORT` is Codex's reasoning budget and does not reach the agent. Its own rung comes from `EXECUTOR_EFFORT:` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`), which defaults to `xhigh`: the driver asks for the most the chosen model has and settles for `max` or `high` when it has no `xhigh`. Leave it out unless you want the agent to think less.
- The agent has neither `request_user_input` nor `notify_director`, so it cannot send you a mid-run note. It still asks questions through ACP elicitation, which reaches you as the usual `QUESTION` event.
- `THREAD:` works the same way, but a thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- No streaming command output, no file diff counts, no sub-agent rows: ACP does not carry them, so the live view shows fewer details than a Codex task.
- The result footer prints `Session ID:` with no `codex resume` line.

### MODE and effort

Codex runs on `gpt-6-astra` by default (set in `~/.codex/config.toml`, together with a default effort of `high`). On this model, **medium or high is enough for nearly every task**; do not set `MODEL` unless the user asks for a specific model.

| Goal | MODE | EFFORT | Notes |
|---|---|---|---|
| Scan the codebase to answer a question, locate entry points, small well-scoped edits | investigate / implement | medium | Fast; the default for anything narrow |
| Trace call chains, understand a module, implement a change from requirements | investigate / implement | high | The default for anything that spans several files |
| Find the root cause of a bug or odd behavior | investigate | high | Start here; escalate to xhigh only if the high round comes back inconclusive |
| Any follow-up on a problem that already has a thread | continue | unset | Put `THREAD: <id>` in the header; writes files only with `WRITE: yes` |
| Standard code review | review | ignored | Prefer providing `BASE: <ref>`, see below; a review never reads `EFFORT`, and the untracked fallback runs at `high` |
| Challenge the approach and assumptions | adversarial-review | unset | Body is the focus text; prefer providing `BASE: <ref>` |

Picking the effort:

- **medium**: the answer lives in one or two files, or the edit is a few lines at a known location and you only delegate because the code is unfamiliar.
- **high**: everything else. Multi-file investigation, implementation from requirements, first root-cause pass.
- **xhigh**: reserved. Use it only when a `high` round already ran and came back without a clear answer, or the problem is known to be non-deterministic (concurrency, ordering, intermittent failures) and needs long reasoning over many interacting paths. Do not start a task at xhigh; when escalating, prefer `continue` in the same thread with `EFFORT: xhigh` in the header so Codex keeps what it already read.

### Review modes and untracked files

Review modes (`review`, `adversarial-review`) start detached and `dispatch` returns an empty `JOB:`. The pane discovers their job files by Claude session and can still display them; it does not depend on the dispatch return value. The Monitor remains the reliable way to receive the terminal `DONE` or `FAILED` line and learn the job id. Without `BASE`, the plugin uses working-tree mode and inlines the content of every untracked file into the prompt. Repos with many untracked files exceed Codex's input limit and the review fails. Two options:

- **Preferred**: commit the change to a branch first and put `BASE: <base branch>` in the header so only the committed diff is compared.
- If committing is not possible, do nothing special. dispatch.sh counts untracked files and, above 3, automatically falls back to a read-only task that performs the review, adding a NOTE line to its return. In that case **list the changed files in the brief body** so Codex knows what to look at.

### Thread continuity: keep one Codex thread per problem

Codex has a very large context window, and a thread keeps everything Codex has read and concluded so far. Follow-ups on the same problem are faster and more accurate when they land in the same thread, so **once a problem has a thread, every later dispatch about that problem uses `continue`**: further investigation, follow-up questions, implementing what the investigation found, and fixing review findings. Start a fresh `investigate` or `implement` only for a different problem, or when the thread has clearly gone wrong.

How it works:

- Every task-class result comes back with a `THREAD: <id>` line. Remember it together with the problem it belongs to.
- Put `THREAD: <id>` in the header of every `continue` for that problem. With a plugin that supports `task --thread` (see openai/codex-plugin-cc PR #719), dispatch.sh resumes exactly that thread, so several problems can be interleaved freely in one repo. With an older plugin, dispatch.sh verifies the thread against the one the plugin is about to resume and refuses with `THREAD_MISMATCH` otherwise; in that case, while a problem is in progress, do not dispatch other task-class jobs (`investigate`, `implement`, or a review that falls back to a task) in the same repo between two `continue` calls, because only the most recent thread can be resumed. Reviews in branch or working-tree mode are review-class and do not affect this.
- A thread belongs to the checkout it was created in. `continue` with `CWD:` pointing at a different worktree is rejected by the plugin (`Thread ... is not tracked for this repository`); to carry the work into a worktree, dispatch a fresh task there with a complete brief.
- `continue` starts a later turn after the previous job finishes. While the job is still running, use the live controls below instead of dispatching another task.
- A `continue` brief can be short: state what changed since last time and what to do next. Codex already has the background.
- A `continue` is dispatched like any other task: write the `MODE: continue` text with `THREAD:` to a new file and run `dispatch` on it.

On an older plugin, parallel routes are therefore for independent problems or one-shot work, not for a problem you intend to keep iterating on.

### Live corrections and questions

Everything reaches a running job through the worker, in a Bash call of your own:

| Intent | Channel |
|---|---|
| Stop the current approach now, on either executor | `dispatch.sh message <job-id> <prompt-file> --cwd <repo> --interrupt` |
| A correction that can wait for this round to end, on either executor | The same with `--queue`: the message is delivered as the next turn once the current one finishes, and the agent keeps the work it was doing |
| A correction Codex should read without stopping | The same with no flag; it lands at Codex's next model request. An ACP agent (qoder) reports `midTurnSteer: false` and refuses a plain message -- use `--queue` there |
| End the job now | `cancel <job-id>` on the selected companion |
| Answer a structured question | `answer` with the request id and exact question ids |
| Start a new round on the same problem | Dispatch `MODE: continue` with `THREAD:` |

A correction goes in a file, not inline: write it with the Write tool and pass the path. Answer a pending structured question before sending an ordinary message — while one is open the message is refused, and the refusal names the request.

For direct Bash delivery, use `bash ~/.claude/skills/code-director/scripts/dispatch.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt|--queue]` (the two flags are two different intents; passing both is refused). It prints only `MESSAGED job=<id>` on success, or `MESSAGE_FAILED job=<id> <reason>` on failure; unsupported plugins return `MESSAGE_UNSUPPORTED:` and exit 2. Keep the job ID with its repository and thread. Success means accepted for the next model request, not that the instruction has already been followed. The slash command `/codex:message <job-id> <text>` remains user-facing shorthand. Use the worker for automatic `message` and `answer` calls; `status` and `result` still use the selected companion with `--cwd <repo>`. Do not invoke these commands as skills.

`--queue` is the one to reach for first: the agent finishes what it is doing, and the correction becomes the next turn in the same job and thread. Only one message waits at a time -- a second `--queue` while one is pending is refused rather than replacing it -- and a turn that ends failed, cancelled, or interrupted delivers nothing, saying so in the job's events rather than dropping the message quietly.

Use `/codex:message <job-id> --interrupt <text>` when the current approach must stop. It cancels the turn and continues the same job and thread with the new instruction, retaining its original write permission. Report the returned partial changes; interruption does not undo files. Do not use this to escalate a read-only task's permissions.

On `STATUS: waiting-for-answer`, the Codex job remains running. Read the returned questions. Answer from already established facts, or ask the user when a choice or authorization is missing. Never infer permission from a factual answer. Then:

1. Take the question ids from the `status --json` output: `job.live.questions[]` lists each pending request with its `requestId` and `questions[]`, and every question has an `id`. Those ids are the only valid keys of the answers file; never make a key up or copy one from an example.
2. Write the answers file as a JSON map keyed by those ids: `{"<question-id>":{"answers":["<answer text>"]},...}`, one entry per question of the request, each with a nonempty array of nonempty strings. The broker rejects the whole request if any key is missing or unknown.
3. Deliver it with `bash ~/.claude/skills/code-director/scripts/dispatch.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the keys against the pending question before forwarding, forwards, and then confirms the question is gone. Run it alone in a foreground Bash call, never through a pipe or `grep`: a pipe hides the error line and replaces the exit code. It ends with one line, `ANSWERED job=<id> request=<id>` on success or `ANSWER_FAILED job=<id> request=<id> <reason>` otherwise; on `ANSWER_FAILED` read the reason before retrying: a validation failure (bad keys, bad shape, no such request) means nothing was sent and the question is untouched, but `still pending after answer` is reported after the forward already succeeded, so answering again answers twice. On that one, run `status --json` and only answer again if the request is really still listed. Do not send an ordinary message to answer a structured request.

After `ANSWERED` the job carries on by itself and the pane reports its next event. An answered request is never reported again. A `QUESTION_PENDING` line on the Monitor path arriving after you answered means the request is still open, so the answer was not accepted: run `status <job-id> --json` and answer again; if `job.live.questions` is empty, the request is closed and there is nothing to do. Questions time out after 10 minutes by default and interrupt the turn; report that outcome without inventing an answer. Ordinary prose questions that already ended a turn still use `continue` in the same thread. Old plugins without `message` require an update; do not pretend that live delivery succeeded.

### Notifications from Codex

On plugins that expose the `notify_director` tool, Codex can send you a one-line note while it keeps working. It reaches you as a `director.notified` line from the pane (or a `NOTIFIED` line on the Monitor path); the job is still running. The line carries `pending_request=<n>` when a structured question was open at the moment the note was written; answer that request before anything else, because a `message` sent while it is pending is refused. Read the note and decide: start parallel work that it makes possible (for example, a test-writing task once the root cause is known), send the job a `message` if the note changes what it should do, or do nothing. Delivered notes are acknowledged and do not come back again; `/codex:status <job-id>` shows notes that have not been delivered yet. Codex is told to use the tool only for conclusions that change the plan, blockers, or a finished phase, so treat a note as worth reading, not as routine progress.

### What Codex knows about you

For `investigate` and `implement`, dispatch.sh prepends a fixed note to your brief: Codex was started by a director agent, not a human; `request_user_input` questions are addressed to you; `notify_director` exists (when the plugin supports it); other Codex tasks may be running and Codex must not coordinate with them itself but tell you instead. The `SIBLINGS:` header fills in the list of running tasks. Consequences for you:

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
