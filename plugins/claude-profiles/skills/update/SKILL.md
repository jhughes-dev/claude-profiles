---
name: update
description: Pull then push this workspace's .claude profile branch, prompting on conflicts
disable-model-invocation: true
---

Sync this workspace's `.claude` profile with its remote.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/profile-update.sh"`. It performs the
   deterministic cases (push when ahead, fast-forward when behind, rebase+push
   when diverged) and only stops for cases requiring human judgement. Parse the
   `key=value` output.

2. Report `summary` to the user. Then act based on `action`:

   - `clean`, `pushed`, `pulled`, `rebased_pushed` → done. Stop.

   - `init` / `opt_out_cleanup` → tell the user there's nothing to update. Stop.

   - `needs_commit` → uncommitted changes block the update. Ask the user
     whether to (a) commit them now (offer a one-line message and run
     `git -C .claude commit -am "<msg>"`), (b) stash them
     (`git -C .claude stash`), or (c) abort. After committing or stashing,
     re-run this command.

   - `needs_resolve` → rebase hit conflicts. Read the `conflicts=` list. For
     each file ask whether to (a) keep ours (`git -C .claude checkout --ours <file>`),
     (b) take theirs (`git -C .claude checkout --theirs <file>`), or (c) edit
     manually. After each is resolved, `git -C .claude add <file>`. When all
     are staged, run `git -C .claude rebase --continue` and then
     `git -C .claude push`. If the user wants to bail, run
     `git -C .claude rebase --abort`.

   - `push_failed` / `pull_failed` → show the user the failing command's
     output so they can investigate (e.g. permission denied, non-fast-forward).
     Don't retry blindly.
