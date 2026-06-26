#!/usr/bin/env bash
# Clone a profile branch into <workspace>/.claude.
# If <new-branch> is provided, treat <branch> as the starting point (template)
# and create <new-branch> locally; otherwise clone <branch> directly.
#
# Usage: clone-profile.sh <branch> [new-branch] [workspace-dir]
# Refuses to overwrite an existing .claude — caller must remove it first.
set -uo pipefail

branch="${1:?usage: clone-profile.sh <branch> [new-branch] [workspace-dir]}"
new_branch="${2:-}"
workspace="${3:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
repo=$(pcfg_active_repo)
if [ -z "$repo" ]; then
  echo "no profiles repo configured — run /claude-profiles:init" >&2
  exit 1
fi

if [ -e "$dir" ]; then
  echo ".claude already exists at $dir — remove it first" >&2
  exit 1
fi

git clone --branch "$branch" --single-branch "$repo" "$dir" || exit $?

if [ -n "$new_branch" ]; then
  git -C "$dir" checkout -b "$new_branch" || exit $?
  git -C "$dir" push -u origin -- "$new_branch" || {
    echo "Created local branch '$new_branch' from '$branch' but failed to push." >&2
    echo "Push manually with: git -C .claude push -u origin $new_branch" >&2
    exit 1
  }
  echo "Created and pushed branch '$new_branch' from '$branch'."
fi

# Opportunistically cache this profile's self-description (issue #3).
# Only for a direct clone — a new-from-template branch has no description yet.
if [ -z "$new_branch" ]; then
  bash "$here/cache-description.sh" "$branch" "$workspace" >/dev/null 2>&1 || true
fi
