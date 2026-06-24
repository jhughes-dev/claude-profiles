#!/usr/bin/env bash
# List profile branches on the configured profiles repo, one per line.
# Excludes 'template'. Reads the repo URL from ~/.claude-profiles-config.
# Usage: list-branches.sh
# Exits non-zero with an error message on stderr if no repo is configured
# or the remote is unreachable.
set -uo pipefail

config="$HOME/.claude-profiles-config"
if [ ! -f "$config" ]; then
  echo "no claude-profiles config — run /claude-profiles:init" >&2
  exit 1
fi
repo=$(sed -n 's/^repo=//p' "$config" | head -n1)
if [ -z "$repo" ]; then
  echo "no repo= line in $config — run /claude-profiles:init" >&2
  exit 1
fi

git ls-remote --heads "$repo" 2>/dev/null \
  | awk '{sub("refs/heads/","",$2); print $2}' \
  | grep -v '^template$' \
  | sort
