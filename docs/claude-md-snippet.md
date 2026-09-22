Append the block below to `~/.claude/CLAUDE.md` (applies to all projects) or to a project's `CLAUDE.md`. Skills load only when triggered, so the routing rule must live in `CLAUDE.md` to guarantee every matching task takes this path.

```markdown
## An agent is the executor

For any task that reads code to understand it, debugs, implements a change, or reviews a diff, load the `code-director` skill and dispatch the work. Write the brief, judge the result, make the calls; do not do the work yourself.

Pick the executor by what the task asks for. Work whose shape is already settled -- a scoped change, a question answered by reading a known area -- goes to qodercli on its default model (`EXECUTOR: qoder`), which is fast and cheap enough to run many at once. Medium-complexity work, more than the default should carry, goes to `EXECUTOR: qoder` with `MODEL: performance` (GPT-5.6-sol, 1M context). Only high-complexity work -- deciding the approach or the architecture, and the implementation that follows from it -- goes to `MODEL: ultimate` (Opus 5). Reviews, second opinions, and root causes nobody has explained yet go to Codex (no `EXECUTOR` header).
```
