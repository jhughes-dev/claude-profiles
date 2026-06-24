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

# ---------------------------------------------------------------------------
# JSON config + marker layer
#
# The plugin owns the format of its config files, so we read/write a fixed,
# valid JSON layout in pure bash (jq is used when present, but is NOT required).
# The writer keeps each profile object on a single line so the no-jq reader can
# parse it with line-oriented sed/grep. See schemas/*.schema.json.
#
# Back-compat: readers also accept the legacy pre-1.x `key=value` format, and a
# legacy global config is migrated to JSON on first access.
# ---------------------------------------------------------------------------

PCFG_SCHEMA_URL="https://github.com/jhughes-dev/claude-profiles/blob/main/plugins/claude-profiles/schemas/config.schema.json"
PCFG_MARKER_SCHEMA_URL="https://github.com/jhughes-dev/claude-profiles/blob/main/plugins/claude-profiles/schemas/marker.schema.json"

# Global config location (XDG, with ~/.config fallback).
pcfg_dir()  { printf '%s/claude-profiles' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
pcfg_file() { printf '%s/config.json' "$(pcfg_dir)"; }
pcfg_legacy_file() { printf '%s/.claude-profiles-config' "$HOME"; }

# Minimal JSON string escaping (backslash + double-quote).
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

# True if the file's first non-whitespace byte is '{' (i.e. JSON, not key=value).
_is_json_file() {
  [ -f "$1" ] || return 1
  local first
  first=$(awk '{ gsub(/^[ \t\r\n]+/, ""); if (length) { print substr($0,1,1); exit } }' "$1")
  [ "$first" = "{" ]
}

# Portable no-jq scanner: print the first "<key>": "<value>" string in a file,
# JSON-unescaped, respecting backslash escapes (so values may contain quotes).
_json_scan() { # <file> <key>
  awk -v key="$2" '
    function unescape(s,   r, i, c, n) {
      r = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
          i++; c = substr(s, i, 1)
          if (c == "n") r = r "\n"; else if (c == "t") r = r "\t"; else r = r c
        } else r = r c
      }
      return r
    }
    {
      pos = index($0, "\"" key "\"")
      if (pos == 0) next
      rest = substr($0, pos + length(key) + 2)
      cpos = index(rest, ":"); if (cpos == 0) next
      rest = substr(rest, cpos + 1)
      qpos = index(rest, "\""); if (qpos == 0) next
      rest = substr(rest, qpos + 1)
      out = ""; n = length(rest); esc = 0
      for (i = 1; i <= n; i++) {
        c = substr(rest, i, 1)
        if (esc) { out = out c; esc = 0; continue }
        if (c == "\\") { out = out c; esc = 1; continue }
        if (c == "\"") break
        out = out c
      }
      print unescape(out); exit
    }
  ' "$1"
}

# Read a top-level string value from a flat JSON object. Empty if absent.
json_get_string() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    _json_scan "$file" "$key"
  fi
}

# --- default-source accessors (single-source behavior; schema supports many) ---

_pcfg_read_repo() {
  local file; file="$(pcfg_file)"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.sources[0].repo) // empty' "$file" 2>/dev/null
  else
    _json_scan "$file" repo
  fi
}

_pcfg_read_name() {
  local file; file="$(pcfg_file)"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.sources[0].name) // empty' "$file" 2>/dev/null
  else
    _json_scan "$file" name
  fi
}

# Emit the default source's profiles as `branch<TAB>description` lines.
_pcfg_profiles_tsv() {
  local file; file="$(pcfg_file)"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.sources[0].profiles // [])[] | [.branch, (.description // "")] | @tsv' "$file" 2>/dev/null
    return
  fi
  # No-jq: one profile object per line; scan branch + description with escapes.
  awk '
    function unescape(s,   r, i, c, n) {
      r = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
          i++; c = substr(s, i, 1)
          if (c == "n") r = r "\n"; else if (c == "t") r = r "\t"; else r = r c
        } else r = r c
      }
      return r
    }
    function field(line, key,   pos, rest, cpos, qpos, out, n, i, c, esc) {
      pos = index(line, "\"" key "\"")
      if (pos == 0) return ""
      rest = substr(line, pos + length(key) + 2)
      cpos = index(rest, ":"); if (cpos == 0) return ""
      rest = substr(rest, cpos + 1)
      qpos = index(rest, "\""); if (qpos == 0) return ""
      rest = substr(rest, qpos + 1)
      out = ""; n = length(rest); esc = 0
      for (i = 1; i <= n; i++) {
        c = substr(rest, i, 1)
        if (esc) { out = out c; esc = 0; continue }
        if (c == "\\") { out = out c; esc = 1; continue }
        if (c == "\"") break
        out = out c
      }
      return unescape(out)
    }
    /"branch"[ \t]*:/ {
      b = field($0, "branch")
      if (b != "") print b "\t" field($0, "description")
    }
  ' "$file"
}

