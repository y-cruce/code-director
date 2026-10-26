---
name: code-director
description: A way of working where another coding agent executes and Claude only directs. Load this skill for any task that involves reading code to understand current behavior, finding the root cause of a bug, implementing a change from requirements, reviewing a diff, or getting a second opinion, and whenever the user says "ask codex", "let codex look", "use codex", or names another executor such as qoder or dsh. Follow the process to dispatch the work; Claude only writes the brief, judges the result, and makes the calls.
---

# Code director mode

Premise: the scarce resource is the Claude main thread's context and output. Therefore:

- **Do not read files to understand code.** To learn "where is X handled" or "why does this happen", write a brief and dispatch it to Codex. Let Codex read and report back. (Trivial lookups are the exception; see "What not to delegate". Checking the `file:line` a review finding cites is judging, not exploring; see "Judging review findings".)
- **Do not write large implementations yourself.** Specify what is needed, let Codex write it, and review.
- **Dispatch whole tasks.** One task goes from reading the code to a verified result; do not split a problem into explore, plan and implement stages handed to different jobs.
- **Run independent work in parallel.** A job takes minutes to come back, and running jobs one after another leaves that time idle. Whenever parts of the work do not need each other's results, dispatch them together, and keep working while they run.
- **Dispatch work whose result you can check.** Every brief carries acceptance criteria. An implementation comes back as a diff and test output; an investigation comes back with `file:line` or command output behind each conclusion. A summary with nothing to check it against is not a basis for a decision.
- **You do four things only**: talk to the user, break the task down and write briefs, judge Codex's results, and make the calls.

## Responsibilities

| Area | Director | Executor | `context.sh` |
|---|---|---|---|
| Dispatch | Choose a direct answer, an existing thread, or a new task; find prior conclusions first | Execute the brief | `find` includes the source thread |
| Brief | Give the goal, acceptance criteria and task-specific context; reference existing conclusions by ID | Follow the brief | — |
| Rules | Fix recurring gaps in memory, or draft repository AGENTS.md changes for user confirmation before committing | Read the files listed by `rules` before work | Lists Claude-loaded rules Codex does not discover and the memory index |
| Conclusions | Check evidence, `verify` or `retract`, and resolve conflicts | `find`, recheck file:line before citing, and `save` useful conclusions; name corrected entries with `--supersedes` | Records commit, file blobs and source; flags possible staleness |
| Memory | Sole writer of user preferences, decisions and corrections, following existing memory rules | Read only; return suggested memories | Lists the index when available |
| Siblings | Sole relay: forward entry IDs or send `message --queue` | Report cross-task facts to the director | — |
| Delivery | Check evidence and report to the user | Self-check within authorized scope; return conclusions, evidence, check results and saved IDs | — |
| Summaries and verification | Own phase/session summaries and entry verification | Do not write summaries, write memory, or verify your own entries | — |

## Shared context

`rules --from <startup>` lists `CLAUDE.md` files above the target repository, including common ancestors of sibling worktrees and directories between startup and repository root. Inside the repository, it lists `CLAUDE.md` only where neither `AGENTS.md` nor `AGENTS.override.md` exists. Each listed file is followed by existing whole-line `@path` imports (relative to that file, with `~/` supported), expanded one level and deduplicated in order. Standalone ancestor `AGENTS.md` and `AGENTS.override.md` files are not listed. `--memory <index>` appends an existing memory index.

Use `bash ~/.claude/skills/code-director/scripts/context.sh find <keywords>` before writing a brief. `find --kind repo-map` locates the repository map; `show <id>` reads an entry. Pass `--cwd <repo>` when outside the assigned repository. Briefs reference existing conclusions by ID instead of repeating them. Follow up with the source thread when it belongs to the current checkout; otherwise start a new task with the relevant IDs. Reviews use a fresh thread and name any entries they cite.

When judging a result, check its evidence and use `verify <id>` or `retract <id> --reason <reason>`. Verification changes status, retaining the recorded file blobs; a changed file remains marked "可能过期". Relay conclusions to siblings by ID. Save user preferences, decisions and corrections in the director's memory under its existing rules; executors only suggest what to remember.

Entries live in `<git-common-dir>/agent-context/entries/`, shared by the repository's worktrees and outside tracked files. Each Markdown entry records its kind, status, commit, file blobs and source (`CODEX_THREAD_ID` when available, or `--source`). Executors save reusable repository maps, root causes, code paths, pitfalls and decisions with file:line evidence. Ordinary progress and one-off details stay in the task result.

If two or more tasks repeat the same mistaken assumption or lack the same prerequisite, fix the gap once in memory, or draft a repository AGENTS.md change and obtain user confirmation before committing it. Dispatch one task to verify the correction before dispatching the rest.

