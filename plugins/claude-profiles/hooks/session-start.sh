#!/usr/bin/env bash
# SessionStart hook: report the workspace's .claude profile sync status, plus
# detect new branches on the profiles repo since last session.
# No `-e`: any individual command failure should be tolerated rather than
# aborting the session start.
set -uo pipefail

here="$(dirname "$0")"
# shellcheck source=../scripts/_lib.sh
. "$here/../scripts/_lib.sh"

workspace="${CLAUDE_PROJECT_DIR:-$PWD}"
dir="$workspace/.claude"
marker="$workspace/.claude-profiles"
config="$HOME/.claude-profiles-config"

# Don't nag inside the global ~/.claude. Also skip a checkout of this plugin's
# own source repo *only* when the user hasn't classified it yet — once they've
# adopted it into a profile (marker present) we want normal sync reporting.
[ "$workspace" = "$HOME/.claude" ] && exit 0
if [ ! -f "$marker" ] && [ -f "$workspace/.claude-plugin/marketplace.json" ] && \
   grep -q '"name"[[:space:]]*:[[:space:]]*"claude-profiles"' "$workspace/.claude-plugin/marketplace.json" 2>/dev/null; then
  exit 0
fi

emit() { # $1 = user-visible message, $2 = context for Claude
  local msg="$1" ctx="$2"
  if [ -n "${NEW_BRANCHES:-}" ]; then
    msg="$msg (New profile branches available: $NEW_BRANCHES)"
    ctx="$ctx [claude-profiles] New profile branches detected on \$CLAUDE_PROFILES_REPO since the last session: $NEW_BRANCHES. Mention these to the user as options for /claude-profiles:set."
  fi
  hook_emit_json SessionStart "$msg" "$ctx"
}

profiles_repo=""
known_branches=""
if [ -f "$config" ]; then
  profiles_repo=$(sed -n 's/^repo=//p' "$config" | head -n1)
  known_branches=$(sed -n 's/^branches=//p' "$config" | head -n1)
fi
profile=$(read_marker_profile "$workspace")

# Detect new branches on the profiles repo (vs cached list). Cheap rate limit:
# once per day per machine.
NEW_BRANCHES=""
check_new_branches() {
  [ -n "$profiles_repo" ] || return 0
  local stamp="$HOME/.claude-profiles-branches-stamp"
  if [ -n "$(find "$stamp" -mtime -1 2>/dev/null)" ]; then
    return 0
  fi
  local remote
  remote=$(bash "$here/../scripts/list-branches.sh" 2>/dev/null | paste -sd, -)
  touch "$stamp"
  [ -n "$remote" ] || return 0
  if [ -z "$known_branches" ]; then
    # First run: just record what's there, don't nag.
    if grep -q '^branches=' "$config" 2>/dev/null; then
      sed -i.bak "s|^branches=.*|branches=$remote|" "$config" && rm -f "$config.bak"
    else
      printf 'branches=%s\n' "$remote" >> "$config"
    fi
    return 0
  fi
  local new
  new=$(comm -23 <(printf '%s\n' "$remote" | tr ',' '\n' | sort -u) \
                 <(printf '%s\n' "$known_branches" | tr ',' '\n' | sort -u) \
        | paste -sd, -)
  [ -n "$new" ] && NEW_BRANCHES="$new"
  if grep -q '^branches=' "$config" 2>/dev/null; then
    sed -i.bak "s|^branches=.*|branches=$remote|" "$config" && rm -f "$config.bak"
  else
    printf 'branches=%s\n' "$remote" >> "$config"
  fi
}
check_new_branches

# 1) No marker — workspace hasn't been classified yet.
if [ -z "$profile" ]; then
  if [ -z "$profiles_repo" ]; then
    emit "No Claude profiles repo configured — run /claude-profiles:init to set one up. Profiles let you keep a different ~/.claude per workspace, backed by branches in a single git repo." \
         "[claude-profiles] ~/.claude-profiles-config is missing or has no repo= line. The user has not yet configured a profiles repo. Profiles are per-workspace .claude folders backed by branches of a single git repo (one branch per scenario: rust-cli, web-dev, etc.). Run /claude-profiles:init to configure one before adopting any workspace into a profile."
    exit 0
  fi
  if [ -d "$dir" ]; then
    emit "This workspace has a .claude folder but no profile marker — run /claude-profiles:set to adopt it as a new profile or pick an existing one." \
         "[claude-profiles] This workspace has a .claude folder but no .claude-profiles marker. Profiles are per-workspace .claude folders, each tracked as a branch of the user's profiles repo (\$CLAUDE_PROFILES_REPO). Ask the user whether to (a) adopt the existing .claude as a new profile branch (push it and write the marker), (b) replace it with an existing profile branch via /claude-profiles:set <branch>, or (c) opt out via /claude-profiles:set --none."
  else
    emit "No Claude profile in this workspace — run /claude-profiles:set to set one up (or dismiss permanently)." \
         "[claude-profiles] This workspace has no .claude-profiles marker and no .claude folder. Profiles are per-workspace .claude folders backed by branches of the user's profiles repo (one branch per scenario). Ask the user if they want to run /claude-profiles:set to (a) clone an existing profile branch, (b) start a new branch from template, or (c) opt out via --none."
  fi
  exit 0
fi

# 2) Opted out — silent (only nag about new branches if any).
if [ "$profile" = "none" ]; then
  [ -n "$NEW_BRANCHES" ] && emit "" ""
  exit 0
fi

# 3) Profile configured: get its sync state from the shared status script.
status_kv=$(bash "$here/../scripts/profile-status.sh" "$workspace" 2>/dev/null || true)
state=$(kv_get "$status_kv" state)
action=$(kv_get "$status_kv" action)
behind=$(kv_get "$status_kv" behind)

case "$state" in
  missing)
    emit "Workspace marker says profile=$profile but .claude folder is missing — run /claude-profiles:set $profile to restore it." \
         "[claude-profiles] The .claude-profiles marker says profile=$profile but the .claude folder doesn't exist. Ask the user if they want to clone it back via /claude-profiles:set $profile."
    ;;
  not_git)
    emit "Workspace marker says profile=$profile but .claude isn't a git clone — fix manually or rerun /claude-profiles:set $profile." \
         "[claude-profiles] The .claude-profiles marker says profile=$profile but .claude is not a git repo. Ask the user how to proceed (manual fix, or remove .claude and rerun /claude-profiles:set $profile)."
    ;;
  ok)
    case "$action" in
      commit)
        emit "This workspace's .claude profile has uncommitted changes — consider committing and pushing them." \
             "[claude-profiles] The .claude profile in this workspace has uncommitted changes. Ask the user if they want to commit and push them to the claude-profiles repo."
        ;;
      push)
        emit "This workspace's .claude profile has unpushed commits — consider pushing them." \
             "[claude-profiles] The .claude profile in this workspace has unpushed commits. Ask the user if they want to push them."
        ;;
      pull|rebase)
        emit "This workspace's .claude profile is ${behind:-some} commit(s) behind — run /claude-profiles:update to pull." \
             "[claude-profiles] The .claude profile in this workspace is behind its remote branch. A newer version of this profile is available. Suggest the user run /claude-profiles:update to pull the latest changes."
        ;;
      clean)
        # In sync; only emit if there are new branches to advertise.
        [ -n "$NEW_BRANCHES" ] && emit "" ""
        ;;
    esac
    ;;
esac
exit 0
