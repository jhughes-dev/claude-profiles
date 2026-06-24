#!/usr/bin/env bash
# Write/update the repo= line in ~/.claude-profiles-config.
# Usage: write-config.sh <repo-url-or-path>
set -uo pipefail

repo="${1:?usage: write-config.sh <repo-url>}"
config="$HOME/.claude-profiles-config"

if [ -f "$config" ] && grep -q '^repo=' "$config"; then
  sed -i.bak "s|^repo=.*|repo=$repo|" "$config" && rm -f "$config.bak"
else
  printf 'repo=%s\n' "$repo" >> "$config"
fi
echo "wrote repo=$repo to $config"