## Dispatching

All dispatch logic lives in `~/.claude/skills/code-director/scripts/dispatch.sh` (which Codex command to run, the director note, sandbox flags, review fallbacks).

**With the Codex plugin's tools (1.4.48 or later), one dispatch is one call.** When `mcp__codex__dispatch` is in your tool list, use it and its siblings instead of Bash. Every header below is a field of its own: `mode`, `name` and `cwd` are required, `brief` holds the body, and `thread`, `base`, `write` (true for `WRITE: yes`), `effort`, `model`, `siblings`, `sandbox`, `executor`, `executor_mode`, `executor_effort`, `executor_command`, `executor_args` (an array of strings) and `executor_permissions` are filled only when the rules below call for that header. The tool runs `dispatch.sh dispatch` with the brief on stdin and returns the same lines. Several dispatches go in one message as separate tool calls. The other tools replace the Bash calls named later in this skill:

| Tool | Replaces |
|---|---|
| `mcp__codex__message` (`job`, `cwd`, `text`, `delivery`: `queue`, `steer` or `interrupt`) | writing a prompt file and running `dispatch.sh message` (`steer` is the call with no flag) |
| `mcp__codex__answer` (`job`, `cwd`, `request`, `answers` as the JSON map) | writing an answers file and running `dispatch.sh answer` |
| `mcp__codex__result` (`job`, `cwd`) | `node "$(… dispatch.sh companion)" result <job-id> --cwd <repo>` |
| `mcp__codex__status` (`cwd`, optional `job`, optional `detail`) | `status [<job-id>] --cwd <repo> --brief` on the companion; `detail: true` is `--json` |
| `mcp__codex__tasks` (optional `query`, `cwd`, `all`, `days`, `limit`) | a compact thread list across repositories; defaults to this Claude session, newest 20 first |
| `mcp__codex__cancel` (`job`, `cwd`) | `cancel <job-id> --cwd <repo>` on the companion. TaskStop cannot stop a Codex job |

Use `mcp__codex__tasks` to find a thread to continue or check what this session has running. Each thread appears once with its name, thread id (`pending` until known), executor, status, latest job and repository; queued follow-up rounds share that line. `query` is a case-insensitive name substring, `cwd` limits the repository, `limit` accepts 1–100 (default 20), and `all: true` includes other sessions' tasks created in the last 3 days with an `other session=<id>` marker. Set `days` to a positive integer to widen that window. This session's threads have no age limit. A final line counts older matches that were not shown. The first listing migrates older unindexed jobs once; later listings read this session's index. Indexes idle for 7 days expire; job records and state directories remain available.

A failed call comes back as a tool error carrying the script's own line (`NAME_REQUIRED`, `MESSAGE_FAILED …`, `ANSWER_FAILED …`), read the same way as below. Everything else in this skill (worktrees, `pane`, `follow`, `events`) stays a Bash call.

**Without those tools** (an older plugin, or a session where mods do not load), one dispatch is two calls. First write the dispatch text to a file with the Write tool (in your scratchpad directory, one file per task, for example `<scratchpad>/codex/locate-answer-validation.md`; the script copies it into its own work directory, so several files in one folder can be dispatched at the same time):

```
MODE: investigate
NAME: locate answer validation path
CWD: /abs/path/to/repo

<brief>
```

Then one foreground Bash call that starts it and returns in seconds:

```
bash ~/.claude/skills/code-director/scripts/dispatch.sh dispatch < <that file's absolute path>
```

Either way it prints `STATUS: started`, `JOB:`, `NAME:`, `THREAD:` and sometimes a `NOTE:` line, or `STATUS: failed` / `ERROR:` when the dispatch itself is wrong — fix it and dispatch again. Several dispatches go in one message as separate Bash calls. Keep each job id together with its repository and its thread.

The brief never passes through a shell command, so it appears nowhere but in your own tool call or Write row.

Nothing waits on the job. The Codex plugin's tasks pane watches every job this session started and draws its live trace. For each repository with a live job, it automatically arms one Monitor running `dispatch.sh events`; the Monitor's background notification can reach you while a turn is still running. `/codex:tasks` opens the pane, `/codex:tasks <n>` or `/codex:tasks <part of a name>` switches to one, and Tab walks the list at its foot, the trace following wherever it lands.

A Codex task may run for any length of time. Do not re-dispatch because it is taking long. `/codex:status` lists jobs and `/codex:status <job-id>` shows pending messages, questions, notifications, and interruption state; those are for the user.

