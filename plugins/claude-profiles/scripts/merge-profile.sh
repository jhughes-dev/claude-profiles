#!/usr/bin/env bash
# Create a new profile branch by merging two or more existing profile branches.
# Clones <base-branch> into <workspace>/.claude as <new-branch>, then merges
# each <other-branch> into it.
#
# On a clean merge: pushes <new-branch> to the remote.
# On conflict: leaves the worktree on <new-branch> with conflict markers,
# prints the conflicting paths and a resolution checklist, and exits non-zero
# WITHOUT pushing. The caller (or user) resolves, commits, and pushes manually.
#
# Usage: merge-profile.sh <new-branch> <base-branch> <other-branches-csv> [workspace-dir]
# Refuses to overwrite an existing .claude — caller must remove it first.
set -uo pipefail

new_branch="${1:?usage: merge-profile.sh <new-branch> <base-branch> <other-branches-csv> [workspace-dir]}"
base_branch="${2:?missing <base-branch>}"
others_csv="${3:?missing <other-branches-csv>}"
workspace="${4:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"

config="$HOME/.claude-profiles-config"
repo=$(sed -n 's/^repo=//p' "$config" 2>/dev/null | head -n1)
if [ -z "$repo" ]; then
  echo "no repo= in $config — run /claude-profiles:init" >&2
  exit 1
fi

if [ -e "$dir" ]; then
  echo ".claude already exists at $dir — remove it first" >&2
  exit 1
fi

# Clone base, then ensure we have the other branches available locally.
git clone --branch "$base_branch" --origin origin "$repo" "$dir" || exit $?
git -C "$dir" checkout -b "$new_branch" || exit $?

# Split the CSV into an array of other branches.
IFS=',' read -r -a others <<< "$others_csv"

for other in "${others[@]}"; do
  [ -n "$other" ] || continue
  git -C "$dir" fetch origin "$other:refs/remotes/origin/$other" >/dev/null 2>&1 || {
    echo "failed to fetch branch '$other' from $repo" >&2
    exit 1
  }
  if ! git -C "$dir" merge --no-ff "origin/$other" -m "Merge $other into $new_branch"; then
    # Conflict: surface the offending files and a checklist, then bail.
    conflicts=$(git -C "$dir" diff --name-only --diff-filter=U)
    echo
    echo "Merge of '$other' into '$new_branch' has conflicts."
    echo "Conflicting files:"
    printf '  %s\n' $conflicts
    echo
    echo "Resolution hints:"
    echo "  - settings.json, plugins/installed_plugins.json,"
    echo "    plugins/known_marketplaces.json: union the entries by hand"
    echo "    (both sides usually want to be kept)."
    echo "  - CLAUDE.md: concatenate sections from both sides."
    echo "  - agents/, skills/, commands/, hooks/: 'git checkout --theirs' or"
    echo "    '--ours' per file is rare — usually keep both files."
    echo
    echo "After resolving:"
    echo "  cd .claude"
    echo "  git add <files>"
    echo "  git commit"
    echo "  git push -u origin $new_branch"
    exit 2
  fi
done

git -C "$dir" push -u origin "$new_branch" || {
  echo "Merged cleanly but failed to push '$new_branch'." >&2
  echo "Push manually with: git -C .claude push -u origin $new_branch" >&2
  exit 1
}
echo "Created and pushed branch '$new_branch' (base: $base_branch, merged: $others_csv)."
