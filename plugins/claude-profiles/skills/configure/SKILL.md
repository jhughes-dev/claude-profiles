---
name: configure
description: Configure/onboard this workspace's profile by promoting config from user space (~/.claude) into it — enable plugins, copy skills/agents/commands/hooks, add CLAUDE.md guidance, and copy settings, tailored to the repo.
when_to_use: When the user wants to set up, onboard, or fill out the current workspace's profile, or move/enable plugins, skills, agents, hooks, or settings from their global ~/.claude into this profile.
---

Help the user configure **this workspace's profile** (`.claude/`) by promoting
the right pieces of their **user space** (`~/.claude/`) into it. This is the
onboarding step: "set up this profile for this repo."

Follow the `maintain-profile` skill's rules throughout (enable plugins, never
copy plugin files; keep secrets/machine paths out of profiles; ask scope when
unsure).

## 1. Require an active profile

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"` and read `state`:

- `ok` → continue.
- `missing` / `not_git` (no profile clone) → tell the user to run
  `/claude-profiles:set <branch>` first to put a profile in this workspace, then
  stop.

## 2. Understand the repo, then ask intent

Take a quick look at the workspace (language/framework/build files, README) to
infer what kind of project this is. Then **ask the user** what this profile is
for — keep it short, offer multiple-choice where natural (e.g. "Which of these
should this profile focus on?"). Use their answers to tailor every suggestion
below; recommend, don't dump everything.

## 3. Resolve the promote mode (preference)

Read the stored preference:
`bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/_lib.sh"; pcfg_get_pref promoteMode'`.

- If it prints `copy` or `move`, use that for file promotions (skills/agents/
  commands/hooks).
- If empty or `ask`, ask the user once: **copy** (keep the item in `~/.claude`
  too) or **move** (remove it from `~/.claude`), or "ask me each time". Persist
  their choice:
  `bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/_lib.sh"; pcfg_set_pref promoteMode <copy|move|ask>'`.
  (Store `ask` if they want to be asked every time.)

## 4. Survey user space

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-user-components.sh"`. It prints
tab-separated lines: `skill/agent/command/hook <name>`,
`plugin <name@marketplace> <true|false>`, `setting <key>`, `claudemd present`.

## 5. Offer to promote, by category

For each category, present the relevant candidates (multi-select) and act on the
user's picks:

- **Plugins** — for each chosen `name@marketplace`, edit the **profile's**
  `.claude/settings.json`: set `enabledPlugins["name@marketplace"] = true`
  (create the object/key if absent). If that marketplace isn't already known in
  the profile, copy its entry from `~/.claude/settings.json`
  `extraKnownMarketplaces` into the profile's. **Never copy plugin files.**
- **Skills / agents / commands / hooks** — for each chosen item run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/promote-component.sh" <type> <name> <mode> "$CLAUDE_PROJECT_DIR"`
  using the mode from step 3 (ask per item only if the preference is `ask`).
- **CLAUDE.md guidance** — if `claudemd present`, read `~/.claude/CLAUDE.md`,
  propose the rules that make sense for *this* profile (skip personal/global-only
  ones), and append the chosen lines to the profile's `.claude/CLAUDE.md`.
- **Settings** — for each chosen `setting` key, copy its value from
  `~/.claude/settings.json` into `.claude/settings.json`. Skip anything sensitive
  or machine-specific (absolute paths, secrets in `env`).

## 6. Review, commit, push

Show `git -C .claude status --short` so the user sees exactly what changed in the
profile. Offer to commit and push:
`git -C .claude add -A && git -C .claude commit -m "Configure profile: <summary>" && git -C .claude push`.

Then summarize what was enabled/copied and remind the user the profile branch now
carries this config for every workspace that uses it.
