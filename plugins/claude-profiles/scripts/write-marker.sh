#!/usr/bin/env bash
# Write the .claude-profiles marker file (JSON) at the workspace root.
# Usage: write-marker.sh <profile> [workspace-dir]
#   <profile> may be 'none' to record opt-out (omits repo/source).
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

profile="${1:?usage: write-marker.sh <profile> [workspace-dir]}"
workspace="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"

repo=""
source=""
if [ "$profile" != "none" ]; then
  source=$(pcfg_active_source)
  repo=$(pcfg_source_repo "$source")
fi

write_marker_json "$workspace" "$profile" "$repo" "$source"
echo "wrote $(marker_path "$workspace")"
