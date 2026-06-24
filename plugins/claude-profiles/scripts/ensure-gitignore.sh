#!/usr/bin/env bash
# Ensure .claude/ is in the workspace's .gitignore (only if the workspace is a
# git repo and .claude isn't already ignored).
# Usage: ensure-gitignore.sh [workspace-dir]
#
# Output (key=value):
#   state=not_git|already_ignored|added|skipped_no_workspace_repo
#   summary=<one-line>
set -uo pipefail

workspace="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
emit() { printf '%s=%s\n' "$1" "$2"; }

if ! git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit state not_git
  emit summary "Workspace isn't a git repo — skipping .gitignore."
  exit 0
fi

# Use a synthetic path inside .claude/ so the check works even when .claude/
# doesn't exist on disk yet. check-ignore evaluates the path against rules
# without requiring the file to exist.
if git -C "$workspace" check-ignore -q --no-index .claude/marker 2>/dev/null; then
  emit state already_ignored
  emit summary ".claude is already ignored."
  exit 0
fi

gitignore="$workspace/.gitignore"
if [ -f "$gitignore" ] && [ -n "$(tail -c1 "$gitignore" 2>/dev/null)" ]; then
  printf '\n.claude/\n' >> "$gitignore"
else
  printf '.claude/\n' >> "$gitignore"
fi
emit state added
emit summary "Appended '.claude/' to $gitignore."
