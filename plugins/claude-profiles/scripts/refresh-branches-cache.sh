#!/usr/bin/env bash
# Refresh the cached profile list in the config so the SessionStart hook doesn't
# flag a just-created branch as "new" on the next session.
# Usage: refresh-branches-cache.sh
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

repo=$(pcfg_default_repo)
[ -n "$repo" ] || exit 0

branches=$(git ls-remote --heads "$repo" 2>/dev/null \
  | awk '{sub("refs/heads/","",$2); print $2}' \
  | grep -v '^template$' \
  | sort | paste -sd, -)
[ -n "$branches" ] || exit 0

pcfg_set_branches_csv "$branches"
echo "refreshed branches cache: $branches"
