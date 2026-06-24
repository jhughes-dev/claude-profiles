---
name: init
description: First-time setup for the claude-profiles system (configure profiles repo and capture current ~/.claude)
disable-model-invocation: true
---

Walk the user through configuring a profiles repo for the first time.

The "upstream" repo (used by the *new remote (fork)* path below) defaults to
`git@github.com:jhughes-dev/claude-profiles.git`. If the user has
exported `CLAUDE_PROFILES_UPSTREAM` in their environment, use that value
instead. Otherwise use the default; do not prompt for it.

## 1. Short-circuit if already configured

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-config.sh"` and parse its
`key=value` output:

- `state=ok` → tell the user it's already configured (`repo=` value) and stop.
- `state=unreachable` → tell the user the config points at an unreachable repo
  and ask whether to reconfigure (continue below) or stop.
- `state=missing` or `state=no_repo` → continue.

## 2. Choose how to host the profiles repo

Ask the user one question with three options:

- **Existing repo** — they already have one (local or remote).
- **New remote** — fork the upstream on GitLab/GitHub.
- **New local** — initialize a bare repo on this machine.

### Existing repo

Ask for the URL or local path. Validate with `git ls-remote --heads "<url>"`.

### New remote (fork)

Detect available CLI:

- If `glab` is installed and authenticated (`glab auth status` succeeds), run
  `glab repo fork "$CLAUDE_PROFILES_UPSTREAM" --clone=false` and capture the URL.
- Else if `gh` is installed and authenticated and the upstream is GitHub, run
  `gh repo fork --clone=false`.
- Else fall back: print the "fork in UI" URL (GitLab: append `/-/forks/new`;
  GitHub: append `/fork`) and ask the user to paste the resulting fork URL.

### New local

Ask for an absolute path (default `$HOME/claude-profiles.git`). Then run:

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-local-repo.sh" <path> "$CLAUDE_PROFILES_UPSTREAM"`

The script handles `git init --bare` (if needed) and pushes `main` and
`template` from upstream into the new repo. If either branch is missing on
upstream the script emits a `WARNING:` line on stderr — surface those warnings
to the user verbatim. In particular, if `template` is missing, tell the user
that `/claude-profiles:set --new` won't work until they create a `template`
branch on the new repo.

The repo URL is `file://<path>`.

## 3. Persist the repo URL

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-config.sh" <repo-url>`

## 4. Offer to capture the current `~/.claude` as the user-profile branch

If `~/.claude/.git` does not exist, ask:

> Capture your existing ~/.claude config as your user profile on your profiles
> repo? This is reversible — your live files won't be overwritten.

If yes, also ask which **branch name** to use for the user profile (default
`user`; any name works — e.g. `main` if you'd rather it be the repo's default
branch). Then run, passing the chosen branch:

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/capture-user-branch.sh" <branch>`

The script persists the branch choice to the global config, then handles
`git init`, remote setup, ignore rules for runtime state, removing embedded
plugin gitlinks, and the initial push. Surface its output to the user.

If no: tell them they can run `/claude-profiles:set` later in any workspace.

## 5. Summary

Print:

- **Profiles repo**: `<url>`
- **Config file**: `~/.config/claude-profiles/config.json`
- **Captured `~/.claude` as user profile**: yes/no (branch name if yes)

Next steps:

- `/claude-profiles:set` to configure a workspace's `.claude`.
- `/claude-profiles:configure` to promote user-space config (plugins/skills/settings) into a profile.
- `/claude-profiles:status` to see if a workspace's profile is in sync.
- `/claude-profiles:update` to pull and push profile changes.
- `/claude-profiles:source add <name> <url>` to draw profiles from additional repos.
