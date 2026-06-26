#!/usr/bin/env bash
# List profile branches across the configured profile sources. Excludes 'template'.
#
# Usage:
#   list-branches.sh               names only, all sources, deduped + sorted
#   list-branches.sh <source>      names only, just that source
#   list-branches.sh --by-source   "<source>\t<branch>\t<description>" lines
#
# Exits non-zero if no profiles repo is configured.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

# Remote branch names for one source (empty if its repo is unset/unreachable).
_branches_of() { # <source>
  local r; r=$(pcfg_source_repo "$1")
  [ -n "$r" ] || return 0
  pcfg_validate_repo "$r" >/dev/null 2>&1 || return 0
  git ls-remote --heads "$r" 2>/dev/null \
    | awk '{ sub("refs/heads/", "", $2); print $2 }' \
    | grep -v '^template$'
}

mode="${1:-}"
case "$mode" in
  --by-source)
    [ -n "$(pcfg_sources)" ] || { echo "no profiles repo configured — run /claude-profiles:init" >&2; exit 1; }
    pcfg_sources | while IFS= read -r s; do
      _branches_of "$s" | sort | while IFS= read -r b; do
        printf '%s\t%s\t%s\n' "$s" "$b" "$(pcfg_description "$b" "$s")"
      done
    done
    ;;
  "")
    [ -n "$(pcfg_sources)" ] || { echo "no profiles repo configured — run /claude-profiles:init" >&2; exit 1; }
    pcfg_sources | while IFS= read -r s; do _branches_of "$s"; done | sort -u
    ;;
  *)
    pcfg_source_repo "$mode" >/dev/null
    [ -n "$(pcfg_source_repo "$mode")" ] || { echo "no such source: $mode" >&2; exit 1; }
    _branches_of "$mode" | sort
    ;;
esac
