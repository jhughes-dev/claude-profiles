# claude-profiles

A Claude Code plugin for managing per-workspace `.claude` profiles backed by a
git repo of profile branches.

Each workspace's `.claude/` is a clone of a *profiles repo* on a chosen branch.
Different scenarios (rust-cli, web-dev, claude-addon-dev, etc.) live on
different branches. Configuring or sharing a profile is plain git.

**This repo is just the plugin.** Your profiles live in a separate repo that
you own and create — install the plugin and run `/claude-profiles:init` to set
one up.

## Install

In Claude Code:

```text
/plugin marketplace add git@github.com:jhughes-dev/claude-profiles.git
/plugin install claude-profiles@claude-profiles
```

Then run `/claude-profiles:init` to configure your profiles repo. The wizard handles:

- Pointing at an **existing** repo (URL or local path).
- Creating **a new remote** (uses `gh`/`glab` if available).
- Initializing a **new local** bare repo.

It will also offer to capture your current `~/.claude` config as your user
profile on your new profiles repo (without overwriting any live files). The
user-profile branch name is your choice — `user` by default, or any name (e.g.
`main`); it's recorded in the global config.

## Your profiles repo

`/claude-profiles:init` sets up a separate git repo that you own. It is **not**
this plugin repo — it holds your profiles, one per branch:

| Branch | Role |
| --- | --- |
| `template` | Starting content for new profile branches. `/claude-profiles:set --new` clones from here. |
| `user` | Your personal `~/.claude` config, captured during `init`. The branch name is configurable (default `user`; can be any branch, e.g. `main`). |
| Scenario branches | One per development context (rust-cli, web-development, etc.). |

## Workspace commands

Once `/claude-profiles:init` is done, in any workspace:

```text
/claude-profiles:set                  # interactive branch picker
/claude-profiles:set rust-cli         # clone a specific profile
/claude-profiles:set --new my-thing   # new branch from template, configure then push
/claude-profiles:set --new combo --from rust-cli,addons-dev   # merge two profiles into a new branch
/claude-profiles:set --none           # mark workspace as no-profile
/claude-profiles:status               # show sync status of this workspace's profile
/claude-profiles:update               # pull + push this workspace's profile (resolve conflicts)
/claude-profiles:configure            # promote user-space config (plugins/skills/settings) into this profile
/claude-profiles:source list          # list profile sources
/claude-profiles:source add work git@host:team/profiles.git   # draw profiles from another repo
```

The plugin's `SessionStart` hook reminds you to commit/push profile changes,
pull updates, or run `/claude-profiles:set` in workspaces that don't have one yet.

## Multiple sources

Profiles can come from more than one repo — e.g. a personal repo plus a shared
team repo. Manage them with `/claude-profiles:source` (`add`/`remove`/`list`/`default`).
`/claude-profiles:set <branch>` finds which source provides a branch and asks
when several share the same name; the chosen source is recorded in the
workspace marker's `source` field so future syncs pull from the right repo.

A `.claude-profiles` marker (JSON) at the workspace root records the chosen
profile — `{ "version": 1, "profile": "<branch>", "source": "<name>", "repo":
"<url>" }`. Commit it. User-level config lives at
`~/.config/claude-profiles/config.json`. Both follow the schemas in
[`plugins/claude-profiles/schemas/`](plugins/claude-profiles/schemas/); legacy
`key=value` files from earlier versions are read and migrated automatically.

## Maintenance

- Shared skills/agents in `template`; merge `template` forward into scenario branches.
- `settings.json`, `CLAUDE.md`, `.gitignore` intentionally diverge per branch — when
  merging, resolve in favor of the branch.
