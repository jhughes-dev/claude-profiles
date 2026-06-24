---
description: Manage profile sources (the git repos that provide profile branches)
argument-hint: "[list | add <name> <url> [--default] | remove <name> | default <name>]"
---

Manage the profile **sources** in `~/.config/claude-profiles/config.json`. Each
source is a git repo whose branches are profiles. Most setups have a single
source created by `/claude-profiles:init`; add more to draw profiles from
several repos at once (e.g. a personal repo plus a shared team repo).

Arguments given: "$ARGUMENTS"

Parse `$ARGUMENTS` and run the matching bundled subcommand:

- **List** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/source.sh" list`
  Prints each source and its repo, with `*` marking the default. Run this when
  no arguments are given, and summarize the result.
- **Add** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/source.sh" add <name> <url> [--default]`
  Validates the repo is reachable, adds it, and caches its branches. Pass
  `--default` to make it the source used when a branch name is unqualified.
- **Remove** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/source.sh" remove <name>`
  Removes the source and its cached branch list (does not touch any workspace).
- **Set default** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/source.sh" default <name>`

`<name>` is a short identifier (letters, digits, `._-`) you choose; it's
recorded in each workspace's marker as the `source` field so syncs know which
repo a profile came from.

After adding a source, tell the user they can adopt its profiles with
`/claude-profiles:set <branch>` — that command auto-detects which source a
branch lives on and asks if more than one source has the same branch name.
