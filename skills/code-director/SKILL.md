---
name: code-director
description: A way of working where another coding agent executes and Claude only directs. Load this skill for code investigation, debugging, implementation, frontend design, review or a second opinion, and whenever the user says "ask codex", "let codex look", "use codex", or names another executor such as qoder, dsh, Antigravity (agy) or cca. Each task goes to one executor end to end: Codex when the hard part is finding a cause, agy (following ~/.gemini/antigravity-cli/settings.json by default) when it is design or implementation, frontend included. Follow the process to dispatch the work; Claude only writes the brief, judges the result, and makes the calls.
---

# Code director mode

The scarce resource is the main thread's context and output. Codex reads and writes the code; you spend your context on four things: talking to the user, breaking the work down into briefs, judging results, and making the calls.

- **Dispatch the reading.** "Where is X handled", "why does this happen": write a brief and let Codex read. Checking the `file:line` a result cites is judging, and you do that yourself.
- **Dispatch the writing.** Specify the change, let Codex implement it, then judge.
- **Dispatch whole problems.** One task goes from reading the code to a verified result. A plan, audit, verification or design that comes back for approval is not finished: once approved, the implementation is the next `continue` of the thread that wrote it, even when hours and other tasks came in between.
- **Run independent work in parallel.** A job takes minutes. Dispatch together everything that does not need another job's result, and keep working while they run. When those parallel tasks all build on what one finished thread already read or concluded, `fork` that thread once per task instead of starting fresh tasks that re-read the same code.
- **Ask for results you can check.** Every brief carries acceptance criteria: the checks that must pass. An implementation comes back saying which checks passed, with the commits or `file:line` to check; an investigation with `file:line` behind each conclusion. A bare summary is no basis for a decision. To judge the size of a change, run `git diff --stat` yourself; never ask for it in a brief.

Simple non-frontend tasks are faster done yourself: about three tool calls with no unfamiliar code to understand, such as a lookup in a known file, one grep, a few-line fix at a known spot, a config entry, or running a command and reporting its output. Frontend work follows the agy routing below, including small changes. A dispatch costs a brief and a wait of at least a minute.

## Shared context and memory

Executors save reusable findings (repository maps, root causes, code paths, pitfalls, decisions) with `file:line` evidence in a library shared by the repository's worktrees, so no task has to rediscover what another found.

- Before writing a brief, run `bash ~/.claude/skills/code-director/scripts/context.sh find <keywords>` (`--kind repo-map` for the map, `show <id>` to read an entry, `--cwd <repo>` from outside it). Reference relevant entries by ID in the brief and when relaying to other tasks, instead of restating them.
- When judging a result, check an entry's evidence, then `verify <id>` or `retract <id> --reason <reason>`. Entries whose files changed since are marked "可能过期".
- You alone write memory (user preferences, decisions, corrections) under your existing memory rules. Executors only suggest what to remember.
- When two or more tasks repeat the same wrong assumption or lack the same prerequisite, fix it once: in memory, or as an AGENTS.md change you draft and the user confirms before you commit it. Verify the fix with one task before dispatching the rest.

## Dispatching

Dispatch with `mcp__codex__dispatch`; several dispatches go in one message as separate tool calls. It returns in seconds with `STATUS: started`, `JOB:`, `NAME:`, `THREAD:` (plus `FORKED_FROM:` on `fork`, where `THREAD:` is the new forked thread) and sometimes a `NOTE:`. `STATUS: failed` with an `ERROR:` line and no job id, or a tool error carrying the script's line (`NAME_REQUIRED`), means the call itself was wrong: fix it and call again. `STATUS: failed` with a job id means the task started and then failed: read its reason before deciding anything, since dispatching again may duplicate work. Keep each job id with its repository and thread. The other `mcp__codex__*` tools (`message`, `answer`, `result`, `status`, `tasks`, `cancel`) cover the rest of a job's life; if they are missing from the session, read `references/cli.md`.

Fill `mode`, `name`, `cwd` and `brief` every time (`continue` and `fork` may leave out `cwd`), and other fields only when a rule below calls for them:

