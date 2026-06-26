#!/usr/bin/env bash
# Set the current profile's self-description (issue #3): write the
# .claude/.profile-description file and cache it in the config. Commit/push is
# left to the caller (the describe skill offers it).
#
# Usage: write-profile-description.sh <text> [workspace-dir] [branch] [source]
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

text="${1:?usage: write-profile-description.sh <text> [workspace] [branch] [source]}"
workspace="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
dir="$workspace/.claude"
[ -d "$dir" ] || { echo "no profile .claude at $dir — run /claude-profiles:set first" >&2; exit 1; }

branch="${3:-$(git -C "$dir" branch --show-current 2>/dev/null)}"
source="${4:-$(pcfg_active_source)}"

# A description is a one-liner. The config dump is TAB/line-delimited, so collapse
# any TAB/CR/LF to spaces (and trim) before storing — otherwise they corrupt it.
clean=$(printf '%s' "$text" | tr '\t\r\n' '   ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
printf '%s\n' "$clean" > "$dir/.profile-description"
[ -n "$branch" ] && pcfg_set_description "$branch" "$clean" "$source"
echo "wrote $dir/.profile-description"
