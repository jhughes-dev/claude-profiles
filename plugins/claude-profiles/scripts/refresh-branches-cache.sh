#!/usr/bin/env bash
# Refresh the cached profile list for every source so the SessionStart hook
# doesn't flag a just-created branch as "new" on the next session.
# Usage: refresh-branches-cache.sh [source]   (all sources if omitted)
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

refresh_one() { # <source>
  local s="$1" branches
  branches=$(bash "$here/list-branches.sh" "$s" 2>/dev/null | paste -sd, -)
  [ -n "$branches" ] || return 0
  pcfg_set_branches_csv "$branches" "$s"
  echo "refreshed $s: $branches"
}

if [ -n "${1:-}" ]; then
  refresh_one "$1"
else
  pcfg_sources | while IFS= read -r s; do refresh_one "$s"; done
fi