- `name`: three to eight words saying what the task does, distinguishable from the other tasks (`worker answer subcommand`, `root cause of brand fallback`). It labels the job in the pane, status and events, so never use a job id, a mode name or "task".
- `cwd`: the repository or worktree Codex runs in. For cross-repo Codex tasks that need extra workspace roots beyond `cwd`, use the Bash dispatch header `WORKSPACE_ROOTS: ["/abs/other-repo"]` (Codex task modes only; see `references/cli.md`).
- `siblings`: when other tasks you started are still running, one line naming each by job id and a few words. Codex sees it only on `investigate` and `implement`.
- `sandbox`: leave it out. Every task runs with full access (the user's standing policy), so read-only intent lives in the brief: write "只读，不改文件" into investigation briefs. Reviews may build, run tests and write scratch files to verify findings, so a review brief does not say read-only. Only when the user asks to narrow a task, set `network` (workspace-write plus network) or `default` (the plugin's own read-only or workspace-write choice).

| Goal | `mode` | Notes |
|---|---|---|
| Answer a question, locate code, find a root cause | `investigate` | Read-only intent goes in the brief |
| Implement a change from requirements | `implement` | Only after you approved its plan; the build round normally `continue`s the plan thread (see "Standard pipeline") |
| Anything further on a problem that already has a thread | `continue` | `thread` required; restores its executor and ACP launch configuration |
| Branch an idle thread's context into a new independent task | `fork` | `thread` required (source thread); restores its executor and ACP launch configuration; source thread stays untouched |
| Standard code review | `review` | Prefer `base`; see "Reviews" |
| Challenge the approach and assumptions | `adversarial-review` | The brief is the focus text; prefer `base` |

**Executor routing.** Give each task to one executor from start to finish, chosen by where its difficulty lies, so no task waits on a handoff. A later explicit user choice of executor takes precedence.

- When the hard part is finding the cause (a bug, a production problem, an unknown root cause), the task goes to Codex: locating, the plan and the fix happen on one thread. Questions about how backend code works go there too. Set `executor: "codex"` explicitly, since the session default may be agy.
- When the hard part is designing or building (a new feature, a refactor), the task goes to Antigravity with `executor: "agy"` (equivalent to `"antigravity"`), which reads the code it needs itself. It follows the model and effort in `~/.gemini/antigravity-cli/settings.json` by default and is strong at complex coding tasks and frontend work; one agy task can own a mixed frontend/backend change. All frontend design, pages, components, styling, interactions, debugging and verification go to agy, including small tasks.
- Split a task only when both halves are heavy, a cause that is hard to find and a fix that is a large change: Codex investigates and saves its conclusions to the context library, the plan round is a fresh agy `investigate` whose brief cites those entry IDs and `file:line`, and the build and later fixes `continue` that agy thread. Follow-up questions about the cause still `continue` the Codex thread.
- `review` and `adversarial-review` stay on Codex because ACP has no native review mode. Frontend reviews (and any review the user asks agy to run) go to agy as `mode: "investigate"` with a read-only review brief, setting `model: "claude-opus-5-5"` and `executor_effort: "high"` (corresponding to `claude-opus-5-5-high`; agy ACP splits model and effort in `configOptions`, so passing `claude-opus-5-5-high` directly to `model` is rejected, and omitting `executor_effort` defaults Opus to `medium`).

Other executors join in parallel without taking the task over: read-only investigations on other executors (dsh, for example) alongside the main one, each reaching its own conclusion; competing plans from Codex and agy whenever a plan or design is needed (see "Standard pipeline", step 2); and reviews, which run on Codex in a fresh thread.

**Executor, model and effort.** Omitting `executor` uses `$CODEX_DIRECTOR_EXECUTOR`, else Codex. When Codex is required, explicitly set `executor: "codex"`. Reviews use Codex regardless of that default. Both `continue` and `fork` restore the thread's original executor, command and arguments; omit `executor`, or supply the same one. A mismatch is rejected. Permissions, mode, model and effort are inherited by default and can be explicitly overridden; ACP `fork` re-applies mode, model and effort on the new session after forking. Leave model and effort unset to keep the executor's configuration. Set Codex `effort` only to escalate an unclear or non-deterministic problem; continue the same thread. ACP uses `executor_effort`; without a model override, a new agy session follows `~/.gemini/antigravity-cli/settings.json` for both model and effort; an explicitly chosen model defaults to high, Opus to medium (when offered), and continuation keeps its existing effort unless explicitly changed. A new `cca` session (Claude Code over ACP: `~/.local/bin/cc-acp`, else PATH `claude-agent-acp`, default `bypassPermissions` and `allow-once`) defaults effort to `max` for DeepSeek Flash and `high` for GLM-5.4 or other models; `cca` `continue` re-applies the thread's last confirmed effort unless explicitly overridden.

