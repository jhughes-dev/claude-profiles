---
name: describe
description: Set this workspace profile's one-line self-description, shown when picking profiles
argument-hint: "[description text]"
disable-model-invocation: true
---

Give the current profile a short self-description so it's easy to recognize when
picking profiles later. The description lives on the branch (in
`.claude/.profile-description`) and is cached in the config.

1. Ensure a profile is active: `.claude` must be a profile clone
   (`git -C .claude rev-parse --is-inside-work-tree`). If not, tell the user to
   run `/claude-profiles:set` first and stop.

2. Determine the text. Use `"$ARGUMENTS"` if provided; otherwise ask the user for
   a one-line summary of what this profile is for (e.g. "Rust CLI projects:
   clippy-strict, cargo aliases").

3. Write and cache it:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-profile-description.sh" "<text>"`

4. Offer to commit and push so other workspaces (and profile selection) pick it
   up:
   `git -C .claude add .profile-description && git -C .claude commit -m "Describe profile: <text>" && git -C .claude push`
