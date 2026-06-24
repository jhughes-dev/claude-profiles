#!/usr/bin/env bash
# Enumerate promotable components in user space (~/.claude) for the configure
# skill. Output is tab-separated, one component per line:
#   skill<TAB><name>
#   agent<TAB><name>
#   command<TAB><name>
#   hook<TAB><file>
#   plugin<TAB><name@marketplace><TAB><true|false>
#   claudemd<TAB>present
#   setting<TAB><key>
# Usage: list-user-components.sh [user-claude-dir]   (default ~/.claude)
set -uo pipefail

user="${1:-$HOME/.claude}"

# Skills and agents are subdirectories (each one component); skip README.
for type in skill agent; do
  d="$user/${type}s"
  [ -d "$d" ] || continue
  for entry in "$d"/*/; do
    [ -d "$entry" ] || continue
    printf '%s\t%s\n' "$type" "$(basename "$entry")"
  done
done

# Commands are *.md files (skip README.md).
if [ -d "$user/commands" ]; then
  for f in "$user/commands"/*.md; do
    [ -f "$f" ] || continue
    b=$(basename "$f"); [ "$b" = README.md ] && continue
    printf 'command\t%s\n' "${b%.md}"
  done
fi

# Hooks are *.sh files.
if [ -d "$user/hooks" ]; then
  for f in "$user/hooks"/*.sh; do
    [ -f "$f" ] || continue
    printf 'hook\t%s\n' "$(basename "$f")"
  done
fi

# Plugins: keys of enabledPlugins in settings.json, with their on/off value.
s="$user/settings.json"
if [ -f "$s" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.enabledPlugins // {}) | to_entries[] | "plugin\t" + .key + "\t" + (.value | tostring)' "$s" 2>/dev/null
  else
    # No-jq: plugin keys look like "name@marketplace": true|false.
    grep -oE '"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*(true|false)' "$s" | while IFS= read -r line; do
      key=$(printf '%s' "$line" | sed -E 's/^"([^"]+)".*/\1/')
      val=$(printf '%s' "$line" | grep -oE '(true|false)$')
      printf 'plugin\t%s\t%s\n' "$key" "$val"
    done
  fi
  # A handful of commonly-promoted scalar settings, when present.
  for key in model effortLevel statusLine env; do
    grep -qE "\"$key\"[[:space:]]*:" "$s" && printf 'setting\t%s\n' "$key"
  done
fi

[ -f "$user/CLAUDE.md" ] && printf 'claudemd\tpresent\n'