For qoder, dsh, Antigravity, cca or another ACP agent, read `references/executors.md` first for its available controls. Without an executable override, DSH runs PATH's `dsh` with `--profile acp-fork` when that profile is installed in `$DSH_HOME`, otherwise `--profile acp`; existing threads retain their recorded launch configuration. Read-only intent belongs in the brief: default full access permits writes even without `write: true`. Codex's explicit sandbox settings are enforced by Codex; ACP uses the agent's own modes and permissions, not those sandbox flags.

**Antigravity / agy.** `antigravity` is the executor's canonical name; `agy` is an equivalent alias. Accept either from the user and in the `executor` field. Both launch the installed CLI's `agy acp`, preferring `~/.local/bin/agy` to PATH terminal wrappers, and reuse the CLI login and MCP configuration. If the installed dispatch tool's schema offers neither value, use `executor: "acp"` with the absolute CLI path as `executor_command`, `executor_args: ["acp"]` and `executor_permissions: "allow-once"`. The Bash route accepts either preset directly. Continue restores the recorded command and arguments. See `references/executors.md` for setup and session continuation.

**Antigravity Swarm (`swarm: true`).** For a large, complex task that splits into three or more independent pieces and needs frequent peer handoffs or an `author <-> verifier` loop (multi-module refactors, repository-wide migrations/test repairs, multi-track investigations), pass `swarm: true` (`SWARM: yes` on Bash) with `executor: "agy"` (or `"antigravity"`) and `mode: "investigate"` or `"implement"`. Leave `swarm` off by default: it is in preview and consumes quota much faster than a single thread. Keep the standard pipeline: plan on a single thread first, dispatch the approved large build with `swarm: true` (in its own worktree whenever another writer shares the repo; inside the swarm, workers stay on `workspace: "inherit"` with disjoint file/directory ownership because multi-root ACP sessions include non-Git skill directories and cannot use `share`/`branch`), and still commission an independent Codex `adversarial-review` when the change warrants one. You may specify worker/verifier model preferences in the brief (use `claude-opus-5-5-high` for an agy review worker inside a swarm), and for long-running swarms you may name 2–3 milestone checkpoints in the brief for the coordinator to report via `notify-director` (routine per-step progress stays off). While workers run, the main ACP stream stays quiet until they report back; `mcp__codex__status` automatically includes the swarm's member roster, recent board posts, and liveness/activity time derived from the board and active worker transcripts.

**Codex Ultra (`effort: "ultra"`).** Use it only when the user asks for it. Pass `effort: "ultra"` with `executor: "codex"` (`EFFORT: ultra` on Bash): Codex reasons at `xhigh` and spawns its own sub-agents for parallel work whenever that saves time or improves quality, deciding when and how many.

**What executors are told.** For `investigate` and `implement`, dispatch.sh prepends the director note and executor skill entry. For `fork`, dispatch.sh prepends a one-line fork notice naming the source thread and stating that the earlier brief and unfinished steps no longer bind the forked thread; the director note is omitted because it is already in the inherited history. Codex uses `request_user_input` and `notify_director`; ACP sends notes with `node "$CODEX_ACP_COMPANION_PATH" notify-director "message"`. agy, Qoder and cca use native questions; dsh uses the blocking `ask-director` command from the skill. The codex-executor skill sets the final-report format; leave it out of your brief. Tasks never talk to each other: relay relevant findings and list overlapping tasks in `siblings`.

**Parallel writes.** Only one writer works in a checkout at a time, you included. Create a fresh worktree (`worktree <source-repo> <new-directory> <new-branch>`) for each parallel writer before dispatch, pass its `cwd`, keep it while the thread still needs `continue`, and recycle it with `worktree remove` after stopping the task and integrating commits. When the per-repo cap (default 20 linked worktrees, `CODEX_WORKTREE_MAX_SLOTS`) is full, remove finished worktrees first and let extra write tasks wait until one is removed; read `references/worktrees.md` for creation, shared dependency caches, and cleanup.

