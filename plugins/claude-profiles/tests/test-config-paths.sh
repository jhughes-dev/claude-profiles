#!/usr/bin/env bash
# Exercise the pure-bash (no-jq) config path deterministically, and — when a real
# jq is present — assert the jq path produces byte-identical config.json.
# Forced via CLAUDE_PROFILES_NO_JQ (honored by _have_jq in _lib.sh).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

build_config() {
  rm -f "$(pcfg_file)"
  pcfg_add_source personal "https://example.com/p.git" default
  pcfg_add_source work "https://example.com/w.git"
  pcfg_set_branches_csv "rust-cli,web" personal
  pcfg_set_description rust-cli "Rust CLI projects" personal
  pcfg_set_pref promoteMode copy
}

# --- Force the no-jq path and verify reads/writes round-trip correctly. -------
export CLAUDE_PROFILES_NO_JQ=1
build_config
nojq=$(cat "$(pcfg_file)")
assert_contains "$nojq" '"name": "personal"' "no-jq: personal source written" || { echo "$nojq"; exit 1; }
assert_contains "$nojq" "Rust CLI projects" "no-jq: description written" || { echo "$nojq"; exit 1; }
assert_eq "$(pcfg_default_source_name)" "personal" "no-jq: default source read" || exit 1
assert_eq "$(pcfg_source_branches_csv personal)" "rust-cli,web" "no-jq: branches read" || exit 1
assert_eq "$(pcfg_description rust-cli personal)" "Rust CLI projects" "no-jq: description read" || exit 1
assert_eq "$(pcfg_get_pref promoteMode)" "copy" "no-jq: preference read" || exit 1

# --- If a real jq exists, it must produce identical config.json. --------------
if command -v jq >/dev/null 2>&1; then
  unset CLAUDE_PROFILES_NO_JQ
  build_config
  withjq=$(cat "$(pcfg_file)")
  assert_eq "$withjq" "$nojq" "jq and no-jq produce identical config.json" \
    || { printf -- '--- jq ---\n%s\n--- no-jq ---\n%s\n' "$withjq" "$nojq"; exit 1; }
fi
