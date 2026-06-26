#!/usr/bin/env bash
# Inspect the claude-profiles config and report whether the configured repo is
# reachable. Used by /claude-profiles:init to short-circuit if already set up.
#
# Usage: check-config.sh
# Output (key=value):
#   state=missing|no_repo|unreachable|ok
#   repo=<url>           (when present)
#   summary=<one-line>
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

emit() { printf '%s=%s\n' "$1" "$2"; }

pcfg_migrate
file="$(pcfg_file)"

if [ ! -f "$file" ]; then
  emit state missing
  emit summary "$file does not exist."
  exit 0
fi
repo=$(pcfg_default_repo)
if [ -z "$repo" ]; then
  emit state no_repo
  emit summary "$file has no profiles source configured."
  exit 0
fi
safe_repo=$(pcfg_redact_repo "$repo")
emit repo "$safe_repo"
if pcfg_validate_repo "$repo" >/dev/null 2>&1 && git ls-remote --heads "$repo" >/dev/null 2>&1; then
  emit state ok
  emit summary "Profiles repo configured and reachable: $safe_repo"
else
  emit state unreachable
  emit summary "Configured repo is unreachable: $safe_repo"
fi