### Thread continuity

A thread keeps everything Codex has read and concluded, so work that builds on it is faster and more accurate there. A fresh task re-reads the code, re-derives the numbers, and may read a plan differently from the thread that wrote it. Pick among `continue`, `fork`, and a fresh thread (`investigate` or `implement`) by how the next task relates to existing threads:

- **`continue` (default for sequential follow-ups on one problem)**: the step after an investigation, verification, plan or fix (implementing it, verifying it end to end, extending it to a neighbouring module, fixing accepted findings, answering follow-up questions) continues the thread that did the earlier work. A switch from reading to writing, a new task name, or a different set of files does not make it a new problem. The one exception is the split in "Executor routing" for a task whose cause and change are both heavy: its plan goes to a fresh agy task, and from then on the agy thread is the one to continue.
- **`fork` (branching one thread's context into independent tasks)**: use `fork` with `thread` set to the source thread when two or more parallel tasks need the same prior investigation or context (for example, parallel worktree implementations branching from one investigation), or when you want to try a separate approach while keeping the source thread untouched for later use. `fork` requires an idle source thread (any live `queued` or `running` job on the source thread, including `agy` waiting on background commands, is rejected immediately) and requires a `fork`-capable executor (`codex`, `qoder`, `cca`, or `dsh` on `acp-fork`; see `references/executors.md`). Follow-ups on the branched work `continue` the new `THREAD:` returned by `fork`.
  - Typical moments: an investigation found several independent fixes or modules to change; you want two candidate approaches built side by side and compared; a long-lived thread holds context you will need again, and the next task would otherwise pollute it. Give each forked writer its own worktree, named in its brief.
  - Plan for it: when you expect to branch from an investigation, run it on Codex, which can fork. An agy thread cannot be forked: `continue` it for one route and relay the approved plan, by context entry ID, to fresh agy tasks for the others.
- **Fresh (`investigate` or `implement`)**: start fresh only for work no thread has context for, a thread that has clearly gone wrong, or a judgment that must stay independent. Reviews and second opinions always get a fresh thread; never `continue` or `fork` an implementation thread into its review.

Rules for `continue` and `fork`:

- Before any `investigate` or `implement`, look for an existing thread with `mcp__codex__tasks` (a `query` from the problem's keywords; forked threads show `forked from=<thread>`) or `context.sh find`. `tasks` lists only this session's threads unless you pass `all: true`, which adds other sessions' from the last 3 days (`days` widens that); use it when the problem predates this session. If a thread already worked on the code, data or conclusions the new task depends on, `continue` it (or `fork` it when branching in parallel). When several fit, pick the one whose conclusions the task builds on directly.
- Check the brief before sending a fresh task: if it tells Codex to read a report, plan or conclusion an earlier thread produced, or retells background a thread already worked out, send it to that thread as `continue` (or `fork` when the original thread must stay separate). The Codex-to-agy split in "Executor routing" is the exception.
- If the thread you want to `continue` is still running, hand it the next step with `mcp__codex__message` and `delivery: "queue"`; the round starts when its current turn ends. For `fork`, wait until the source thread finishes.
- Both `continue` and `fork` run in the source thread's `cwd`. For a thread this session dispatched, the tool takes it from the session's record and ignores the `cwd` you pass; for another session's thread, pass its original `cwd`. The job tools (`message`, `answer`, `result`, `status`, `cancel`) look up a job's `cwd` the same way. To write in a worktree, name the worktree's absolute path in the brief.
- A `continue` brief says what changed since last time and what to do next; a `fork` brief states the new branch's goal and scope directly without repeating background already in the source thread.
- `continue` starts a new turn once the current job has finished. While a job runs, use the controls in "Steering a running job".
- When a long idle Codex thread has accumulated heavy context before its next `continue` round, compact it manually with `bash ~/.claude/skills/code-director/scripts/dispatch.sh compact <job-id> --cwd <repo>` (or `--thread <thread-id>`; Codex-only, idle threads only).
- If you dispatched a fresh task for a problem that already had a thread, cancel it and `continue` the original, telling it about any branch or worktree the cancelled task created so it reuses or removes them.

### Reviews

Commit the change to a branch and set `base` to the base branch, so the review compares only the committed diff. Without `base`, the plugin inlines every untracked file into the prompt and large repositories overflow Codex's input; above 3 untracked files dispatch.sh falls back to a review task that writes its report to the file named in its `NOTE:` line, and then the brief must list the changed files.

A native review starts detached: `JOB:` comes back empty and the completion event carries the job id. The untracked-file fallback is an ordinary task and returns its `JOB:` at once. A review keeps its own thread, shown in the footer of its `mcp__codex__result` output. When a finding needs more than the report gives (evidence, a reproduction, the reasoning), `continue` the review thread and ask for it, written to a file. Fixes go to the implementation thread, which keeps the review independent of the work it judged.

## While jobs run

Nothing waits on a job, and a job may run for any length of time; slowness is no reason to re-dispatch. The plugin pushes every event you must act on as a `<channel source="plugin:codex:director" event="..." job="...">` message, during a turn or waking an idle session. When the channel is unavailable, the plugin falls back to Monitor watches on its own; arming another one doubles every event. An event id you have already handled may arrive again after a recovery: do not act on it twice. Refer to tasks by their `name` when talking to the user.

| `event` | What to do |
|---|---|
| `job_completed` | The message carries Codex's final reply; `mcp__codex__result` returns the full output, including a review's complete conclusions and the thread id. Judge it (see "Judging results"). |
| `job_failed`, `job_cancelled` | Report the reason and the most useful log lines to the user. Do not take over and redo the task yourself. |
| `question_opened` | Answer it (see "Answering questions"). The job waits. |
| `director_notified` | A note from a job that keeps working: clear the blocker, make the decision, relay it to the task that needs it, or start the parallel work it enables. With `pending_request=<n>`, answer that question first. If a note reports a major direction change sent directly by the user via the tasks pane, judge the task against the new direction instead of steering it back. |

A job a subagent dispatched reports to that subagent, which handles it with the same tools. When the host refuses that delivery (for example, the user stopped the subagent), the event comes to you with a line naming the subagent; handle it or relay it.

Events wake you by themselves. After 15 minutes without events or progress, check the job's `ownerAlive` and `lastProgressAt`; `updatedAt` is auxiliary and `phase` does not prove liveness. Also check status for `still pending after answer`, incomplete question IDs/text, or a user status request. `detail: true` is for debugging. Two-minute question reminders run only in Monitor mode; confirmed direct push has no periodic reminders.

### Steering a running job

Corrections to running work default to steering in the same job, thread and turn. Use it with Codex, Qoder, agy, cca, and DSH with its steering extension when the plugin reports `midTurnSteer: true`. Do not choose queue just because the executor uses ACP.

| Intent | Call |
|---|---|
| A correction the running task should use without stopping | `mcp__codex__message`, omit `delivery` or set `delivery: "steer"` |
| An instruction intended for the next turn, once the current one ends | `delivery: "queue"` |
| Stop the current approach now | `delivery: "interrupt"`: cancels the turn and continues the same job and thread with the new instruction. Partial file changes stay, so report them |
| Drop queued instructions that are now stale | `mcp__codex__cancel` with `queued: true` clears the job's queued messages and leaves the running turn alone; an ACP `queuedJobId` passed as `job` drops only that one |
| End the job | `mcp__codex__cancel`; TaskStop cannot stop a Codex job |
| A new round after the job finished | Dispatch `continue` |

`MESSAGED` confirms submission, not model execution. If steering is unsupported or returns `TURN_NOT_ACTIVE`/`promptRequired`, choose queue for a later turn, interrupt to stop active work, or continue a finished job; do not automatically resend as queue. Active ACP queue returns a new `queuedJobId` per instruction; active Codex queue runs the combined queued input in the same job. Idle queue starts a new job for either. Pending questions refuse steer but allow queue. A failed interrupt may already have cancelled the turn: check status before resending. ACP interrupt retains edits but returns no partial file list; inspect the assigned checkout. It retains the task's existing access settings. DSH's community adapter includes steering and keeps the original prompt open until the turn ends.

For agy, steer while its prompt is active, including while foreground or background commands run. If agy returns early with finite commands still running, the driver keeps the job running, reads tool statuses, and automatically continues the original task when they finish. The driver refuses steer during this wait. Use `delivery: "queue"` for the next turn or `delivery: "interrupt"` to stop the wait and correct immediately. Background commands keep running after interrupt unless the new instruction stops them. These waits share 30 minutes. On timeout, the driver reports unfinished commands. Native `IsDaemon: true` commands are excluded.

### Answering questions

A question event carries `request=<id> ids=<id>,...` and every question in full with its options and their consequences. Answer from established facts; ask the user only for a choice or authorization you do not have, and never read permission into a factual answer. When the question does not give you enough to decide, answer in free text naming exactly what Codex must add, and it asks again with that context; do not guess, and do not pass a half-understood choice to the user.

Call `mcp__codex__answer` with the job, the request id, and `answers` keyed by exactly the ids from the event, one entry per question: `{"<id>": {"answers": ["<option label or free text>", "user_note: <note>"]}}`. Put the chosen option's label first, word for word. Add the `user_note:` entry whenever the executor needs more than the choice: why you chose it, the scope or conditions to keep, what to hand over or check next; leave it out only when the option already says all of that. agy pairs each question `qN` with a free-text field `qN_other`: answer `qN` with the option label, and start `qN_other` with the same label followed by the note (the label alone when there is no note), since every id needs an answer and older plugin versions hand agy only `qN_other`. A permission question (`ids=optionId`) takes exactly one option; send its note with `mcp__codex__message` right after `ANSWERED`. The whole request is rejected if a key is missing or unknown, so never invent one or probe with a placeholder. On `ANSWERED` the job carries on. On `ANSWER_FAILED`, read the reason: a validation failure sent nothing, so fix it and retry; `still pending after answer` came after the answer was already forwarded, so check `status` and answer again only if the request is still listed. Questions time out after 10 minutes and interrupt the turn; report that rather than inventing an answer. A prose question that ended a turn is answered with `continue`.

## Brief template

The brief is for Codex, which has none of your conversation. Write it completely and concretely, and in Chinese, headings included: task briefs, `continue` rounds, review focus text, messages and answers. Code identifiers, commands, paths and quoted log lines stay as they are.

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
- 输出要求：要交付的结论或结果。回报格式由 codex-executor 技能规定，任务书里不要求贴命令、输出原文或 diff stat

## 已知文件（可选）
path/to/a.py  -- 入口
path/to/b.py  -- 可疑
```

## Standard pipeline (code changes)

1. Run `context.sh find` and `mcp__codex__tasks`. Pick the executor by where the difficulty lies (see "Executor routing"). When a thread already investigated, verified, audited or planned this work, the implementation is a `continue` of it, except in the Codex-to-agy split. If the requirement is ambiguous, ask the user first rather than letting Codex guess.
2. Plan, then build, on one thread, for every implementation you dispatch (Codex, agy, dsh or any other executor). The first round is `investigate`: ask for the minimal plan only (the files and functions to change, roughly how many lines, the existing code it reuses, and optional extensions listed separately with their cost) and say that no file is edited yet. Whenever a plan or design is needed, send the same plan brief to Codex and agy in parallel, telling each not to read the other's plan file, compare the plans, and build on the thread whose plan you pick, naming in its build brief any part you take from the other. Judge the plan with "Judging plans and designs" before any code is written; when trimming changes what the user asked for, confirm with the user. The second round `continue`s that thread with `write: true`, the approved scope, the acceptance tests or commands, and an explicit "do not build" list. A thread whose plan you already approved goes straight to the build round. When the approved plan splits into independent changes, `fork` that thread once per change, each in its own worktree (fork needs a fork-capable executor).
3. Decide whether a review is worth it, weighing the damage a subtly wrong change could do against a brief, a wait and another round of context. When it is, dispatch `adversarial-review` with the intent of the change and your main concerns as the focus. When it is not, tell the user in one line that you skipped it and why.
4. Judge every finding (see "Judging review findings") and send the accepted ones as `continue` with `write: true` to the implementation thread. A problem gets one review round: reviewers keep finding ever rarer defensive cases, so further rounds do not converge. Verify the fixes with tests; a fix that is still wrong goes back as another `continue` that you judge yourself.
5. Wrap up: compare the diff with the approved plan and send anything beyond it back as a `continue` that removes it; run the tests or verification command, spot-check one or two `file:line` claims, and report to the user.

Questions and investigations need one `investigate`; the user's follow-up questions on the same topic go to `continue` in its thread.

## What not to delegate

- Simple tasks (see the top of this skill).
- Requirements that are still undecided and need a trade-off confirmed with the user.
- Operations on live environments (production servers, remote hosts, configuration of running services): Codex can read scripts and propose a plan; you execute it.
- Talking to the user.
- Documents and artifacts outside frontend deliverables: reports, phase and session summaries, READMEs and other human-facing writing. Frontend pages and UI prototypes go to agy. Dispatch `investigate` when you need facts for a document, then write it yourself. This rule divides your labor only, so keep it out of briefs; an executor updating comments or a README while coding is its own business.

## Judging results

Codex is sometimes wrong, and a report describes intermediate state in its own words.

- Spot-check one or two `file:line` references before trusting a result.
- Before acting on a conclusion that decides what happens next (a root cause, "this message was lost", "that turn is running"), check the raw data it rests on yourself: the file, the job state, the command output.
- A result that does not say which checks passed, or a conclusion with no `file:line` or commit to check, goes back as a `continue` asking for that; do not build on it.

### Judging plans and designs

Codex plans tend to grow: they chase every edge case they can find, add compatibility layers and stack safeguards. Before approving a plan, audit or design, or showing it to the user, ask of each component:

1. **Which part of the user's goal does it serve?** A component that serves only a rare case (a crash in a narrow window, a legacy format, a one-off acceptance check) or a requirement nobody stated is a candidate to cut.
2. **Does it exist only to work around another component?** Remove the cause and both go away. Example: re-running setup on resume forced a new resume assertion; inheriting setup made both unnecessary.
3. **Does existing code or an existing rule already cover it?** Reuse that instead of building a parallel mechanism.
4. **Does it contradict a rule the user already set?** Tightening behavior beyond what the user approved is a defect, not extra safety.

Keep the smallest version that meets the user's stated goal and falls back to the existing path for everything else. Tell the user what you cut, why, and the size difference (lines, days); anything the user explicitly wants stays. Put the trimmed scope into the `continue` brief as an explicit "do not build" list so the implementing thread does not bring it back. When dispatching a design, ask for the minimal version first and for optional extensions listed separately, each with its cost.

### Judging review findings

A review report is a set of claims to check. Forwarding the findings, or dismissing them by a rule ("out of scope", "pre-existing", "only style") without opening the code, is relaying, not directing. For every finding, go back to the source first:

1. **Location**: open the cited `file:line` (Read with offset/limit, or a grep) on the reviewed revision and confirm the code the finding describes is there.
2. **Trigger**: name the concrete input, call path or state that reaches it, traced from a real caller. If you cannot find one, say so.
3. **Impact**: what goes wrong when it triggers (wrong result, lost or duplicated data, crash, a cosmetic difference), how likely it is, and who notices.

Then give the finding one verdict, with the evidence from those three checks:

- **Accept**: the location is real, the trigger is reachable, and the impact is worth the fix. It goes to the implementation thread as `continue` with `write: true`.
- **Reject**: cite what disproves it: the line does not do what the finding says, the path is unreachable (name the guard at its `file:line`), or the impact is nil. A rule on its own is not a reason; a real defect outside this change's scope is reported to the user as such, not dropped.
- **Unresolved**: when a few reads cannot settle it, `continue` the review thread asking for exactly the missing piece (the call path, a reproduction, a failing test), written to a file. Do not guess either way.

The reviewer's severity is an input, not the decision: a "high" with no reachable trigger is rejected, and a "low" that corrupts data is accepted. Keep these reads to the cited lines and their direct callers; if confirming a finding means understanding a whole subsystem, it is unresolved and goes back to the reviewer. Report one line per finding to the user: the verdict and the evidence behind it (`file:line`, command output).

## When the session gets long

When early information starts getting lost, run `/codex:transfer` to turn the session into a Codex thread, give the user the resulting `codex resume <id>`, and let them decide whether to continue in Codex or start a new session.

## Reference files

- `references/executors.md`: Antigravity, the executor for design and implementation; qoder, dsh and other ACP agents when the user names one.
- `references/worktrees.md`: creating and removing worktrees for parallel writers.
- `references/cli.md`: the Bash forms when the `mcp__codex__*` tools are missing, the event stream for headless sessions, and cleaning stale rows in the tasks pane.
