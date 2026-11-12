Append the block below to `~/.claude/CLAUDE.md` (applies to all projects) or to a project's `CLAUDE.md`. Skills load only when triggered, so the routing rule must live in `CLAUDE.md` to guarantee every matching task takes this path.

```markdown
## An agent is the executor

For any task that reads code to understand it, debugs, implements a change, or reviews a diff, load the `code-director` skill and dispatch the work. Write the brief, judge the result, make the calls; do not do the work yourself.

Antigravity (`agy`, alias of `antigravity`) is the first-choice executor. Its default model, gemini-4-carbon, is strong at complex coding tasks and frontend work. Send investigations, debugging and implementation to it, backend and frontend alike, and all frontend design, verification and reviews, including small changes. For frontend reviews use `MODE: investigate` with a read-only review brief. Follow the `code-director` skill's ACP fallback when the installed tool schema lacks the agy names.

Send corrections to a running task with `mcp__codex__message`, omitting `delivery` or setting `delivery: "steer"`. Codex, Qoder, and DSH/agy with their steering extensions support input in the same job/thread/turn when the plugin reports `midTurnSteer: true`; ACP alone is no reason to queue. Use `delivery: "queue"` for an intended next turn, and `delivery: "interrupt"` when the current turn must stop immediately. If steering is unavailable or the turn has ended, check status and choose the next action by intent; use `continue` for a finished job. Submission or acceptance does not prove model execution.

Reviews and second opinions go to Codex (`EXECUTOR: codex`). When the user picks qodercli (`EXECUTOR: qoder`), choose its model by complexity. Work whose shape is already settled -- a scoped change, a question answered by reading a known area -- runs on its default model, which is fast and cheap enough to run many at once. Medium-complexity work, more than the default should carry, uses `MODEL: performance` (GPT-5.6-sol, 1M context). Only high-complexity work -- deciding the approach or the architecture, and the implementation that follows from it -- uses `MODEL: ultimate` (Opus 5).
```
