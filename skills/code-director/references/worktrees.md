# Worktrees for parallel writers

Only one writer works in a checkout at a time, the director included. For parallel edits, create one worktree per route before dispatch and pass its absolute path as `cwd`.

## Create

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree /abs/source-repo /abs/new-worktree worker/topic
```

The helper pins the source HEAD, registers fresh Git metadata, and clones tracked files copy-on-write where APFS supports it (Python 3 is needed on macOS for native `clonefile`). Source edits and missing files are checked out from the pinned commit; untracked and ignored files, including installed dependencies and build outputs, are not copied. Keep the source stable while it runs. Check the returned `cwd`, `branch` and `base`; `clonedFiles`, `copiedFiles` and `checkoutFiles` show how much was actually cloned. Never copy an existing `.git` file by hand.

Git submodules, nested ones included, are initialized at the commits the pinned parent records, each with its own Git directory and object store. Local source submodules supply clones; otherwise Git clones from the configured URL, and pinned commits missing locally are fetched from it, which needs network access. Missing access or objects fail the creation and leave the incomplete directory for inspection: do not dispatch into it.

## Use

- Executors stay in their assigned directory. Before building, check symlinks and absolute paths; install dependencies in the worktree or use repository-supported immutable caches. Do not hard-link writable files or point several writers at the same dependency or output directory.
- Reuse an idle worktree when its branch and contents fit the next task.
- Read-only investigations can share a repository at a pinned SHA; parallel tests that write files need their own worktree too.
- A thread stays tied to the `cwd` it was created in, so keep its worktree while further `continue` rounds are needed.

## Remove

After judging the result and integrating the chosen commits, stop the task and its builds, then:

```bash
bash ~/.claude/skills/code-director/scripts/dispatch.sh worktree remove /abs/source-repo /abs/worktree
```

It refuses while the parent or any submodule has uncommitted, untracked or ignored files, or while a submodule has commits outside its recorded initial refs and remote-tracking refs (including commits kept only by reflogs after a reset). Preserve or push those commits first, and do not bypass the check with a manual force-remove. The parent branch is kept.
