Append the block below to `~/.claude/CLAUDE.md` (applies to all projects) or to a project's `CLAUDE.md`. Skills load only when triggered, so the routing rule must live in `CLAUDE.md` to guarantee every matching task takes this path.

```markdown
## An agent is the executor

For any task that reads code to understand it, debugs, implements a change, or reviews a diff, load the `code-director` skill and dispatch the work. Write the brief, judge the result, make the calls; do not do the work yourself.

Pick by difficulty: low to medium, implementation included, goes to qodercli (`EXECUTOR: qoder`), cheap enough to run many at once. Hard tasks and every review go to Codex. On the line, send it to Codex.
```
