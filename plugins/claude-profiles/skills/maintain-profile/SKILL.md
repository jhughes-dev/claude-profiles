---
name: maintain-profile
description: Use when installing/enabling Claude Code plugins, adding skills/hooks/agents, editing settings.json or CLAUDE.md, or merging template forward into scenario branches. Explains user-vs-profile placement and how to keep profile branches healthy.
---

# Maintaining claude-profiles

A claude-profile is a git branch cloned into a workspace's `.claude/` folder.
One branch per scenario (e.g. `rust-cli`, `web-dev`); switch by switching
workspaces, not by editing config. The `template` branch holds shared starter
content that new profiles fork from. A `.claude-profiles` marker at the
workspace root records which profile this workspace expects (commit it to the
project repo). Treat the profile as **configuration**, not as a place to
install software.

## Where does new config go? Ask first.

Whenever the user adds a **skill, hook, agent, command, settings change, or
CLAUDE.md edit**, there are two valid destinations:

- **User space (`~/.claude/`)** — applies to *every* workspace this user opens.
  Use for genuinely cross-cutting tools, personal preferences, or anything the
  user wants available everywhere.
- **Local profile (`.claude/`, the current workspace's profile branch)** —
  applies only when this scenario branch is checked out. Use for
  scenario-specific behavior (language stack, project conventions, repo-aware
  hooks).

**If the user doesn't say which, ask.** A one-line question is cheaper than
moving the file later. Frame the choice around scope: "Should this apply to
every workspace, or only when the `<branch>` profile is active?"

Heuristics when the user gives no signal:

- Talks about "this project" / repo-specific behavior → local profile.
- Talks about "I always want…" / personal workflow → user space.
- Sensitive or machine-specific (API keys, absolute paths) → user space, never
  a profile branch (profiles get cloned into other workspaces).

## Plugins: install user-wide, enable per-profile

**Do not move a plugin's files into a profile branch.** Plugins are installed
once into the user's plugin directory (`~/.claude/plugins/...`) and then
*enabled* per profile by listing them in that profile's `settings.json`
(`enabledPlugins` / `enabledPluginMarketplaces`).

Why this matters:

- Plugins installed via `/plugin install` live in user space and are shared
  across all workspaces. Copying them into a profile branch duplicates the
  install, drifts from upstream, and breaks `/plugin` updates.
- A profile branch should contain *only* the settings and content that differ
  per scenario — `settings.json`, `CLAUDE.md`, project-specific skills/agents,
  and the enable-list for plugins this scenario needs.
- Multiple profiles can enable the same plugin without duplicating it on disk.

When the user says "add plugin X to this profile":

1. Confirm the plugin is installed in user space (`/plugin list` or check
   `~/.claude/plugins/`). If not, install it there first with `/plugin install`.
2. Edit the **profile's** `.claude/settings.json` to add the plugin to
   `enabledPlugins` (and its marketplace to `enabledPluginMarketplaces` if
   needed).
3. Commit the settings change to the profile branch.

If you find plugin source files that have been copied into a profile branch,
flag it — they should be removed and replaced with an enable-list entry.

## Other profile maintenance guidance

- **Shared content lives in `template`.** Skills, agents, or CLAUDE.md snippets
  that should reach every scenario go on the `template` branch and are merged
  forward into scenario branches.
- **Per-branch divergence is expected for `settings.json`, `CLAUDE.md`, and
  `.gitignore`.** When merging `template` forward, resolve conflicts in these
  files in favor of the scenario branch.
- **The `.claude-profiles` marker** at the workspace root records which branch
  this workspace expects. It belongs in the project repo, not the profile.
- **Don't commit secrets or machine-specific paths** to a profile branch — it
  will be cloned into every workspace using that scenario.
- **Scenario branches are long-lived.** Prefer editing in place and pushing
  over deleting/recreating; other workspaces may already have the branch
  cloned.
- **Combining two profiles.** Use `/claude-profiles:set --new <name> --from
  <a>,<b>` to clone branch `a` and merge `b` into it as a new branch. On
  conflicts the script stops and prints which files need manual resolution
  (JSON files want union; `CLAUDE.md` wants concatenation; `agents/`/`skills/`
  usually keep both).
