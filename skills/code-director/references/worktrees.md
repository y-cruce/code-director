# Worktrees for parallel writers

Only one writer works in a checkout at a time, the director included. For parallel edits, create a fresh worktree per write task before dispatch and pass its absolute path as `cwd`.

## Create

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree /abs/source-repo /abs/new-worktree worker/topic
```

The helper pins the source HEAD, registers fresh Git metadata, and clones tracked files copy-on-write where APFS supports it (Python 3 is needed on macOS for native `clonefile`). Source edits and missing files are checked out from the pinned commit; untracked and ignored files, including installed dependencies and build outputs, are not copied. Keep the source stable while it runs. Check the returned `cwd`, `branch` and `base`; `clonedFiles`, `copiedFiles` and `checkoutFiles` show how much was actually cloned. Never copy an existing `.git` file by hand.

Git submodules, nested ones included, are initialized at the commits the pinned parent records, each with its own Git directory and object store. Local source submodules supply clones; otherwise Git clones from the configured URL, and pinned commits missing locally are fetched from it, which needs network access. Missing access or objects fail the creation and leave the incomplete directory for inspection: do not dispatch into it.

- **Per-repo cap**: newer plugins count registered linked worktrees per repository with `git worktree list --porcelain` (excluding the main checkout) and cap each repository independently at **10** by default (submodule repositories are counted separately; `CODEX_WORKTREE_MAX_SLOTS` adjusts the limit). When the cap is reached, creation refuses without creating a directory or branch and lists every existing linked worktree with its path, branch, and uncommitted/untracked status. Remove finished worktrees first with `worktree remove` before creating a new one; if every existing worktree is still active or waiting for `continue`, let additional write tasks wait until one finishes and is removed.

## Shared dependency caches (keep each worktree small)

Tracked source files are APFS copy-on-write cloned; disk growth comes from duplicated dependencies and build outputs:

- **Maven**: always use the shared `~/.m2/repository` directly. Never copy or clone `~/.m2` (including `cp -c`) into a worktree, and never point `-Dmaven.repo.local` to another directory.
- **Go**: share the global `GOMODCACHE` and `GOCACHE`; do not set per-worktree Go module/build caches.
- **Node.js**: prefer `pnpm` (global content-addressed store). Never symlink or hard-link a shared writable dependency or build output directory.

## Use

- Executors stay in their assigned directory. Before building, check symlinks and absolute paths, and keep writable build outputs (`target/`, `dist/`, etc.) local to the worktree.
- Read-only investigations can share a repository at a pinned SHA without creating a worktree; parallel tests that write files need their own worktree too.
- A thread stays tied to the `cwd` it was created in, so keep its worktree while further `continue` rounds are needed.

## Remove

After judging the result and integrating the chosen commits, stop the task and its builds, then recycle the worktree:

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree remove /abs/source-repo /abs/worktree
```

It refuses while the parent or any submodule has uncommitted, untracked or ignored files, while a submodule has commits outside its recorded initial refs and remote-tracking refs (including commits kept only by reflogs after a reset), or (on newer plugins) while parent `HEAD` has commits not reachable from any branch, tag or remote ref (listing their SHAs). Preserve or push those commits first, and do not bypass the check with a manual force-remove. The parent branch is kept.
