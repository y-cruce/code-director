# Command-line forms

Read this when the `mcp__codex__*` tools are missing from the session, in an SDK or headless session without plugin hooks, or to clean the tasks pane. Each call below is one foreground Bash call. `$D` stands for `~/.claude/skills/code-director/scripts/dispatch.sh`, and `$CC` for the companion it selects, `"$(bash ~/.claude/skills/code-director/scripts/dispatch.sh companion)"`.

## Without the MCP tools

| Tool | Bash form |
|---|---|
| `dispatch` | Write the dispatch text to a file in your scratchpad (one file per task), then `bash $D dispatch < <file>` |
| `message` | Write the text to a file, then `bash $D message <job-id> <file> --cwd <repo> [--queue\|--interrupt]` |
| `answer` | Write the answers map to a file, then `bash $D answer <job-id> <request-id> <file> --cwd <repo>` |
| `result` | `node "$CC" result <job-id> --cwd <repo>` |
| `status` | `node "$CC" status <job-id> --cwd <repo> --brief` |
| `cancel` | `node "$CC" cancel <job-id> --cwd <repo>` |

The dispatch file has header lines, a blank line, then the brief. Each tool field is a header in upper case: `MODE`, `NAME`, `CWD` (defaults to your working directory), `THREAD`, `BASE`, `WRITE: yes`, `EFFORT`, `MODEL`, `SIBLINGS`, `SANDBOX`, `EXECUTOR`, `EXECUTOR_MODE`, `EXECUTOR_EFFORT`, `EXECUTOR_COMMAND`, `EXECUTOR_ARGS` (a JSON array), `EXECUTOR_PERMISSIONS`.

```
MODE: investigate
NAME: locate answer validation path
CWD: /abs/path/to/repo

<brief>
```

The brief goes through a file so it never passes through a shell command line. Run `answer` alone, never through a pipe or `grep`: a pipe hides the `ANSWER_FAILED` line and replaces the exit code. `message` prints `MESSAGED job=<id>` (plus `queued=<id>` with `--queue`, naming the job the queued turn runs as) or `MESSAGE_FAILED job=<id> <reason>`.

`message` with no flag steers the running turn for Codex, Qoder, and DSH/agy with the steering extensions when `midTurnSteer: true`. Do not add `--queue` merely because an executor uses ACP. Add `--queue` when the instruction is meant for the next turn, or `--interrupt` when the current turn must stop now. If steering is unsupported or the turn ended, check status before choosing the next action; a finished job needs `continue`.

## Event stream without plugin hooks

With hooks loaded, the plugin delivers events itself through its channel, or falls back to Monitor watches it manages; do not arm a Monitor yourself. Only in an SDK or headless session without hooks, consume `bash $D events --cwd <repo>` (one line per event), or block on a single job with `bash $D follow <job-id> --cwd <repo> [--after <cursor>]`, which returns on the first event that needs you. The lines are `DONE` (completed, with `thread=` and, for a review, `report=`), `FAILED`, `QUESTION`, `NOTIFIED`, and `QUESTION_PENDING` (a question still open: check `status` before answering). `IDLE_EXIT` ends the stream after an idle hour; start a new one before the next dispatch.

## Tasks pane

The pane draws each job's live trace; `/codex:tasks` opens it for the user, and `/codex:tasks <n | part of a name>` switches tasks. When it shows a row as running that should be over, or a row you no longer need, use `bash $D pane`: `list` prints each row with the pane's status next to the job file's status and marks disagreements `STALE`; `refresh` rebuilds the rows from disk; `forget <n | part of a name | task id>` hides one row. None of them touch job files. `did not answer` means the pane is not running in this session: tell the user rather than retrying.
