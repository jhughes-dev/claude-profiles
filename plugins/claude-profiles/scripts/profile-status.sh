#!/usr/bin/env bash
# Report this workspace's .claude profile sync status as key=value lines.
# Usage: profile-status.sh [workspace-dir]
#
# Output keys (always present, in this order):
#   state=missing|opted_out|not_git|ok
#   branch=<branch-name>            (only if state=ok)
#   dirty=0|1                        (only if state=ok)
#   ahead=<n>                        (only if state=ok)
#   behind=<n>                       (only if state=ok)
#   action=clean|commit|push|pull|rebase|opt_out_cleanup|init
#   summary=<one-line human summary>
#
# Always exits 0 on success — consumers should switch on `state`/`action`.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

workspace="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"

emit_kv() { printf '%s=%s\n' "$1" "$2"; }

if [ ! -d "$dir" ]; then
  emit_kv state missing
  emit_kv action init
  emit_kv summary "No .claude folder — run /claude-profiles:set to configure one."
  exit 0
fi

if [ ! -d "$dir/.git" ]; then
  emit_kv state not_git
  emit_kv action opt_out_cleanup
  emit_kv summary "This workspace opted out (.claude exists but isn't a profile clone)."
  exit 0
fi

# Refresh remote tracking. Hot-path callers (the SessionStart/ConfigChange
# hooks) set CLAUDE_PROFILES_FETCH=daily to rate-limit this network call to once
# per day via the stamp; interactive callers (status/update) leave it unset for
# an immediate fetch. Skip if the clone's origin URL is unsafe (RCE guard).
stamp="$dir/.git/profile-fetch-stamp"
origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
if [ -n "$origin" ] && pcfg_validate_repo "$origin" >/dev/null 2>&1; then
  if [ "${CLAUDE_PROFILES_FETCH:-}" != "daily" ] || [ -z "$(find "$stamp" -mtime -1 2>/dev/null)" ]; then
    git -C "$dir" fetch -q 2>/dev/null || true
    touch "$stamp" 2>/dev/null || true
  fi
fi

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
dirty=0
[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty=1

# `rev-list --left-right --count @{u}...HEAD` prints "<behind>\t<ahead>".
counts=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || printf '0\t0')
behind=$(printf '%s' "$counts" | awk '{print $1+0}')
ahead=$(printf '%s' "$counts" | awk '{print $2+0}')

emit_kv state ok
emit_kv branch "$branch"
emit_kv dirty "$dirty"
emit_kv ahead "$ahead"
emit_kv behind "$behind"

if [ "$dirty" = "1" ]; then
  emit_kv action commit
  emit_kv summary "Uncommitted changes on '$branch'."
elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
  emit_kv action rebase
  emit_kv summary "Diverged: $ahead ahead, $behind behind on '$branch'."
elif [ "$ahead" -gt 0 ]; then
  emit_kv action push
  emit_kv summary "$ahead unpushed commit(s) on '$branch'."
elif [ "$behind" -gt 0 ]; then
  emit_kv action pull
  emit_kv summary "$behind commit(s) behind on '$branch'."
else
  emit_kv action clean
  emit_kv summary "Profile '$branch' is up to date."
fi
exit 0
