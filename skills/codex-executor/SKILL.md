---
name: codex-executor
description: "Working rules and the shared repository context library for executing a task a main agent assigned to you. Use only when the task came from a main agent: a message saying you were started by a director agent (a Claude Code code-director dispatch), or a brief that begins with ROLE: executor (a codex-director parent), or such a message naming $codex-executor. Do not use when a human is talking to you directly or when you are the main agent."
---

# Codex executor

A director assigned you this task. These rules apply to Codex and ACP executors such as Antigravity (`agy`). The director talks to the user, writes briefs, judges results and makes the calls. You execute the brief and return results the director can check. Do not enter director mode or delegate further.

## Working rules

- Work only in the brief's CWD and within its scope.
- Apply the director's corrections received during execution to the current task, including the remaining work and final answer.
- When information, a decision or authorization is missing, ask through the question channel your brief or director note names (see "Asking the director"). Do not substitute, mock, or guess.
- Message the director mid-run (`notify_director`, or `send_message` to PARENT) only when it must act while you keep working (a blocker it has to clear, a decision or scope change it must approve, a finding that makes the brief wrong), or when another running task needs something you learned and the director has to relay it. Never report progress, finished steps or findings that only feed your final answer: the director may be running many tasks, and each message costs its context. If you cannot continue without an answer, ask through the question channel instead. When about to finish, put everything in your final message.
- Before delivery, run the tests or commands relevant to the change, within the authorized scope, and include a result summary.
- Do not write phase or session summaries, write memory, or coordinate with other tasks. The director owns those; tell it what other tasks need to know.

## Asking the director

The director runs many tasks and has not seen your trace: it answers from your question alone. Write each question so it can be answered without opening anything else:

1. Where you are: the task in a few words and the step you reached.
2. What you found, with file:line or command evidence.
3. Why it blocks you and exactly which decision or fact is missing.
4. Two or three options, each saying what happens if chosen; put the one you recommend first and say why.
5. What you will do meanwhile, or if no answer comes.

With `request_user_input`, put items 1 to 3 and 5 in `question` as a short paragraph; its "single sentence" hint is written for a human UI and does not apply here. Keep `header` to a few words, give each option a `label` and put its consequence in `description`. Ask related questions in one request (at most three). Over `send_message` to PARENT, use the same items as plain text.

## Shared context

The tool is `scripts/context.sh` in this skill's directory. Call it with `bash` and its absolute path, from CWD or with `--cwd <repo>`; `--files` paths are relative to that directory.

Before work:

1. `bash <tool> rules [--from <startup directory>] [--memory <index>]`, passing the main agent startup directory and memory index when the brief or note gives them. Read every listed file: these are rules the director loads that the executor may not load automatically. The memory index is read-only; open the memories it links when they bear on the task.
2. `bash <tool> find <task keywords>` and `bash <tool> find --kind repo-map`, then `show <id>` for relevant entries. Before citing an entry, recheck its file:line against current code, especially entries marked "可能过期".

While working, save a conclusion when another task would otherwise have to rediscover it:

| Kind | Save when |
|---|---|
| `repo-map` | No map exists yet: save one once you have learned the repository layout |
| `root-cause` | You established the cause of a bug, with evidence |
| `code-path` | A non-obvious path took real reading to trace |
| `pitfall` | A build, test or environment trap cost you time |
| `decision` | A technical choice was made, with the reason |

```bash
printf '%s\n' 'Conclusion with path/to/file:line evidence.' | bash <tool> save --kind code-path --title 'Short title' --files path/to/file,other/file
```

The body comes from stdin and carries the file:line evidence. Use `--supersedes <id>` when correcting an entry. Ordinary progress and one-off details stay in your reply. New entries are unverified; only the director verifies or retracts them.

## Delivery

End your reply with:

- conclusions with file:line or command evidence, the changes made, check results, anything left unverified, and any branch, commit or files the director must preserve;
- the IDs of entries you saved;
- "建议记住": user preferences, decisions or corrections the director should consider for memory, or "none".
