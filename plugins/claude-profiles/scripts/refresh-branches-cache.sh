#!/usr/bin/env bash
# Refresh the branches= line in ~/.claude-profiles-config so the SessionStart
# hook doesn't flag a just-created branch as "new" on the next session.
# Usage: refresh-branches-cache.sh
set -uo pipefail

config="$HOME/.claude-profiles-config"
[ -f "$config" ] || exit 0
repo=$(sed -n 's/^repo=//p' "$config" | head -n1)
[ -n "$repo" ] || exit 0

branches=$(git ls-remote --heads "$repo" 2>/dev/null \
  | awk '{sub("refs/heads/","",$2); print $2}' \
  | grep -v '^template$' \
  | sort | paste -sd, -)
[ -n "$branches" ] || exit 0

if grep -q '^branches=' "$config" 2>/dev/null; then
  sed -i.bak "s|^branches=.*|branches=$branches|" "$config" && rm -f "$config.bak"
else
  printf 'branches=%s\n' "$branches" >> "$config"
fi
echo "refreshed branches cache: $branches"
