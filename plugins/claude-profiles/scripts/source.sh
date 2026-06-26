#!/usr/bin/env bash
# Manage profile sources in the claude-profiles config (issue #1).
#
# Usage:
#   source.sh list                          list sources (default marked with *)
#   source.sh add <name> <repo> [--default] add/update a source (validates repo)
#   source.sh remove <name>                 remove a source
#   source.sh default <name>                set the default source
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=_lib.sh
. "$here/_lib.sh"

cmd="${1:-list}"
shift || true

case "$cmd" in
  list)
    sources=$(pcfg_sources)
    [ -n "$sources" ] || { echo "no sources configured — run /claude-profiles:init" >&2; exit 1; }
    def=$(pcfg_default_source_name)
    printf '%s\n' "$sources" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      mark=" "; [ "$n" = "$def" ] && mark="*"
      printf '%s %s\t%s\n' "$mark" "$n" "$(pcfg_redact_repo "$(pcfg_source_repo "$n")")"
    done
    ;;
  add)
    name="${1:?usage: source.sh add <name> <repo> [--default]}"
    repo="${2:?usage: source.sh add <name> <repo> [--default]}"
    case "$name" in
      *[!A-Za-z0-9._-]*|"") echo "invalid source name: $name (use letters, digits, . _ -)" >&2; exit 2 ;;
    esac
    makedef=""
    [ "${3:-}" = "--default" ] && makedef=default
    pcfg_validate_repo "$repo" || exit 1
    safe_repo=$(pcfg_redact_repo "$repo")
    if ! git ls-remote --heads "$repo" >/dev/null 2>&1; then
      echo "repo unreachable: $safe_repo" >&2
      exit 1
    fi
    pcfg_add_source "$name" "$repo" "$makedef"
    bash "$here/refresh-branches-cache.sh" "$name" >/dev/null 2>&1 || true
    echo "added source '$name' -> $safe_repo${makedef:+ (default)}"
    ;;
  remove|rm)
    name="${1:?usage: source.sh remove <name>}"
    [ -n "$(pcfg_source_repo "$name")" ] || { echo "no such source: $name" >&2; exit 1; }
    pcfg_remove_source "$name"
    echo "removed source '$name'"
    ;;
  default)
    name="${1:?usage: source.sh default <name>}"
    [ -n "$(pcfg_source_repo "$name")" ] || { echo "no such source: $name" >&2; exit 1; }
    pcfg_set_default_source "$name"
    echo "default source -> $name"
    ;;
  *)
    echo "unknown subcommand: $cmd (use list|add|remove|default)" >&2
    exit 2
    ;;
esac
