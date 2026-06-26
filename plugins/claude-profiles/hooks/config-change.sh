#!/usr/bin/env bash
# ConfigChange hook (issue #9):
#  - Detect anything newly added to the user's GLOBAL ~/.claude (enabled plugins,
#    skills, agents, commands, hooks) since the session-start baseline, and ask
#    whether it should move into this workspace's profile, go into local settings,
#    or stay global on purpose. Works whether or not the workspace has a profile.
#  - If the workspace has a profile, also nudge to commit/push pending changes.
# Never blocks.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=../scripts/_lib.sh
. "$here/../scripts/_lib.sh"

workspace="${CLAUDE_PROJECT_DIR:-$PWD}"
dir="$workspace/.claude"

# Don't nag about the global config dir itself.
[ "$workspace" = "$HOME/.claude" ] && exit 0

profile=$(read_marker_profile "$workspace")
has_profile=0
[ -n "$profile" ] && [ "$profile" != "none" ] && [ -d "$dir/.git" ] && has_profile=1

# --- Detect additions to global ~/.claude vs the baseline -------------------
# The baseline is seeded at SessionStart and refreshed after each event, so we
# notice changes made during the session. list-user-components enumerates the
# global config (enabled plugins, skills, agents, commands, hooks, ...).
cache="$HOME/.claude-profiles-global-cache"
current=$(bash "$here/../scripts/list-user-components.sh" 2>/dev/null | sort -u)
added=""
[ -f "$cache" ] && added=$(comm -23 <(printf '%s\n' "$current") <(sort -u "$cache") 2>/dev/null || true)
printf '%s\n' "$current" > "$cache"

# Keep only meaningful additions: newly-enabled plugins and new components.
added_list=$(printf '%s\n' "$added" | awk -F'\t' '
  $1 == "plugin" && $3 == "true" { print "plugin " $2; next }
  $1 == "skill" || $1 == "agent" || $1 == "command" || $1 == "hook" { print $1 " " $2 }
')

msg_parts=""
ctx_parts=""
append() {
  if [ -z "$msg_parts" ]; then msg_parts="$1"; else msg_parts="$msg_parts | $1"; fi
  if [ -z "$ctx_parts" ]; then ctx_parts="$2"; else ctx_parts="$ctx_parts $2"; fi
}

if [ -n "$added_list" ]; then
  items=$(printf '%s' "$added_list" | paste -sd'; ' -)
  if [ "$has_profile" = 1 ]; then
    append "Added to your global ~/.claude: $items — keep global, move into profile '$profile', or local settings?" \
           "[claude-profiles] New config was added to the user's GLOBAL ~/.claude: $items. Ask the user, per item, whether it should (a) move into this workspace's profile '$profile' — for a plugin that means enabling it in .claude/settings.json's enabledPlugins; for a skill/agent/command/hook, copying it into .claude/<type>/ (the /claude-profiles:configure skill does this) — (b) go into local-only settings (.claude/settings.local.json), or (c) stay global on purpose. Apply the choice and, for profile changes, offer to commit + push."
  else
    append "Added to your global ~/.claude: $items — this workspace has no profile; keep global, set one up, or use local settings?" \
           "[claude-profiles] New config was added to the user's GLOBAL ~/.claude: $items. This workspace has no claude-profiles profile. Ask the user whether to (a) keep it global, (b) set up/adopt a profile for this workspace with /claude-profiles:set and put it there, or (c) put it in local-only settings (.claude/settings.local.json)."
  fi
fi

# --- Profile sync nudge (only when a profile is active) ---------------------
if [ "$has_profile" = 1 ]; then
  status_kv=$(bash "$here/../scripts/profile-status.sh" "$workspace" 2>/dev/null || true)
  case "$(kv_get "$status_kv" action)" in
    commit)
      append "Profile '$profile' has uncommitted changes — consider committing and pushing." \
             "[claude-profiles] The profile branch '$profile' has uncommitted changes in .claude. Recommend the user commit and push so other workspaces on this profile pick them up."
      ;;
    push)
      append "Profile '$profile' has unpushed commits — consider pushing them." \
             "[claude-profiles] The profile branch '$profile' has commits that haven't been pushed. Recommend the user push them."
      ;;
  esac
fi

[ -n "$msg_parts" ] && hook_emit_json ConfigChange "$msg_parts" "$ctx_parts"
exit 0
