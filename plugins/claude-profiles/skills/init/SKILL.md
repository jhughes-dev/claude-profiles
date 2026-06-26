---
name: init
description: First-time setup for the claude-profiles system (configure profiles repo and capture current ~/.claude)
disable-model-invocation: true
---

Walk the user through configuring a profiles repo for the first time.

New profiles repos are seeded with starter content — a `main` landing branch and
a `template` profile — bundled with the plugin under
`${CLAUDE_PLUGIN_ROOT}/starter/`. There is no external upstream to fork or
depend on: the repo the user ends up with is entirely their own.

## 1. Short-circuit if already configured

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-config.sh"` and parse its
`key=value` output:

- `state=ok` → tell the user it's already configured (`repo=` value) and stop.
- `state=unreachable` → tell the user the config points at an unreachable repo
  and ask whether to reconfigure (continue below) or stop.
- `state=missing` or `state=no_repo` → continue.

## 2. Choose how to host the profiles repo

Ask the user one question with three options. All three end with a repo that is
entirely theirs — none of them fork or depend on the plugin's repo.

- **Existing repo** — they already have one (local or remote).
- **New remote** — create a brand-new empty repo they own on GitHub/GitLab, then
  seed it with the bundled starter.
- **New local** — initialize a bare repo on this machine, seeded with the bundled
  starter. A first-class option — a profiles repo never has to live on a hosting
  service.

### Existing repo

Ask for the URL or local path. Validate with `git ls-remote --heads "<url>"`.

### New remote

The goal is a **new, empty repo the user owns** — never a fork of the plugin's
repo. Ask how they'd like to create it and help them through their choice:

- **With a CLI** — if `gh` is installed and authenticated, run
  `gh repo create <name> --private` (GitHub); if `glab` is, run
  `glab repo create <name>` (GitLab). Capture the resulting URL.
- **In the web UI** — have them create an empty repository (no README) on their
  host and paste back the clone URL.

Then seed it with the bundled starter by building the branches locally and
pushing them up:

```bash
tmpbare="$(mktemp -d)/seed.git"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-local-repo.sh" "$tmpbare"
git -C "$tmpbare" push "<new-repo-url>" main template
```

The repo URL is the one they just created.

### New local

Ask for an absolute path (default `$HOME/claude-profiles.git`). Then run:

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-local-repo.sh" <path>`

The script creates the bare repo (if needed) and seeds `main` and `template`
from the plugin's bundled starter — no network and no upstream involved.

The repo URL is `file://<path>`. A local bare repo is a real git remote: every
workspace `/claude-profiles:set` clones from that `file://` URL exactly as it
would from a hosted one, and you can `git clone`, push, and pull it like any
remote. To move it onto a hosting service later, create an empty remote and
`git -C <path> push <remote-url> --all`.

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

## 4b. Offer to set up this workspace now (autodetect)

If the current workspace looks like a real project (not the home dir), run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-project.sh"` to infer its stack and
offer to set up a fitting profile right away rather than leaving a generic menu
for later:

- Match the detected traits (e.g. `rust`, `node`, `tauri`, `claude-plugin`)
  against the available branches (`list-branches.sh --by-source`, with their
  descriptions).
- If a branch clearly fits, propose `/claude-profiles:set <branch>`; if nothing
  fits, propose `/claude-profiles:set --new <name>` seeded from `template`.
- Only proceed on the user's confirmation.

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
