#!/usr/bin/env bash
# Update this workspace's .claude profile against its remote.
# Handles the deterministic cases automatically; bails out to the caller
# (with action=needs_*) when human judgement is required.
#
# Usage: profile-update.sh [workspace-dir]
#
# Output: same key=value shape as profile-status.sh, plus possibly:
#   action=clean              — already in sync, nothing done
#   action=needs_commit       — dirty tree, refuses to pull on top
#   action=pushed             — was ahead, push succeeded
#   action=pulled             — was behind, fast-forward succeeded
#   action=rebased_pushed     — diverged, rebase + push succeeded
#   action=needs_resolve      — diverged, rebase hit conflicts
#   action=push_failed        — push attempt errored
#   action=pull_failed        — fast-forward errored
#   conflicts=<file>,<file>   — when action=needs_resolve
#
# Exits 0 on success, 1 on hard error (e.g. no .claude).
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

workspace="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"

emit() { printf '%s=%s\n' "$1" "$2"; }

if [ ! -d "$dir" ]; then
  emit state missing
  emit action init
  emit summary "No .claude folder — nothing to update."
  exit 1
fi
if [ ! -d "$dir/.git" ]; then
  emit state not_git
  emit action opt_out_cleanup
  emit summary "Workspace opted out — no profile to update."
  exit 1
fi

# Refuse to touch the remote if the clone's origin URL is unsafe (a
# transport-helper URL would execute commands on fetch/pull/push).
origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
if [ -n "$origin" ] && ! pcfg_validate_repo "$origin" >/dev/null 2>&1; then
  emit state ok
  emit branch "$(git -C "$dir" branch --show-current 2>/dev/null)"
  emit action push_failed
  emit summary "Refusing to sync: the profile's git origin URL looks unsafe. Fix .claude's remote."
  exit 1
fi

git -C "$dir" fetch -q 2>/dev/null || true
touch "$dir/.git/profile-fetch-stamp" 2>/dev/null || true

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
emit state ok
emit branch "$branch"

dirty=0
[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty=1
counts=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || printf '0\t0')
behind=$(printf '%s' "$counts" | awk '{print $1+0}')
ahead=$(printf '%s' "$counts" | awk '{print $2+0}')
emit dirty "$dirty"
emit ahead "$ahead"
emit behind "$behind"

if [ "$dirty" = "1" ]; then
  emit action needs_commit
  emit summary "Uncommitted changes on '$branch' — commit, stash, or discard before updating."
  exit 0
fi

if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
  emit action clean
  emit summary "Profile '$branch' already in sync."
  exit 0
fi

if [ "$ahead" -gt 0 ] && [ "$behind" = "0" ]; then
  if git -C "$dir" push 2>/dev/null; then
    emit action pushed
    emit summary "Pushed $ahead commit(s) on '$branch'."
  else
    emit action push_failed
    emit summary "Push failed on '$branch'. Investigate manually."
  fi
  exit 0
fi

if [ "$behind" -gt 0 ] && [ "$ahead" = "0" ]; then
  if git -C "$dir" pull --ff-only -q 2>/dev/null; then
    emit action pulled
    emit summary "Fast-forwarded $behind commit(s) on '$branch'."
  else
    emit action pull_failed
    emit summary "Fast-forward failed on '$branch'. Investigate manually."
  fi
  exit 0
fi

# Diverged: try a rebase.
if git -C "$dir" pull --rebase -q 2>/dev/null; then
  if git -C "$dir" push 2>/dev/null; then
    emit action rebased_pushed
    emit summary "Rebased onto remote and pushed '$branch'."
  else
    emit action push_failed
    emit summary "Rebase succeeded but push failed on '$branch'."
  fi
  exit 0
fi

# Rebase hit conflicts.
conflicts=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null | paste -sd, -)
emit action needs_resolve
emit conflicts "$conflicts"
emit summary "Rebase paused on conflicts: $conflicts"
exit 0
