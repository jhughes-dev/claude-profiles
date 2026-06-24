---
description: Check this workspace's .claude profile sync status against the claude-profiles repo
---

Check the sync status of this workspace's `.claude` profile.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"` and parse its
   `key=value` output. The script handles fetch, dirty detection, and ahead/behind
   counts; you don't need to run any git commands yourself.

2. Report the `summary` line to the user, then act based on `action`:
   - `init` → suggest `/claude-profiles:set` to configure a profile. Stop.
   - `opt_out_cleanup` → tell the user this workspace opted out; they can delete
     `.claude` and run `/claude-profiles:set` to adopt a profile. Stop.
   - `clean` → just confirm it's up to date. Stop.
   - `commit` → offer to commit and push the uncommitted changes (propose a
     one-line message and confirm).
   - `push` → offer to run `git -C .claude push`.
   - `pull` → offer to run `git -C .claude pull`.
   - `rebase` → offer to run `/claude-profiles:update` (which handles the
     diverged case end-to-end including conflicts).

   Run the chosen action only after the user agrees.