**Status is not how you follow jobs.** Every event you must act on wakes you by itself, so a quiet job needs nothing from you. On a periodic check-in (a goal check-in, a loop tick) or when the user asks how the tasks are going, answer from the events you have received and what you dispatched; do not call status to refresh. Call it only in these cases, and always for one job with the brief form (`mcp__codex__status` with `job`, or `status <job-id> --cwd <repo> --brief`, plugin 1.4.56 and later):

- a `STALLED` line for that job;
- after answering: `ANSWER_FAILED ... still pending after answer`, or a `QUESTION_PENDING` line arriving after `ANSWERED`;
- a question line without `ids=` or cut with `…` (an older plugin, or a question longer than the line keeps);
- the user asks about one specific job, or a job you expect to be over has sent nothing.

The brief form is a few lines: the job's state, any pending question in full with its ids and options, undelivered notes, and its last three progress lines. Without `job` it lists one line per active job and the last five finished ones. Use `detail: true` (`--json`) only when debugging the plugin; it returns the whole status, every thread in the repository included, and costs tens of thousands of characters.

### Waiting: the pane and Monitor wake you, you act

Nothing blocks on a job. The Monitor prints one line when a job produces an event you must act on; its task notification can arrive during the current turn. The pane keeps the trace current at the same time. If no Monitor covers that repository, the pane can submit a compact `Codex tasks` prompt once the session is idle. Use the `NAME:` you gave at dispatch, not the job id, when telling the user which task something belongs to. Five kinds arrive:

- `DONE` / `job.completed`: run `node "$(bash ~/.claude/skills/code-director/scripts/dispatch.sh companion)" result <job-id> --cwd <repo>` in a foreground Bash call and judge the output as usual. A review's `DONE` line ends with `report=<path>`: read that Markdown file with the Read tool instead; it holds the review's full conclusions.
- `FAILED` / `job.failed` / `job.cancelled`: report the reason to the user.
- `QUESTION` / `question.opened`: the line names the request and the question ids (`request=<id> ids=...`) and, from plugin 1.4.55, carries every question in full with its options and their consequences (`[id] question Options: label (consequence); ...`, several questions separated by ` | `). Answer from the line (below); read `status <job-id> --cwd <repo> --brief` only on an older plugin, and `--json` only when even that ends cut with `…`. The job stays alive, waiting.
- `NOTIFIED` / `director.notified`: a one-line note from Codex while it keeps working: something you must act on, or something to relay to another running task. The job never paused.
- `STALLED`: the job has produced no progress for fifteen minutes. Inspect `status <job-id> --brief`; the event does not mark the job failed.

The Monitor can deliver while you are mid-turn. A repository covered by a Monitor is excluded from the pane's prompt-submit path, so one event does not wake you twice. The pane does not report a job that was already over the first time it saw it, and it says each ending once.

To watch a job's trace as it runs, `/codex:tasks` opens the pane and `/codex:tasks <n>` or a fragment of its name switches to one. To block on a single job instead, `dispatch.sh follow <job-id> --cwd <repo> [--after <cursor>]` prints the same events and returns on the first one that needs you; it is a tool for when you want to wait, not the normal path.

When the pane shows a row as running that should be over, or a row you no longer need, clean it with `bash ~/.claude/skills/code-director/scripts/dispatch.sh pane` instead of experimenting. `pane list` prints each row with the pane's status next to the job file's status on disk, marks the ones that disagree `STALE`, and names the files it read; `pane refresh` makes the pane rebuild its rows from disk; `pane forget <n | part of a name | task id>` hides one row. None of them touch job files. The pane answers within a few seconds; `did not answer` means the pane is not running in this session, so tell the user rather than retrying. `/codex:tasks refresh` and `/codex:tasks forget <...>` are the same actions for the user.

When Claude Code was started with the Codex plugin among its channels (`--channels` or `--dangerously-load-development-channels plugin:codex@<marketplace>`, plugin 1.4.58+), job events arrive as `<channel source="plugin:codex:director" event="..." job="...">` messages instead: `job_completed`, `job_failed`, `job_cancelled`, `question_opened` (with the request and question ids) and `director_notified`. Treat each exactly like the matching Monitor line: on a completion read the output with `result`, answer a question, weigh a note. The `job` attribute is the job id. No Monitor is armed then, and none expires, so never arm one yourself either.

