#!/usr/bin/env bash
# Set the default source's repo in the JSON config (creating it if needed).
# Usage: write-config.sh <repo-url-or-path>
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

repo="${1:?usage: write-config.sh <repo-url>}"
pcfg_set_repo "$repo" || exit 1
echo "wrote repo=$(pcfg_redact_repo "$repo") to $(pcfg_file)"
