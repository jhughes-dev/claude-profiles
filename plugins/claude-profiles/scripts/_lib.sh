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

# True if dotted-numeric version <a> is strictly greater than <b> (e.g. 1.2.0 > 1.1.9).
version_gt() { # <a> <b>
  [ "$1" = "$2" ] && return 1
  local hi
  hi=$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)
  [ "$hi" = "$1" ]
}

# Highest claude-profiles release version tagged on <repo> (empty if none).
# Reads `claude-profiles--vX.Y.Z` tags, the form `claude plugin tag` creates.
latest_release_version() { # <repo>
  git ls-remote --tags "$1" 'claude-profiles--v*' 2>/dev/null \
    | sed -n 's#.*refs/tags/claude-profiles--v\([0-9][0-9.]*\)$#\1#p' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1
}

# --- multi-source config (issue #1) ---
#
# The config holds an array of sources, each a profiles repo. Pure-bash I/O goes
# through a flat "dump" intermediate so we can manipulate the array without jq:
#   S<TAB>name<TAB>repo<TAB>default      (one per source)
#   P<TAB>name<TAB>branch<TAB>desc       (one cached profile, under its source)
# jq is used for the dump/parse when present; otherwise a layout-aware awk parser
# reads the writer's own format (one source key per line, one profile per line).

