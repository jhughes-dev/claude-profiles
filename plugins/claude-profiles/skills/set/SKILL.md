---
name: set
description: Configure the Claude profile (.claude folder) for this workspace
argument-hint: "[branch | --new <branch> [--from <a>,<b>,...] | --adopt <branch> | --none]"
disable-model-invocation: true
---

Configure this workspace's `.claude` folder from the user's profiles repo.

Profiles come from one or more **sources** in `~/.config/claude-profiles/config.json`
(manage them with `/claude-profiles:source`). If no source is configured, tell
the user to run `/claude-profiles:init` first and stop. The bundled scripts
under `${CLAUDE_PLUGIN_ROOT}/scripts/` read this config; you don't need to pass
URLs around explicitly.

**Source resolution.** When the user names an existing branch, find which
source provides it by running
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-branches.sh" --by-source` (it prints
`<source>\t<branch>\t<description>` lines):

- Exactly one source has the branch → use it.
- Several sources have a branch of that name → **ask the user which source**.
- None list it → fall back to the default source (the branch may be new/uncached).

Then export `CLAUDE_PROFILES_SOURCE=<source>` for the clone/adopt/marker scripts
below — they operate on that source's repo and record it in the marker. With a
single source you can skip this; everything defaults to it.

Arguments given: "$ARGUMENTS"

## 1. Pre-check the marker

If a `.claude-profiles` marker already exists at the workspace root, the user is
asking to change the profile. Show the current profile (the marker's `profile`
field) and confirm before proceeding. On yes, delete the existing `.claude/`
folder (if any) and continue. The marker will be rewritten in step 5.

## 2. Determine the mode

- A bare branch name → existing-branch path (step 3a).
- `--new <branch>` → new-from-template path (step 3b).
- `--new <branch> --from <a>,<b>,...` → merge two-or-more existing profiles
  into a new branch (step 3d). The first entry in `--from` is the base; each
  remaining entry is merged into it in order.
- `--adopt <branch>` → adopt path (step 3c).
- `--none` → run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-marker.sh" none` and stop.
- No arguments → ask the user. Tailor the menu to the workspace state:

  - **`.claude` exists, not a profile clone** → offer adopt / replace-with-existing /
    replace-with-template / opt-out.
  - **`.claude` exists, already a profile clone** → just write the marker matching
    its current branch (`git -C .claude branch --show-current`) and stop.
  - **No `.claude`** → offer existing / new-from-template / opt-out.

  To list available branches, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-branches.sh"`
  (or `--by-source` to see each branch's source and cached description). Show the
  descriptions to help the user choose; a profile's description is filled in once
  it's been cloned/adopted (or set via `/claude-profiles:describe`).

  **Recommend a match first.** Run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-project.sh"` to infer the
  workspace's stack (e.g. `rust`, `node`, `tauri`, `claude-plugin`). Match those
  traits against the branch names and descriptions and surface the best-fitting
  profile(s) at the top of the menu, before the full list.

## 3. Execute the chosen mode

### 3a. Existing branch

Resolve the source first (see **Source resolution** above) and export
`CLAUDE_PROFILES_SOURCE` if more than one source exists. Then run the one-shot
setup (clone + `.gitignore` + marker + cache refresh, in one deterministic step):

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-profile.sh" <branch>`

Parse its `state=`/`summary=` output and report it. If `.claude` already exists,
ask before deleting it; the script refuses to overwrite. **It already does steps
4 and 5 — skip them.**

### 3b. New from template

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-profile.sh" --new <branch>`

This branches the `template` branch into a new `<branch>`, pushes it, ignores
`.claude/`, writes the marker, and refreshes the cache. (Add `--from <base>` to
branch from a different base.) Tell the user to customize `.claude/` — subsequent
edits push from `.claude` as normal. **Steps 4 and 5 are handled — skip them.**

### 3d. Merge existing profiles into a new branch

Parse `--from` as a comma-separated list. The first entry is the base; the
rest are merged in order.

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-profile.sh" <branch> <base> <others-csv>`

Exit codes:

- **0** — clean merge, branch pushed. Run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-branches-cache.sh"` and continue
  to step 4.
- **2** — conflicts. The script printed the conflicting files and a resolution
  checklist; do **not** proceed past step 3. Tell the user to resolve in
  `.claude/`, then commit and push manually. Skip steps 4 and 5 — the user
  will re-run `/claude-profiles:set <branch>` after pushing.
- **other** — hard failure (clone/fetch/push). Surface the script's stderr.

### 3c. Adopt existing `.claude`

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/adopt-profile.sh" <branch>`

The script handles three cases (no git, our remote already, different remote)
and exits non-zero with an explanation if it can't proceed. After a successful
adopt, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-branches-cache.sh"`.

## 4. Update workspace .gitignore (adopt/merge paths only)

*(3a and 3b already did steps 4 and 5 via `setup-profile.sh`. Do steps 4–5 only
for the adopt (3c) and merge (3d) paths.)*

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gitignore.sh"` and parse the
`state=` line:

- `not_git` or `already_ignored` → nothing to do.
- `added` → tell the user `.claude/` was appended to `.gitignore`.

If the user explicitly wants to *track* `.claude/` in the project repo instead,
skip the script and warn them that committing `.claude/` while it's a git clone
will embed it as a gitlink unless they take further steps.

## 5. Write the marker

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-marker.sh" <branch>`

This records the chosen profile so the SessionStart hook knows the workspace's
intended state. Tell the user to commit the `.claude-profiles` file to the
project repo so collaborators see which profile this project expects.
