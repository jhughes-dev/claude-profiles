#!/usr/bin/env bash
# Adopt the existing <workspace>/.claude folder as a new profile branch on the
# configured profiles repo. Pushes <branch> to origin.
#
# Usage: adopt-profile.sh <branch> [workspace-dir]
#
# Behavior:
#  - If .claude isn't a git repo yet: `git init -b <branch>`, add origin, commit,
#    push -u.
#  - If .claude already has a git repo pointing at our profiles repo:
#    refuse — nothing to adopt.
#  - If .claude has a git repo pointing somewhere else: rename remote to
#    `origin-old`, add ours as `origin`, force-rename branch, push.
set -uo pipefail

branch="${1:?usage: adopt-profile.sh <branch> [workspace-dir]}"
workspace="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
repo=$(pcfg_active_repo)
if [ -z "$repo" ]; then
  echo "no profiles repo configured — run /claude-profiles:init" >&2
  exit 1
fi
pcfg_validate_repo "$repo" || { echo "refusing unsafe configured repo URL" >&2; exit 1; }
if [ ! -d "$dir" ]; then
  echo "no .claude folder at $dir — nothing to adopt" >&2
  exit 1
fi

if [ -d "$dir/.git" ]; then
  current_origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  if [ "$current_origin" = "$repo" ]; then
    echo ".claude is already a clone of $repo — nothing to adopt" >&2
    exit 1
  fi
  if [ -n "$current_origin" ]; then
    git -C "$dir" remote rename origin origin-old
  fi
  git -C "$dir" remote add origin "$repo"
  # Rename current branch to <branch> (force, in case it already exists locally).
  current_branch=$(git -C "$dir" branch --show-current)
  if [ -n "$current_branch" ] && [ "$current_branch" != "$branch" ]; then
    git -C "$dir" branch -M "$branch"
  fi
  git -C "$dir" push -u origin -- "$branch" || exit $?
  bash "$here/cache-description.sh" "$branch" "$workspace" >/dev/null 2>&1 || true
  exit 0
fi

# Fresh: init + first commit + push. Guard each mutation so a failure (e.g. no
# git user.name/email configured) surfaces instead of being masked.
git -C "$dir" init -b "$branch" || exit $?
git -C "$dir" remote add origin "$repo" || exit $?
git -C "$dir" add -A || exit $?
git -C "$dir" commit -m "Adopt existing .claude as profile '$branch'" || exit $?
git -C "$dir" push -u origin -- "$branch" || exit $?
bash "$here/cache-description.sh" "$branch" "$workspace" >/dev/null 2>&1 || true