Otherwise the pane arms its Monitor automatically, one per repository, and re-arms it whenever it ends while a live job remains there -- the host ends one after thirty minutes, and the stream ends itself once the repository has been quiet. The pane drops the expiry and idle-exit notices of the watches it armed, so their endings never reach you; job events and a failed watch still do. Never arm one yourself while the pane is running: the pane is already covering that repository, and a second watch on it reports every event twice and wakes you when it expires. Only when the pane is not running at all (SDK, headless, or hooks unavailable) arm one before the first dispatch with `bash ~/.claude/skills/code-director/scripts/dispatch.sh events --cwd <repo>` (description: "Codex job events in <repo>"; a worktree counts as its own repository). Read `DONE`, `FAILED`, `QUESTION`, `NOTIFIED`, `STALLED`, and the two `QUESTION_PENDING` forms from it; on `DONE` read the output with `result <job-id>`. A manually armed stream exits after an hour without an active job, ending with `IDLE_EXIT`, so arm a fresh one before the next dispatch. Defaults are `--poll-ms` 2s, `--stall-ms` 15m, `--question-remind-ms` 2m and `--exit-idle-ms` 1h. Current plugins reject unknown `events` and `follow` flags, name the supported options, and exit non-zero.

Sandbox: every Codex task and review runs without a sandbox (full read/write access and network), which is the user's standing policy; dispatch.sh passes `--sandbox danger-full-access` unless the header says otherwise. Reviews are not restricted from writing either: the reviewer may build, run tests and write scratch files to verify its findings, so a review brief does not say "read-only". Read-only intent for `investigate` is stated in the brief, not enforced by the sandbox, so keep writing "read-only, do not modify files" into investigation briefs. `SANDBOX: network` (workspace-write plus network) or `SANDBOX: default` (the plugin's own read-only / workspace-write choice) narrow it for a single task; use them only when the user asks. On plugins without the `--sandbox` option (for reviews: before 1.4.47) the task runs in the plugin's default sandbox and cannot open sockets; a Codex report that tests could not run there is not a test failure.

Prompt format: a few header lines, a blank line, then the brief body. `NAME: <a few words>` is required in every dispatch: say what the task does in three to eight words a reader can tell apart from the other tasks (for example `NAME: worker answer subcommand`, `NAME: root cause of brand fallback`), never a job id, a mode name, or a generic word like "task"; the name is stored on the job, printed as `<job-id> [<name>]` in status listings and after `job=<id>` in every monitor line. dispatch.sh refuses a dispatch without it (`NAME_REQUIRED`). Add `CWD: <absolute path>` when Codex must run in a repository other than the current directory (the script inherits your working directory otherwise). Add `SIBLINGS: <one line>` when other Codex tasks you started are still running: name each with its job ID and a few words on what it does. dispatch.sh copies the line into the note it prepends for Codex, which only `investigate` and `implement` get, so the header does nothing on a `continue` or a review (see "What Codex knows about you" below).

```
MODE: investigate
NAME: <what this task does>

<brief>
```

### Executors and models

One executor carries every task: Codex on `gpt-6-sol` (set in `~/.codex/config.toml`). Implementation, investigation, root cause, review and second opinions all go there, so a brief names neither `EXECUTOR` nor `MODEL`. For a review or a second opinion, a fresh thread is what keeps the judgment independent of the work it judges.

The one other choice is `MODEL: luna`, for bulk mechanical work: a rename across many files, the same edit applied in dozens of places, boilerplate. The test is whether tests or the diff alone can confirm the result. If they can, `luna` (`gpt-6-luna`, run at `max` effort unless `EFFORT:` says otherwise) is enough and costs next to nothing; if judgment is needed to tell whether it is right, leave `MODEL` out.

An explicit `EXECUTOR:` or `MODEL:` header is passed through as written; write one only when the user asks for a specific executor or model.

| EXECUTOR | Agent | Extra headers |
|---|---|---|
| `codex` (default) | Codex through the plugin's app-server | — |
| `qoder` | qodercli over ACP; the binary is found on PATH, then `~/.qoder/entry/qoder`, or `CODEX_DIRECTOR_QODER_COMMAND` | `EXECUTOR_MODE` (a Qoder session mode, e.g. `yolo`) |
| `dsh` | DeepSeek Harness over ACP (`dsh --profile acp`); executable from `EXECUTOR_COMMAND`, `$CODEX_DIRECTOR_DSH_COMMAND`, then PATH | `EXECUTOR_ARGS` (override the launch arguments), `EXECUTOR_PERMISSIONS` (`allow-once` or `ask`) |
| `acp` | Any other agent speaking the Agent Client Protocol on stdio | `EXECUTOR_COMMAND` (or `$CODEX_COMPANION_ACP_COMMAND`; one of them is required), `EXECUTOR_ARGS` (a JSON array), `EXECUTOR_MODE` |

On Qoder, `MODEL:` names Qoder's own model (`dfmodel`, `fast`, `ultimate`). Without it a task runs on the default model in Qoder's own settings; `MODE: continue` keeps the model its thread was created on. Qoder runs in its `yolo` permission mode by default, matching the standing policy that a dispatched task never stalls on a prompt no human is watching; `EXECUTOR_MODE:` overrides it.

