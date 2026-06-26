#!/usr/bin/env bash
# Cache a profile's self-description into the config (issue #3).
# Reads <workspace>/.claude/.profile-description (a short, one-line summary the
# branch carries about itself) and stores it for <branch> under its source.
#
# Usage: cache-description.sh <branch> [workspace-dir] [source]
# No-op (exit 0) if the profile has no description file.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

branch="${1:?usage: cache-description.sh <branch> [workspace] [source]}"
workspace="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
source="${3:-$(pcfg_active_source)}"

f="$workspace/.claude/.profile-description"
[ -f "$f" ] || exit 0

# First non-empty line, trimmed.
desc=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | grep -m1 . || true)
[ -n "$desc" ] || exit 0

pcfg_set_description "$branch" "$desc" "$source"
echo "cached description for '$branch': $desc"
