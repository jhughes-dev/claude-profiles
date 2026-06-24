#!/usr/bin/env bash
# Write the .claude-profiles marker file at the workspace root.
# Usage: write-marker.sh <profile> [workspace-dir]
#   <profile> may be 'none' to record opt-out (omits repo=).
set -uo pipefail

profile="${1:?usage: write-marker.sh <profile> [workspace-dir]}"
workspace="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
marker="$workspace/.claude-profiles"

config="$HOME/.claude-profiles-config"
repo=$(sed -n 's/^repo=//p' "$config" 2>/dev/null | head -n1)

{
  printf 'profile=%s\n' "$profile"
  if [ "$profile" != "none" ] && [ -n "$repo" ]; then
    printf 'repo=%s\n' "$repo"
  fi
} > "$marker"

echo "wrote $marker"
