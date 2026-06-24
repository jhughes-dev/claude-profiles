#!/usr/bin/env bash
# Shared helpers for claude-profiles hooks. `source` this file; do not run it.

# Print a hook JSON payload to stdout.
# Usage: hook_emit_json <hook-event-name> <systemMessage> <additionalContext>
# Uses jq when available; otherwise emits hand-escaped JSON.
hook_emit_json() {
  local event="$1" msg="$2" ctx="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ev "$event" --arg msg "$msg" --arg ctx "$ctx" \
      '{systemMessage: $msg, hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
  else
    local m c
    m=$(printf '%s' "$msg" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    c=$(printf '%s' "$ctx" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "%s", "additionalContext": "%s"}}\n' \
      "$m" "$event" "$c"
  fi
}

# Read a key from key=value lines on stdin.
# Usage: kv=$(some-script ...); val=$(kv_get "$kv" branch)
kv_get() {
  local input="$1" key="$2"
  printf '%s\n' "$input" | sed -n "s/^${key}=//p" | head -n1
}

# Read profile= from a workspace's .claude-profiles marker.
read_marker_profile() {
  local workspace="$1"
  local marker="$workspace/.claude-profiles"
  [ -f "$marker" ] || return 0
  sed -n 's/^profile=//p' "$marker" | head -n1
}