# Flatten config.json to the S/P dump format above.
pcfg_dump() {
  local file; file="$(pcfg_file)"
  [ -f "$file" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      .sources[]? |
      ( "S\t" + .name + "\t" + (.repo // "") + "\t" + ((.default // false) | tostring) ),
      ( .name as $n | (.profiles[]? | "P\t" + $n + "\t" + .branch + "\t" + (.description // "")) )
    ' "$file" 2>/dev/null
    return
  fi
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
      qpos = index(rest, "\"")
      if (qpos == 0) { sub(/^[ \t]*/, "", rest); sub(/[ \t,].*$/, "", rest); return rest }
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
    # Source scalar keys live on their own lines (never on a profile line).
    /"name"[ \t]*:/    && $0 !~ /"branch"/ { i++; sn[i] = field($0, "name"); sd[i] = "false"; next }
    /"repo"[ \t]*:/    && $0 !~ /"branch"/ { if (i > 0) sr[i] = field($0, "repo"); next }
    /"default"[ \t]*:/ && $0 !~ /"branch"/ { if (i > 0) sd[i] = field($0, "default"); next }
    /"branch"[ \t]*:/ {
      if (i > 0) { pc[i]++; pb[i, pc[i]] = field($0, "branch"); pd[i, pc[i]] = field($0, "description") }
    }
    END {
      for (s = 1; s <= i; s++) {
        printf "S\t%s\t%s\t%s\n", sn[s], sr[s], sd[s]
        for (p = 1; p <= pc[s]; p++) printf "P\t%s\t%s\t%s\n", sn[s], pb[s, p], pd[s, p]
      }
    }
  ' "$file"
}

# Emit config.json from an S/P dump on stdin (profiles grouped under their source).
_pcfg_write_from_dump() {
  local file dir tmp; file="$(pcfg_file)"; dir="$(pcfg_dir)"; mkdir -p "$dir"; tmp="$file.tmp.$$"
  awk -F'\t' -v schema="$PCFG_SCHEMA_URL" '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    $1 == "S" { ns++; sn[ns] = $2; sr[ns] = $3; sd[ns] = ($4 == "true" ? "true" : "false"); idx[$2] = ns }
    $1 == "P" { k = idx[$2]; if (k) { pc[k]++; pb[k, pc[k]] = $3; pd[k, pc[k]] = $4 } }
    END {
      printf "{\n  \"$schema\": \"%s\",\n  \"version\": 1,\n  \"sources\": [", schema
      if (ns == 0) { printf "]\n}\n"; exit }
      printf "\n"
      for (s = 1; s <= ns; s++) {
        printf "    {\n      \"name\": \"%s\",\n      \"repo\": \"%s\",\n      \"default\": %s,\n      \"profiles\": [",
          esc(sn[s]), esc(sr[s]), sd[s]
        if (pc[s] == 0) { printf "]" } else {
          printf "\n"
          for (p = 1; p <= pc[s]; p++)
            printf "        { \"branch\": \"%s\", \"description\": \"%s\" }%s\n",
              esc(pb[s, p]), esc(pd[s, p]), (p < pc[s] ? "," : "")
          printf "      ]"
        }
        printf "\n    }%s\n", (s < ns ? "," : "")
      }
      printf "  ]\n}\n"
    }
  ' > "$tmp"
  mv "$tmp" "$file"
}

# Ensure exactly one source is marked default (the first, if none is).
_pcfg_ensure_default() {
  awk -F'\t' '
    { line[NR] = $0
      if ($1 == "S") { if ($4 == "true") hasdef = 1; if (!firstS) firstS = NR } }
    END {
      for (n = 1; n <= NR; n++) {
        if (!hasdef && n == firstS) {
          split(line[n], a, "\t"); printf "%s\t%s\t%s\ttrue\n", a[1], a[2], a[3]
        } else print line[n]
      }
    }'
}

# Migrate a legacy ~/.claude-profiles-config (key=value) to JSON, once.
pcfg_migrate() {
  local new old; new="$(pcfg_file)"; old="$(pcfg_legacy_file)"
  [ -f "$new" ] && return 0
  [ -f "$old" ] || return 0
  local repo branches
  repo=$(sed -n 's/^repo=//p' "$old" | head -n1)
  branches=$(sed -n 's/^branches=//p' "$old" | head -n1)
  {
    printf 'S\tdefault\t%s\ttrue\n' "$repo"
    ( IFS=,; for b in $branches; do [ -n "$b" ] && printf 'P\tdefault\t%s\t\n' "$b"; done )
  } | _pcfg_write_from_dump
  mv "$old" "$old.migrated-to-json" 2>/dev/null || true
}

# --- public config API: sources ---

# List all source names, one per line.
pcfg_sources() { pcfg_migrate; pcfg_dump | awk -F'\t' '$1 == "S" { print $2 }'; }

# Name of the default source (the one flagged default, else the first).
pcfg_default_source_name() {
  pcfg_migrate
  pcfg_dump | awk -F'\t' '
    $1 == "S" { if ($4 == "true") { print $2; found = 1; exit } if (first == "") first = $2 }
    END { if (!found && first != "") print first }'
}

# Repo URL for a named source.
pcfg_source_repo() { # <name>
  pcfg_migrate
  pcfg_dump | awk -F'\t' -v n="$1" '$1 == "S" && $2 == n { print $3; exit }'
}

# Cached branches for a named source, as CSV.
pcfg_source_branches_csv() { # <name>
  pcfg_migrate
  pcfg_dump | awk -F'\t' -v n="$1" '$1 == "P" && $2 == n { print $3 }' | paste -sd, -
}

# Source names that have <branch> cached, one per line (for disambiguation).
pcfg_find_sources_for_branch() { # <branch>
  pcfg_migrate
  pcfg_dump | awk -F'\t' -v b="$1" '$1 == "P" && $3 == b { print $2 }'
}

# Add a source (or update its repo if the name exists). [default] marks it default.
pcfg_add_source() { # <name> <repo> [default]
  pcfg_migrate
  local name="$1" repo="$2" makedef="${3:-}" dump
  dump=$(pcfg_dump)
  if printf '%s\n' "$dump" | awk -F'\t' -v n="$name" '$1 == "S" && $2 == n { f = 1 } END { exit !f }'; then
    dump=$(printf '%s\n' "$dump" | awk -F'\t' -v n="$name" -v r="$repo" 'BEGIN { OFS = "\t" } $1 == "S" && $2 == n { $3 = r } { print }')
  else
    dump=$(printf '%s\nS\t%s\t%s\tfalse' "$dump" "$name" "$repo")
  fi
  [ "$makedef" = default ] && dump=$(printf '%s\n' "$dump" | awk -F'\t' -v n="$name" 'BEGIN { OFS = "\t" } $1 == "S" { $4 = ($2 == n ? "true" : "false") } { print }')
  printf '%s\n' "$dump" | _pcfg_ensure_default | _pcfg_write_from_dump
}

# Remove a source (and its cached profiles).
pcfg_remove_source() { # <name>
  pcfg_migrate
  pcfg_dump | awk -F'\t' -v n="$1" '$2 != n' | _pcfg_ensure_default | _pcfg_write_from_dump
}

# Mark a source as the default.
pcfg_set_default_source() { # <name>
  pcfg_migrate
  pcfg_dump | awk -F'\t' -v n="$1" 'BEGIN { OFS = "\t" } $1 == "S" { $4 = ($2 == n ? "true" : "false") } { print }' \
    | _pcfg_write_from_dump
}

# --- back-compat single-(default-)source helpers ---

pcfg_default_repo() { pcfg_migrate; pcfg_source_repo "$(pcfg_default_source_name)"; }

pcfg_branches_csv() { pcfg_migrate; pcfg_source_branches_csv "$(pcfg_default_source_name)"; }

pcfg_description() { # <branch> [source]
  pcfg_migrate
  local src="${2:-}"
  pcfg_dump | awk -F'\t' -v b="$1" -v s="$src" '$1 == "P" && $3 == b && (s == "" || $2 == s) { print $4; exit }'
}

# Set the (default or named) source's repo, creating the source if needed.
pcfg_set_repo() { # <url> [source]
  pcfg_migrate
  local url="$1" name="${2:-}"
  [ -n "$name" ] || name=$(pcfg_default_source_name)
  [ -n "$name" ] || name=default
  pcfg_add_source "$name" "$url"
}

# Replace a source's cached branch list, preserving existing descriptions.
pcfg_set_branches_csv() { # <csv> [source]
  pcfg_migrate
  local csv="$1" src="${2:-}" dump existing kept newp b d
  [ -n "$src" ] || src=$(pcfg_default_source_name)
  dump=$(pcfg_dump)
  existing=$(printf '%s\n' "$dump" | awk -F'\t' -v s="$src" '$1 == "P" && $2 == s { print $3 "\t" $4 }')
  kept=$(printf '%s\n' "$dump" | awk -F'\t' -v s="$src" '!($1 == "P" && $2 == s)')
  newp=$( ( IFS=,
    for b in $csv; do
      [ -n "$b" ] || continue
      d=$(printf '%s\n' "$existing" | awk -F'\t' -v x="$b" '$1 == x { print $2; exit }')
      printf 'P\t%s\t%s\t%s\n' "$src" "$b" "$d"
    done ) )
  printf '%s\n%s\n' "$kept" "$newp" | _pcfg_write_from_dump
}

pcfg_set_description() { # <branch> <description> [source]  (issue #3)
  pcfg_migrate
  local branch="$1" desc="$2" src="${3:-}"
  [ -n "$src" ] || src=$(pcfg_default_source_name)
  pcfg_dump | awk -F'\t' -v s="$src" -v b="$branch" -v d="$desc" '
    BEGIN { OFS = "\t" }
    $1 == "P" && $2 == s && $3 == b { $4 = d; found = 1 }
    { print }
    END { if (!found) print "P", s, b, d }' | _pcfg_write_from_dump
}

# --- active source (the source a command/script is operating on) ---
#
# Scripts operate on the "active" source: the CLAUDE_PROFILES_SOURCE override if
# set (the `set` command sets it after disambiguating a branch), else the default
# source. With a single source these both resolve to it, so callers stay simple.

pcfg_active_source() {
  pcfg_migrate
  local s="${CLAUDE_PROFILES_SOURCE:-}"
  [ -n "$s" ] || s=$(pcfg_default_source_name)
  printf '%s' "$s"
}

pcfg_active_repo() { pcfg_source_repo "$(pcfg_active_source)"; }

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
