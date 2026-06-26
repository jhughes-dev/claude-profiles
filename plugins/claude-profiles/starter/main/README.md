# My Claude profiles

This repository holds my
[claude-profiles](https://github.com/jhughes-dev/claude-profiles) profiles —
one Claude Code `.claude` configuration per git branch. It is **mine**; nothing
here needs to come back to the plugin.

- **`template`** — starter content that new profiles are branched from.
- Scenario branches (e.g. `rust-cli`, `web-dev`) — one per development context.
- A user-profile branch (default `user`) — a capture of `~/.claude`, if I made one.

Point a workspace at a profile with `/claude-profiles:set <branch>`. See the
plugin's README for the full workflow.
