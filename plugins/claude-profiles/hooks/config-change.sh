#!/usr/bin/env bash
# ConfigChange hook:
#  - On any profile-affecting change, nudge to commit/push the profile branch.
#  - On user_settings changes, detect newly-enabled global plugins and ask
#    whether they should also be enabled in the workspace's profile branch.
# Never blocks.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=../scripts/_lib.sh
. "$here/../scripts/_lib.sh"

workspace="${CLAUDE_PROJECT_DIR:-$PWD}"
dir="$workspace/.claude"

[ "$workspace" = "$HOME/.claude" ] && exit 0
profile=$(read_marker_profile "$workspace")
[ -n "$profile" ] && [ "$profile" != "none" ] || exit 0
[ -d "$dir/.git" ] || exit 0

# Read hook input (best-effort) to learn the source.
input=""
[ -t 0 ] || input=$(cat 2>/dev/null || true)
source_field=""
if [ -n "$input" ]; then
  if command -v jq >/dev/null 2>&1; then
    source_field=$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)
  else
    source_field=$(printf '%s' "$input" | tr -d '\n' \
      | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi
fi

# Extract names of plugins set to true in an enabledPlugins map without jq.
extract_enabled_plugins() {
  local file="$1"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.enabledPlugins // {} | to_entries | map(select(.value == true)) | map(.key) | .[]' "$file" 2>/dev/null
    return
  fi
  tr -d '\n' < "$file" \
    | sed -n 's/.*"enabledPlugins"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' \
    | grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*true' \
    | sed -E 's/^"([^"]+)".*/\1/'
}

# --- New global plugin detection (user_settings only) ---
new_plugins=""
if [ "$source_field" = "user_settings" ]; then
  global_settings="$HOME/.claude/settings.json"
  cache="$HOME/.claude-profiles-enabled-plugins-cache"
  if [ -f "$global_settings" ]; then
    current=$(extract_enabled_plugins "$global_settings" | sort -u)
    if [ -f "$cache" ]; then
      previous=$(sort -u "$cache")
      added=$(comm -23 <(printf '%s\n' "$current") <(printf '%s\n' "$previous"))
      if [ -n "$added" ]; then
        profile_enabled=$(extract_enabled_plugins "$dir/settings.json" | sort -u)
        new_plugins=$(comm -23 <(printf '%s\n' "$added" | sort -u) <(printf '%s\n' "$profile_enabled") | paste -sd, -)
      fi
    fi
    printf '%s\n' "$current" > "$cache"
  fi
fi

# --- Profile sync state via the shared status script ---
status_kv=$(bash "$here/../scripts/profile-status.sh" "$workspace" 2>/dev/null || true)
action=$(kv_get "$status_kv" action)

msg_parts=""
ctx_parts=""
append() {
  if [ -z "$msg_parts" ]; then msg_parts="$1"; else msg_parts="$msg_parts | $1"; fi
  if [ -z "$ctx_parts" ]; then ctx_parts="$2"; else ctx_parts="$ctx_parts $2"; fi
}

if [ -n "$new_plugins" ]; then
  append "New global plugin(s) enabled: $new_plugins — also enable in profile '$profile'?" \
         "[claude-profiles] The user just enabled these plugins globally in ~/.claude/settings.json: $new_plugins. They are NOT yet enabled in the workspace profile '$profile' (.claude/settings.json). Ask the user whether each new plugin belongs in this profile (so it'll be enabled automatically in any other workspace using this profile), or if it's intentionally global-only. If yes, add the entry to .claude/settings.json's enabledPlugins map and commit."
fi

case "$action" in
  commit)
    append "Profile '$profile' has uncommitted changes — consider committing and pushing." \
           "[claude-profiles] The profile branch '$profile' has uncommitted changes in .claude. Recommend the user commit and push so other workspaces on this profile pick them up."
    ;;
  push)
    append "Profile '$profile' has unpushed commits — consider pushing them." \
           "[claude-profiles] The profile branch '$profile' has commits that haven't been pushed. Recommend the user push them."
    ;;
esac

[ -n "$msg_parts" ] && hook_emit_json ConfigChange "$msg_parts" "$ctx_parts"
exit 0