# Write the whole config: <repo> <source-name>, profiles as TSV on stdin.
_pcfg_write() {
  local repo="$1" name="${2:-default}" file dir tmp
  file="$(pcfg_file)"; dir="$(pcfg_dir)"
  mkdir -p "$dir"
  tmp="$file.tmp.$$"
  {
    printf '{\n'
    printf '  "$schema": "%s",\n' "$PCFG_SCHEMA_URL"
    printf '  "version": 1,\n'
    printf '  "sources": [\n'
    printf '    {\n'
    printf '      "name": "%s",\n' "$(json_escape "$name")"
    printf '      "repo": "%s",\n' "$(json_escape "$repo")"
    printf '      "default": true,\n'
    printf '      "profiles": ['
    local first=1 b d
    while IFS=$'\t' read -r b d; do
      [ -n "$b" ] || continue
      if [ "$first" = 1 ]; then first=0; printf '\n'; else printf ',\n'; fi
      printf '        { "branch": "%s", "description": "%s" }' \
        "$(json_escape "$b")" "$(json_escape "$d")"
    done
    if [ "$first" = 1 ]; then printf ']\n'; else printf '\n      ]\n'; fi
    printf '    }\n'
    printf '  ]\n'
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$file"
}

# Migrate a legacy ~/.claude-profiles-config (key=value) to JSON, once.
pcfg_migrate() {
  local new old; new="$(pcfg_file)"; old="$(pcfg_legacy_file)"
  [ -f "$new" ] && return 0
  [ -f "$old" ] || return 0
  local repo branches
  repo=$(sed -n 's/^repo=//p' "$old" | head -n1)
  branches=$(sed -n 's/^branches=//p' "$old" | head -n1)
  ( IFS=,; for b in $branches; do [ -n "$b" ] && printf '%s\t\n' "$b"; done ) \
    | _pcfg_write "$repo" "default"
  mv "$old" "$old.migrated-to-json" 2>/dev/null || true
}

# --- public config API ---

pcfg_default_repo() { pcfg_migrate; _pcfg_read_repo; }

pcfg_default_source_name() {
  pcfg_migrate
  local n; n=$(_pcfg_read_name); printf '%s' "${n:-default}"
}

pcfg_branches_csv() { pcfg_migrate; _pcfg_profiles_tsv | cut -f1 | paste -sd, -; }

pcfg_description() { # <branch>
  pcfg_migrate
  _pcfg_profiles_tsv | awk -F'\t' -v b="$1" '$1==b{print $2; exit}'
}

pcfg_set_repo() { # <url>  — preserves cached profiles
  pcfg_migrate
  local url="$1" name
  name=$(_pcfg_read_name); name="${name:-default}"
  _pcfg_profiles_tsv | _pcfg_write "$url" "$name"
}

pcfg_set_branches_csv() { # <csv>  — preserves existing descriptions by branch
  pcfg_migrate
  local csv="$1" repo name existing b d
  repo=$(_pcfg_read_repo); name=$(_pcfg_read_name); name="${name:-default}"
  existing=$(_pcfg_profiles_tsv)
  ( IFS=,
    for b in $csv; do
      [ -n "$b" ] || continue
      d=$(printf '%s\n' "$existing" | awk -F'\t' -v x="$b" '$1==x{print $2; exit}')
      printf '%s\t%s\n' "$b" "$d"
    done
  ) | _pcfg_write "$repo" "$name"
}

pcfg_set_description() { # <branch> <description>  (issue #3)
  pcfg_migrate
  local branch="$1" desc="$2" repo name existing
  repo=$(_pcfg_read_repo); name=$(_pcfg_read_name); name="${name:-default}"
  existing=$(_pcfg_profiles_tsv)
  {
    printf '%s\n' "$existing" | awk -F'\t' -v b="$branch" -v d="$desc" '
      $1 == "" { next }
      { if ($1 == b) { print $1 "\t" d; found = 1 } else { print } }
      END { if (!found) print b "\t" d }'
  } | _pcfg_write "$repo" "$name"
}

# --- workspace marker (the <workspace>/.claude-profiles file) ---

marker_path() { printf '%s/.claude-profiles' "$1"; }

# Read a key from a workspace marker, accepting JSON or legacy key=value.
marker_get() { # <workspace> <key>
  local file; file="$(marker_path "$1")"
  [ -f "$file" ] || return 0
  if _is_json_file "$file"; then
    json_get_string "$file" "$2"
  else
    sed -n "s/^$2=//p" "$file" | head -n1
  fi
}

# Read profile from a workspace's marker (JSON or legacy). Stable public name.
read_marker_profile() { marker_get "$1" profile; }

# Write a workspace marker as JSON. profile='none' records opt-out (no repo).
write_marker_json() { # <workspace> <profile> [repo] [source]
  local ws="$1" profile="$2" repo="${3:-}" source="${4:-}" file
  file="$(marker_path "$ws")"
  {
    printf '{\n'
    printf '  "$schema": "%s",\n' "$PCFG_MARKER_SCHEMA_URL"
    printf '  "version": 1,\n'
    if [ "$profile" != "none" ]; then
      [ -n "$source" ] && printf '  "source": "%s",\n' "$(json_escape "$source")"
      [ -n "$repo" ] && printf '  "repo": "%s",\n' "$(json_escape "$repo")"
    fi
    printf '  "profile": "%s"\n' "$(json_escape "$profile")"
    printf '}\n'
  } > "$file"
}