On DSH, leave `MODEL` out to keep its configured model; an explicit value must be an advertised ACP model id. DSH has no session modes: do not send `EXECUTOR_MODE`. Its default `EXECUTOR_PERMISSIONS: allow-once` selects only the offered one-shot allow option; `ask` forwards permission choices to you. Start with `EXECUTOR: dsh`, continue with `MODE: continue`, the returned `THREAD`, and the same command/profile. The worker owns its stdio independently of the foreground dispatch. When a round and its queue finish, that process closes; the next dispatch restores the same conversation through `session/resume`. The plugin replays its own saved events because DSH resume does not replay old notifications. Use `message --queue` or `--interrupt`; DSH does not accept a second in-flight prompt or mid-turn steering.

What you lose when the executor is not Codex:

- `review` and `adversarial-review` are refused: they use Codex's own review, which has no ACP equivalent.
- `EFFORT` is Codex's reasoning budget and does not reach the agent. Its own rung comes from `EXECUTOR_EFFORT:` (or `$CODEX_DIRECTOR_EXECUTOR_EFFORT`), which defaults to `xhigh`: the driver asks for the most the chosen model has and settles for `max` or `high` when it has no `xhigh`. Leave it out unless you want the agent to think less.
- The agent has neither `request_user_input` nor `notify_director`, so it cannot send you a mid-run note. It still asks questions through ACP elicitation, which reaches you as the usual `QUESTION` event.
- `THREAD:` works the same way, but a thread belongs to the executor that created it: a Qoder session id cannot be resumed as a Codex thread.
- No streaming command output, no file diff counts, no sub-agent rows: ACP does not carry them, so the live view shows fewer details than a Codex task.
- The result footer prints `Session ID:` with no `codex resume` line.

### MODE and effort

dispatch.sh passes no effort unless the header sets `EFFORT:`. A new thread then runs at `model_reasoning_effort` from `~/.codex/config.toml`, and a `continue` keeps the level its thread last ran at. Leave `EFFORT` out for nearly every task.

| Goal | MODE | Notes |
|---|---|---|
| Answer a question, locate code, find the root cause of a bug | investigate | Read-only intent goes in the brief |
| Implement a change from requirements | implement | |
| Any follow-up on a problem that already has a thread | continue | Put `THREAD: <id>` in the header; writes files only with `WRITE: yes` |
| Standard code review | review | Prefer providing `BASE: <ref>`, see below; a review never reads `EFFORT` |
| Challenge the approach and assumptions | adversarial-review | Body is the focus text; prefer providing `BASE: <ref>` |

Set `EFFORT:` for a problem that a round at the configured level already came back unclear on, or one known to be non-deterministic (concurrency, ordering, intermittent failures). Escalate with `continue` in the same thread so Codex keeps what it already read; the thread stays at that level for later `continue` rounds.

### Review modes and untracked files

Review modes (`review`, `adversarial-review`) start detached and `dispatch` returns an empty `JOB:`. The pane discovers their job files by Claude session and can still display them; it does not depend on the dispatch return value. The Monitor remains the reliable way to receive the terminal `DONE` or `FAILED` line and learn the job id. Without `BASE`, the plugin uses working-tree mode and inlines the content of every untracked file into the prompt. Repos with many untracked files exceed Codex's input limit and the review fails. Two options:

- **Preferred**: commit the change to a branch first and put `BASE: <base branch>` in the header so only the committed diff is compared.
- If committing is not possible, do nothing special. dispatch.sh counts untracked files and, above 3, automatically falls back to a task that performs the review and writes its full report to the file named in the NOTE line of its return; read that file once the task is done. In that case **list the changed files in the brief body** so Codex knows what to look at.

Review results come back as files: the plugin writes each review's full output to `<job-id>.review.md` next to the job record and appends `report=<path>` to the `DONE` line. Read the conclusions from that file rather than from the dispatch return or the Monitor line.

