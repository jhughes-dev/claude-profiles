#!/usr/bin/env bash
# Inspect ~/.claude-profiles-config and report whether the configured repo is
# reachable. Used by /claude-profiles:init to short-circuit if already set up.
#
# Usage: check-config.sh
# Output (key=value):
#   state=missing|no_repo|unreachable|ok
#   repo=<url>           (when present)
#   summary=<one-line>
set -uo pipefail

config="$HOME/.claude-profiles-config"
emit() { printf '%s=%s\n' "$1" "$2"; }

if [ ! -f "$config" ]; then
  emit state missing
  emit summary "$config does not exist."
  exit 0
fi
repo=$(sed -n 's/^repo=//p' "$config" | head -n1)
if [ -z "$repo" ]; then
  emit state no_repo
  emit summary "$config has no repo= line."
  exit 0
fi
emit repo "$repo"
if git ls-remote --heads "$repo" >/dev/null 2>&1; then
  emit state ok
  emit summary "Profiles repo configured and reachable: $repo"
else
  emit state unreachable
  emit summary "Configured repo is unreachable: $repo"
fi
