---
name: codex-director
description: Coordinate substantive code investigation, implementation, and review from the Codex main agent using native subagents. Use for coding tasks that benefit from delegation or when the user asks for director mode. Assigned subagents execute their brief and do not enter director mode.
---

# Codex director

The main agent owns the user's request, task briefs, decisions, integration, and final delivery. Delegate substantial code reading and implementation as complete tasks with verifiable results. Handle trivial lookups, small known edits, and human-facing writing directly. Read returned diffs and the code needed to judge them.

Use the native `collaboration` tools exposed in the current session. Call them directly; they are not shell commands or tools inside `functions.exec`. This workflow needs no app-server, companion, plugin task pane, Monitor, or external executor. If native delegation is unavailable, report that limitation and continue the authorized work directly.

## Main agent and executor roles

Apply this workflow only as the main agent. When a parent assigns you a task, execute that brief; do not load director mode or spawn another agent unless the parent explicitly assigns further delegation. Report findings, questions, and completion to the parent through the native mailbox.

Before delegating, read the applicable repository instructions and establish the target repository, revision, permitted writes, required tests, and delivery requirements. Carry the user's existing authorization into each brief; delegation does not authorize additional actions.

## Dispatch

Give one agent a whole problem: investigation through implementation and focused verification when authorized. Continue that problem with the same agent; use a fresh agent for an independent review. Dispatch independent tasks together when useful, within the runtime's concurrency limit, which includes the main agent.

Use `collaboration.spawn_agent` with a short, distinct `task_name`, `fork_turns: "none"`, and a self-contained `message`. Keep the inherited model and reasoning settings unless the user or applicable instructions explicitly select others. Record the returned agent ID and canonical task name with its goal and assigned directory. Native agent IDs replace the old plugin job/thread IDs.

A brief should include:

```text
ROLE: executor. Execute this brief; do not enter director mode or delegate further.
PARENT: <main agent's canonical name>
GOAL: <one complete, checkable outcome>
CWD: <absolute assigned directory; pass it as workdir in shell calls>
REVISION: <branch and fixed SHA or baseline, when relevant>
SCOPE: <read-only or exact permitted files and actions>
CONTEXT: <user requirements, applicable repository instructions, relevant facts>
SIBLINGS: <other active tasks and their owned paths, if any>
ACCEPTANCE: <expected behavior, focused checks, required evidence and delivery>

If information or a decision is missing, send_message to PARENT with the
question and the work you can still do. Never infer new authorization.
Return conclusions with file:line or command evidence, changes, test results,
unverified items, and any branch/commit/files that must be preserved.
```

Use plain-language briefs, not the old `MODE` headers. An investigation is explicitly read-only, including no test runs that write files unless authorized. An implementation names permitted writes and checks. A review names the exact revision/diff and asks for actionable findings with evidence. Challenge assumptions when that is the requested review focus.

## Shared files and parallel work

Native agents share the filesystem. The main agent creates and owns isolated worktrees or checkouts for parallel writers, including itself when it also writes. Use available workspace/Git tools and assign each writer an absolute directory; never use hard links or shared writable build outputs for isolation. Read-only agents may inspect the same fixed revision.

If separate directories are unnecessary, serialize writes in the shared checkout. Include relevant uncommitted changes in the brief and preserve them. Executors work only in their assigned directory and do not create or delete other tasks' worktrees. Commit, push, merge, install, and deploy only within the user's authorized scope. Keep a directory while its task may need follow-up; inspect its remaining files and commits before cleanup.

## Follow progress and steer

| Intent | Native tool | Behavior |
|---|---|---|
| Start a complete task or an independent review | `spawn_agent` | Creates a child agent and starts its turn |
| Add context, relay a decision, or ask a running agent a question | `send_message` | Delivers a mailbox message; does not start an idle agent's turn |
| Continue the same problem, including fixing review findings | `followup_task` | Starts an idle agent's turn; a running agent receives it at a message boundary |
| Stop the active turn before changing direction | `interrupt_agent` | Interrupts the turn; the agent remains available and edits remain on disk |
| Wait while no independent work remains | `wait_agent` | Waits for mailbox activity; the message content arrives separately |
| Inspect live agents, available slots, or an apparent stall | `list_agents` | Returns current status; it does not prove task acceptance |

Use the returned agent ID or canonical task name as `target`. Resume an idle agent with `followup_task`; sending a message alone will not make it work. For a change that must stop current execution, interrupt first, inspect its state and partial changes, then send the replacement task through `followup_task`.

Keep working on independent parts after dispatch. Read incoming questions, progress messages, and final answers; do not repeatedly poll. If waiting, use bounded waits of at most 60 seconds and keep the user informed when progress or the plan changes. A wait timeout is not a failure. After 15 minutes without progress, inspect live status and ask the agent for a concrete progress/blocker report; do not duplicate its task just because it is slow.

Answer questions using the user's existing requirements and authorization. Ask the user only when a material decision or permission is genuinely missing, while continuing independent work. Forward cross-task facts through the parent so every agent has a consistent scope.

## Verify and deliver

An agent's final answer is evidence to review, not automatic acceptance. Inspect the relevant diff or source claims and the actual focused test output. Distinguish code inspection, local/mock checks, and live-system evidence; mark missing proof as unverified. Run only required checks related to the change, and do not repeat passing tests without a new reason.

For a defect or a material implementation, commission an independent review when it adds useful confidence. Give the reviewer the requirements and exact candidate revision/diff without telling it the expected verdict. Send actionable findings to the original executor with `followup_task`, then verify the resulting change. Avoid a review cycle for trivial edits or treating a review summary as proof that tests passed.

Stay responsible until the complete user request, integration, authorized delivery actions, and required checks are finished. Report what changed, why, verification, and remaining limitations. A child agent completing does not finish the main task. Report incomplete work honestly if an external blocker prevents completion.
