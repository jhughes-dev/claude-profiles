#!/usr/bin/env bash
# One-shot profile setup (issue #4): clone (or create) a profile, ignore .claude/
# in the workspace repo, write the marker, and refresh the branch cache — the
# deterministic happy path that /claude-profiles:set used to orchestrate by hand.
# Honors CLAUDE_PROFILES_SOURCE for the source to operate on.
#
# Usage:
#   setup-profile.sh <branch> [workspace]                       use an existing profile branch
#   setup-profile.sh --new <branch> [--from <base>] [workspace] new branch from <base> (default: template)
#   setup-profile.sh --none [workspace]                         mark workspace as no-profile
#
# Refuses to overwrite an existing .claude (clone-profile enforces this).
# Output (key=value): state=ok|none  branch=<b>  gitignore=<state>  summary=<...>
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

mode=existing
branch=""
new=""
base=template
workspace=""

while [ $# -gt 0 ]; do
  case "$1" in
    --new)  mode=new; new="${2:?--new needs a branch}"; shift 2 ;;
    --from) base="${2:?--from needs a base}"; shift 2 ;;
    --none) mode=none; shift ;;
    -*)     echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ "$mode" = existing ] && [ -z "$branch" ]; then branch="$1"; else workspace="$1"; fi
      shift ;;
  esac
done
workspace="${workspace:-${CLAUDE_PROJECT_DIR:-$PWD}}"

emit() { printf '%s=%s\n' "$1" "$2"; }

if [ "$mode" = none ]; then
  bash "$here/write-marker.sh" none "$workspace" >/dev/null
  emit state none
  emit summary "Marked $workspace as no-profile."
  exit 0
fi

if [ "$mode" = new ]; then
  bash "$here/clone-profile.sh" "$base" "$new" "$workspace" || exit $?
  branch="$new"
else
  [ -n "$branch" ] || { echo "usage: setup-profile.sh <branch> | --new <branch> [--from <base>] | --none" >&2; exit 2; }
  bash "$here/clone-profile.sh" "$branch" "" "$workspace" || exit $?
fi

gi=$(bash "$here/ensure-gitignore.sh" "$workspace" | sed -n 's/^state=//p')
bash "$here/write-marker.sh" "$branch" "$workspace" >/dev/null
bash "$here/refresh-branches-cache.sh" >/dev/null 2>&1 || true

emit state ok
emit branch "$branch"
emit gitignore "${gi:-unknown}"
emit summary "Profile '$branch' is set up in $workspace/.claude."
