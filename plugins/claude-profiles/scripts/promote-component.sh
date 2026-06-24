#!/usr/bin/env bash
# Promote a user-space component into the current workspace's profile (.claude).
# Copies (or moves) a skill/agent/command/hook from ~/.claude into .claude.
#
# Usage: promote-component.sh <type> <name> <copy|move> [workspace-dir]
#   <type> = skill | agent | command | hook
#
# Plugins are NOT handled here — they are enabled per-profile in the profile's
# settings.json (see the maintain-profile skill), not copied as files.
set -uo pipefail

type="${1:?usage: promote-component.sh <type> <name> <copy|move> [workspace]}"
name="${2:?usage: promote-component.sh <type> <name> <copy|move> [workspace]}"
mode="${3:?usage: promote-component.sh <type> <name> <copy|move> [workspace]}"
workspace="${4:-${CLAUDE_PROJECT_DIR:-$PWD}}"

user="$HOME/.claude"
dest="$workspace/.claude"
[ -d "$dest" ] || { echo "no profile .claude at $dest — run /claude-profiles:set first" >&2; exit 1; }

case "$type" in
  skill|agent) src="$user/${type}s/$name"; dst="$dest/${type}s/$name" ;;
  command)     src="$user/commands/$name.md"; dst="$dest/commands/$name.md" ;;
  hook)        src="$user/hooks/$name"; dst="$dest/hooks/$name" ;;
  *) echo "unknown type: $type (use skill|agent|command|hook)" >&2; exit 2 ;;
esac
case "$mode" in copy|move) ;; *) echo "mode must be copy or move" >&2; exit 2 ;; esac

[ -e "$src" ] || { echo "not found in user space: $src" >&2; exit 1; }
mkdir -p "$(dirname "$dst")"
cp -R "$src" "$dst"
[ "$mode" = move ] && rm -rf "$src"
echo "${mode}d $type '$name' -> $dst"
