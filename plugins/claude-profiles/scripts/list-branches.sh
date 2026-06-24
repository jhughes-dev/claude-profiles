#!/usr/bin/env bash
# List profile branches on the configured profiles repo, one per line.
# Excludes 'template'. Reads the repo URL from the claude-profiles config.
# Usage: list-branches.sh
# Exits non-zero with an error message on stderr if no repo is configured
# or the remote is unreachable.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

repo=$(pcfg_default_repo)
if [ -z "$repo" ]; then
  echo "no profiles repo configured — run /claude-profiles:init" >&2
  exit 1
fi

git ls-remote --heads "$repo" 2>/dev/null \
  | awk '{sub("refs/heads/","",$2); print $2}' \
  | grep -v '^template$' \
  | sort