A review keeps its Codex thread (the `thread=` field of its `DONE` line). When a finding needs more than the report gives (evidence, a reproduction, the reviewer's reasoning, or a longer write-up), dispatch `continue` with `THREAD: <review thread>` and ask for it there, naming a file to write it to; the reviewer still has the diff and its own analysis in context. Fixes still go to the implementation thread, so the review stays independent of the work it judged.

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
| A correction Codex should read without stopping | The same with no flag; it lands at Codex's next model request. An ACP agent (qoder or dsh) reports `midTurnSteer: false` and refuses a plain message -- use `--queue` there |
| End the job now | `cancel <job-id>` on the selected companion |
| Answer a structured question | `answer` with the request id and exact question ids |
| Start a new round on the same problem | Dispatch `MODE: continue` with `THREAD:` |

A correction goes in a file, not inline: write it with the Write tool and pass the path. Answer a pending structured question before sending an ordinary message — while one is open the message is refused, and the refusal names the request.

For direct Bash delivery, use `bash ~/.claude/skills/code-director/scripts/dispatch.sh message <job-id> <prompt-file> --cwd <repo> [--interrupt|--queue]` (the two flags are two different intents; passing both is refused). It prints only `MESSAGED job=<id>` on success -- with `queued=<id>` appended for `--queue`, naming the job the queued turn will run as, so its `DONE` is recognizable when it arrives -- or `MESSAGE_FAILED job=<id> <reason>` on failure; unsupported plugins return `MESSAGE_UNSUPPORTED:` and exit 2. Keep the job ID with its repository and thread. Success means accepted for the next model request, not that the instruction has already been followed. The slash command `/codex:message <job-id> <text>` remains user-facing shorthand. Use the worker for automatic `message` and `answer` calls; `status` and `result` still use the selected companion with `--cwd <repo>`. Do not invoke these commands as skills.

`--queue` is the one to reach for first: the agent finishes what it is doing, and the correction becomes the next turn in the same job and thread. Only one message waits at a time -- a second `--queue` while one is pending is refused rather than replacing it -- and a turn that ends failed, cancelled, or interrupted delivers nothing, saying so in the job's events rather than dropping the message quietly.

Use `/codex:message <job-id> --interrupt <text>` when the current approach must stop. It cancels the turn and continues the same job and thread with the new instruction, retaining its original write permission. Report the returned partial changes; interruption does not undo files. Do not use this to escalate a read-only task's permissions.

On `STATUS: waiting-for-answer`, the Codex job remains running. Read the returned questions. Answer from already established facts, or ask the user when a choice or authorization is missing. Never infer permission from a factual answer. When the question does not give you enough to decide, do not guess and do not pass a half-understood choice to the user: answer with free text (any answer outside the offered options is accepted) naming exactly what Codex must add, and it asks again with that context. Then:

1. Take the request id and question ids from the question line itself: it carries `request=<id> ids=<id>,<id>` (from plugin 1.4.50). Without `ids=` on the line (an older plugin), read them from `status <job-id> --brief`, whose `QUESTION request=<id> ids=...` line lists them (on a plugin without `--brief`, `status --json`: `job.live.questions[]`, each question's `id`). Those ids are the only valid keys of the answers file; never make a key up, copy one from an example, or send a placeholder key to learn the ids from the error.
2. Write the answers file as a JSON map keyed by those ids: `{"<question-id>":{"answers":["<answer text>"]},...}`, one entry per question of the request, each with a nonempty array of nonempty strings. The broker rejects the whole request if any key is missing or unknown.
3. Deliver it with `bash ~/.claude/skills/code-director/scripts/dispatch.sh answer <job-id> <request-id> <answers-file> --cwd <repo>`. It checks the keys against the pending question before forwarding, forwards, and then confirms the question is gone. Run it alone in a foreground Bash call, never through a pipe or `grep`: a pipe hides the error line and replaces the exit code. It ends with one line, `ANSWERED job=<id> request=<id>` on success or `ANSWER_FAILED job=<id> request=<id> <reason>` otherwise; on `ANSWER_FAILED` read the reason before retrying: a validation failure (bad keys, bad shape, no such request) means nothing was sent and the question is untouched, but `still pending after answer` is reported after the forward already succeeded, so answering again answers twice. On that one, run `status <job-id> --brief` and only answer again if the request is really still listed. Do not send an ordinary message to answer a structured request.

After `ANSWERED` the job carries on by itself and the pane reports its next event. An answered request is never reported again. A `QUESTION_PENDING` line on the Monitor path arriving after you answered means the request is still open, so the answer was not accepted: run `status <job-id> --brief` and answer again; if it shows no `QUESTION` line, the request is closed and there is nothing to do. Questions time out after 10 minutes by default and interrupt the turn; report that outcome without inventing an answer. Ordinary prose questions that already ended a turn still use `continue` in the same thread. Old plugins without `message` require an update; do not pretend that live delivery succeeded.

### Notifications from Codex

On plugins that expose the `notify_director` tool, Codex can send you a one-line note while it keeps working. It reaches you as a `director.notified` line from the pane (or a `NOTIFIED` line on the Monitor path); the job is still running. The line carries `pending_request=<n>` when a structured question was open at the moment the note was written; answer that request before anything else, because a `message` sent while it is pending is refused. Read the note and act: clear the blocker or make the decision it asks for, relay it with a `message` to the running task that needs it, start parallel work it makes possible, or send the job a `message` if it changes what that job should do. Delivered notes are acknowledged and do not come back again; `/codex:status <job-id>` shows notes that have not been delivered yet. Codex is told to use the tool only when you must act or relay, never for progress, so ordinary progress never reaches you; the pane shows it if you or the user want to look.

### What Codex knows about you

For `investigate` and `implement`, dispatch.sh prepends a note to your brief: Codex was started by a director agent, not a human; `request_user_input` questions are addressed to you; `notify_director` exists (when the plugin supports it); other Codex tasks may be running and Codex must not coordinate with them itself but tell you instead. It then names the `codex-executor` skill, which `install.sh` links into `${CODEX_HOME:-$HOME/.codex}/skills` (a non-Codex executor gets its absolute path to read). The skill carries the working rules (self-check, ask instead of substituting, no summaries or memory writes), the shared-context procedure (`context.sh rules`, then `find`, a repository map saved when absent) and the reply format with saved IDs and suggested memories. The note adds the startup directory from the session transcript (falling back to the session ID) and its memory index when present; when unavailable, repository context still works. The `SIBLINGS:` list comes last, just before the brief. Consequences for you:

- Codex tasks never talk to each other. You are the only relay. When a new task overlaps the area of a running one, send the running job a one-line `message` saying what has started, and put the running job in the new task's `SIBLINGS:` line. Most dispatches need neither.
- A `request_user_input` from Codex is a question to you. Answer from established facts; ask the user only for choices or authorization you do not have.
- Do not repeat the note's content in the brief; write the brief as before.

### Isolate tasks that write files

Only one writer per checkout at a time, including the director. For parallel edits, the director creates one worktree per route before dispatch and puts its absolute path in `CWD:`. On macOS/APFS prefer the plugin's clone helper:

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree /abs/source-repo /abs/new-worktree worker/topic
```

This requires a plugin shipping `scripts/worktree.mjs`, plus Python 3 on macOS for native `clonefile`. With an older plugin, use `git worktree add -b worker/topic /abs/new-worktree <base-sha>` instead; never copy an existing `.git` file. The helper pins source HEAD, registers fresh Git metadata, and clones tracked files with copy-on-write where supported. Source edits and missing files are checked out from the pinned commit; untracked and ignored files, including installed dependencies and build outputs, are not copied. Keep the source stable during creation. Check the returned `cwd`, `branch`, `base`, `clonedFiles`, `copiedFiles` and `checkoutFiles`: ordinary copies and Git checkouts do not prove APFS savings.

Submodules and checked removal require plugin 1.4.45 or later. Git submodules, including nested ones, are initialized at the commits recorded by the pinned parent. Each gets its own Git directory, index and object store, without borrowing the source's objects. Available source submodules supply local clones; otherwise Git clones from the configured URL. Pinned commits missing locally are fetched from that URL even if the source is initialized, requiring normal network access and permissions. Existing object files also use copy-on-write when possible. `submodules` lists each path, commit, source and `fetchedFromRemote`; `clonedObjectFiles` and `copiedObjectFiles` count object-file clone attempts separately from tracked files. Missing access or objects fails creation and retains the incomplete directory for inspection; do not dispatch into it. Git's normal submodule initialization can add registrations to the main repository's shared config.

Executors stay in their assigned directory. Before building, check symlinks and absolute paths; install dependencies there or use repository-supported immutable caches. Do not hard-link writable files or point several writers at the same dependency/output directory. Reuse an idle worktree when its branch and contents fit the next task. Read-only source investigations can share a repository using a pinned SHA; parallel tests that write files need their own worktree too.

After judging the result and integrating the chosen commits, stop the task and its builds, then remove it with `bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree remove /abs/source-repo /abs/worktree`. This checks the parent and every submodule for uncommitted, untracked and ignored files, and refuses deletion while a submodule has new commits outside its recorded initial refs and remote-tracking refs, including commits retained only by reflogs after reset. Preserve or push those commits first. The helper handles Git's required force flag for clean initialized submodules; do not bypass its checks with a manual force-remove. The parent branch is retained. APFS releases unreferenced blocks itself; pane expiry and `git worktree prune` do not remove a live directory. A thread remains tied to its original `CWD`, so retain that worktree while further `continue` rounds are needed.

## Brief template

The brief is for Codex, which has none of your conversation context. Write it completely and concretely.

**Write every brief in Chinese**, headings included: task briefs, `continue` rounds, review focus text, live `message` corrections and answers to questions. Header lines (`MODE:`, `NAME:`, `CWD:` …), code identifiers, commands, paths and quoted log lines stay as they are.

```
## 目标
一句话说明完成后的状态。

## 背景
用户原话里的关键事实；已知的入口文件和相关模块；之前试过什么、为什么没成。

## 约束
- 不能动的东西（配置、公共接口、无关文件）
- 风格：贴合周边代码，最小改动，不顺手重构
- 外部系统：写明「只读，不调用」或「允许调用」

## 验收
- 怎样算完成：哪些测试要通过、哪条命令要跑、哪些问题要回答
- 输出要求：结论 + 证据（file:line）+ 不确定的地方单独列出

## 已知文件（可选）
path/to/a.py  -- 入口
path/to/b.py  -- 可疑
```

## Standard pipeline (code changes)

1. Run `context.sh find`, then write the brief with relevant entry IDs. Continue a source thread from the current checkout when the work belongs to it. If the requirement is ambiguous, ask the user first; do not let Codex guess.
2. Dispatch `implement`, with the acceptance tests or commands in the brief. When the affected area is unclear, the same task finds it first; a separate `investigate` is for when you need its answer before you can decide what to build, and the implementation then follows as `continue` in that thread.
3. When the implementation returns, **decide whether a review is worth it**. Review is not a fixed step; it is your call, made on the returned result. Weigh how much could go wrong if the change is subtly wrong against what a review costs (a brief, a wait, and one more round of context), and dispatch `adversarial-review` only when the risk justifies it (intent of the change and your main concerns as the body; prefer `BASE:`, since a fallback review is task-class and would become the most recent thread). When you skip it, go straight to wrap-up and tell the user in one line that you skipped the review and why.
4. If you reviewed: judge every finding against the source (see "Judging review findings"), then dispatch the ones you accepted as `continue` with `THREAD:` and `WRITE: yes` so Codex fixes them in the same thread. **A problem gets at most one review round**: once the fixes are in, go to wrap-up and verify them with tests; never dispatch a second review of the fixes. Codex reviewers keep finding ever rarer defensive cases, so further rounds do not converge. If verification shows a fix is still wrong, send it back as another `continue` and judge the result yourself.
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

You read Codex's text with the companion's `result <job-id>`; it comes back unchanged. For a review, read the report file named by `report=` on its `DONE` line.

- Spot-check one or two `file:line` references before trusting them; Codex is also wrong sometimes.
- Before acting on a conclusion that decides what happens next (a root cause, "this message was lost", "that turn is running"), check the raw data it rests on yourself: the file, the job state, the command output. Do not act on a report's reading of intermediate state.
- A conclusion with no evidence attached goes back as a `continue` asking for the evidence; do not build on it.
- On `STATUS: failed` or `CODEX_FAILED`: report the most useful log lines to the user. Do not take over and redo the whole task yourself.
- Do not auto-apply every review finding, and do not dismiss one without looking; judge each as below.

### Judging review findings

A review report is a set of claims to check, not a verdict to pass along. Forwarding the findings, or dismissing them against a rule you already hold ("out of scope", "pre-existing", "only style") without opening the code, is relaying, not directing. For every finding, before deciding anything, go back to the source:

1. **Location**: open the cited `file:line` (Read with offset/limit, or a grep) on the reviewed revision and confirm the code the finding describes is actually there.
2. **Trigger**: name the concrete input, call path or state that reaches it, traced from a real caller. If you cannot find one, say so.
3. **Impact**: what goes wrong when it triggers (wrong result, lost or duplicated data, crash, a cosmetic difference), how likely it is, and who notices.

Then give the finding one verdict, with the evidence from those three checks:

- **Accept**: the location is real, the trigger is reachable, and the impact is worth the fix. It goes to the implementation thread as `continue` with `WRITE: yes`.
- **Reject**: cite what disproves it: the line does not do what the finding says, the path is unreachable (name the guard at its `file:line`), or the impact is nil. A rule on its own ("out of scope", "pre-existing") is not a reason; a real defect outside this change's scope is reported to the user as such, not dropped.
- **Unresolved**: when a few reads cannot settle it, dispatch `continue` with `THREAD: <review thread>` asking the reviewer for exactly the missing piece (the call path, a reproduction, a failing test), written to a file. Do not guess either way.

The reviewer's severity is an input, not the decision: a "high" with no reachable trigger is rejected, and a "low" that corrupts data is accepted. Keep these reads to the cited lines and their direct callers; if confirming a finding means understanding a whole subsystem, it is unresolved and goes back to the reviewer. Report to the user one line per finding: the verdict and the evidence behind it (`file:line`, command output).
