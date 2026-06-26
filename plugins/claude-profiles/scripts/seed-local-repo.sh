#!/usr/bin/env bash
# Initialize a bare repo at <path> (if missing) and seed it with `main` and
# `template` branches built from the plugin's bundled starter content. No
# network and no upstream repo is involved — the starter ships with the plugin.
#
# Usage: seed-local-repo.sh <bare-path> [starter-dir]
#   [starter-dir] defaults to the plugin's bundled starter/ (../starter relative
#   to this script). Override it in tests or to seed from custom content.
set -uo pipefail

path="${1:?usage: seed-local-repo.sh <bare-path> [starter-dir]}"
starter="${2:-}"
if [ -z "$starter" ]; then
  starter="$(CDPATH= cd -- "$(dirname -- "$0")/../starter" && pwd)"
fi

for sub in main template; do
  if [ ! -d "$starter/$sub" ]; then
    echo "bundled starter content missing: $starter/$sub" >&2
    exit 1
  fi
done

if [ ! -d "$path" ]; then
  git init --bare -b main "$path" >/dev/null
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Build each branch in its own throwaway work tree, then push it into the bare
# repo. Keeping the branches independent gives each a clean one-commit history.
seed_branch() { # <branch> <content-dir>
  local branch="$1" src="$2"
  local work="$tmp/$branch"
  git init -q -b "$branch" "$work" || return 1
  cp -R "$src/." "$work/" || return 1
  (
    cd "$work" || exit 1
    git config user.email "claude-profiles@localhost"
    git config user.name "claude-profiles"
    git add -A &&
    git commit -q -m "Seed $branch from bundled starter" &&
    git push -q "$path" "$branch:$branch"
  )
}

seed_branch main "$starter/main" \
  || { echo "failed to seed 'main' into $path (does it already have that branch?)" >&2; exit 1; }
seed_branch template "$starter/template" \
  || { echo "failed to seed 'template' into $path (does it already have that branch?)" >&2; exit 1; }

echo "seeded $path with: main, template (from bundled starter)"
