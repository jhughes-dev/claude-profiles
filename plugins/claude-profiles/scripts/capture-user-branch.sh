#!/usr/bin/env bash
# Convert ~/.claude into a git working tree on the `user` branch of the
# configured profiles repo, without disturbing the live files.
#
# Usage: capture-user-branch.sh
#
# Steps:
#  1. `git init -b user` if not already a git repo.
#  2. Add the configured profiles repo as `origin`.
#  3. Fetch; if `origin/user` exists, soft-reset HEAD onto it (so already-pushed
#     content shows as untracked rather than as a giant diff).
#  4. Apply the standard ignore set so runtime state doesn't get staged.
#  5. Stage everything not ignored, commit, and push -u.
set -uo pipefail

dir="$HOME/.claude"
config="$HOME/.claude-profiles-config"
repo=$(sed -n 's/^repo=//p' "$config" 2>/dev/null | head -n1)
if [ -z "$repo" ]; then
  echo "no repo= in $config — run /claude-profiles:init first" >&2
  exit 1
fi
[ -d "$dir" ] || { echo "$dir does not exist" >&2; exit 1; }

# 1) Init + branch.
if [ ! -d "$dir/.git" ]; then
  git -C "$dir" init -b user >/dev/null
fi
current=$(git -C "$dir" branch --show-current 2>/dev/null)
if [ -z "$current" ]; then
  git -C "$dir" checkout -b user
elif [ "$current" != "user" ]; then
  echo "$dir is on branch '$current' — refusing to overwrite. Switch to 'user' manually if appropriate." >&2
  exit 1
fi

# 2) Origin.
if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
  git -C "$dir" remote add origin "$repo"
fi

# 3) Align with origin/user if it already exists.
git -C "$dir" fetch -q origin 2>/dev/null || true
if git -C "$dir" rev-parse --verify -q origin/user >/dev/null 2>&1; then
  git -C "$dir" reset --soft origin/user 2>/dev/null || git -C "$dir" reset origin/user
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
  echo "nothing to commit (already in sync with origin/user)"
  exit 0
fi
git -C "$dir" commit -m "Capture ~/.claude as user profile"
git -C "$dir" push -u origin user
