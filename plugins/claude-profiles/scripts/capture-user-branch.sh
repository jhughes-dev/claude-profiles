#!/usr/bin/env bash
# Convert ~/.claude into a git working tree on the user-profile branch of the
# configured profiles repo, without disturbing the live files.
#
# Usage: capture-user-branch.sh [branch]
#   [branch] is the user-profile branch name. Any name is allowed (e.g. 'user'
#   or 'main'). When given, it is persisted to the global config; otherwise the
#   stored preference is used, defaulting to 'user'.
#
# Steps:
#  1. `git init -b <branch>` if not already a git repo.
#  2. Add the configured profiles repo as `origin`.
#  3. Fetch; if `origin/<branch>` exists, soft-reset HEAD onto it (so already-
#     pushed content shows as untracked rather than as a giant diff).
#  4. Apply the standard ignore set so runtime state doesn't get staged.
#  5. Stage everything not ignored, commit, and push -u.
set -uo pipefail

dir="$HOME/.claude"
here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
repo=$(pcfg_default_repo)
if [ -z "$repo" ]; then
  echo "no profiles repo configured — run /claude-profiles:init first" >&2
  exit 1
fi
[ -d "$dir" ] || { echo "$dir does not exist" >&2; exit 1; }

# Resolve the user-profile branch: explicit arg (persisted) > stored pref > 'user'.
branch="${1:-}"
if [ -n "$branch" ]; then
  pcfg_set_pref userBranch "$branch"
else
  branch=$(pcfg_get_pref userBranch); [ -n "$branch" ] || branch=user
fi

# 1) Init + branch.
if [ ! -d "$dir/.git" ]; then
  git -C "$dir" init -b "$branch" >/dev/null
fi
current=$(git -C "$dir" branch --show-current 2>/dev/null)
if [ -z "$current" ]; then
  git -C "$dir" checkout -b "$branch"
elif [ "$current" != "$branch" ]; then
  echo "$dir is on branch '$current' — refusing to overwrite. Switch to '$branch' manually if appropriate." >&2
  exit 1
fi

# 2) Origin.
if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
  git -C "$dir" remote add origin "$repo"
fi

# 3) Align with origin/<branch> if it already exists.
git -C "$dir" fetch -q origin 2>/dev/null || true
if git -C "$dir" rev-parse --verify -q "origin/$branch" >/dev/null 2>&1; then
  git -C "$dir" reset --soft "origin/$branch" 2>/dev/null || git -C "$dir" reset "origin/$branch"
fi

# 4) Standard ignore set — runtime state, plugin caches, embedded plugin clones.
gitignore="$dir/.gitignore"
{
  cat <<'EOF'
# claude-profiles: runtime state
backups/
cache/
debug/
file-history/
history.jsonl
ide/
paste-cache/
projects/
session-env/
mcp-needs-auth-cache.json
.last-cleanup
# plugin runtime
plugins/cache/
plugins/marketplaces/
plugins/blocklist.json
plugins/plugin-catalog-cache.json
EOF
} > "$gitignore.tmp"
# Merge with whatever's already there, deduped, preserving order.
if [ -f "$gitignore" ]; then
  awk '!seen[$0]++' "$gitignore" "$gitignore.tmp" > "$gitignore.new"
  mv "$gitignore.new" "$gitignore"
  rm -f "$gitignore.tmp"
else
  mv "$gitignore.tmp" "$gitignore"
fi

# 5) Stage everything not ignored.
git -C "$dir" add -A

# Drop any embedded git repos (skill clones from plugins) staged as gitlinks.
git -C "$dir" ls-files --stage 2>/dev/null \
  | awk '$1 == "160000" {print $4}' \
  | while read -r path; do
      [ -n "$path" ] && git -C "$dir" rm --cached -f "$path" >/dev/null
    done

if git -C "$dir" diff --cached --quiet 2>/dev/null; then
  echo "nothing to commit (already in sync with origin/$branch)"
  exit 0
fi
git -C "$dir" commit -m "Capture ~/.claude as user profile"
git -C "$dir" push -u origin -- "$branch"
