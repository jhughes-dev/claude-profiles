#!/usr/bin/env bash
# Project trait detection (issue #4).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

mk() { mkdir -p "$TEST_TMP/$1"; }

mk rustp; echo '[package]' > "$TEST_TMP/rustp/Cargo.toml"
assert_contains "$(run_script detect-project.sh "$TEST_TMP/rustp")" "rust" "rust detected" || exit 1

mk nodep; printf '{"dependencies":{"next":"14.0.0"}}' > "$TEST_TMP/nodep/package.json"
out=$(run_script detect-project.sh "$TEST_TMP/nodep")
assert_contains "$out" "node" "node detected" || exit 1
assert_contains "$out" "nextjs" "nextjs detected" || exit 1

mk taurip/src-tauri; echo '[package]' > "$TEST_TMP/taurip/Cargo.toml"
assert_contains "$(run_script detect-project.sh "$TEST_TMP/taurip")" "tauri" "tauri detected" || exit 1

mk plug/.claude-plugin; echo '{}' > "$TEST_TMP/plug/.claude-plugin/marketplace.json"
assert_contains "$(run_script detect-project.sh "$TEST_TMP/plug")" "claude-plugin" "plugin detected" || exit 1

# Empty workspace: no traits, no crash, exit 0.
mk empty
run_script detect-project.sh "$TEST_TMP/empty" >/dev/null
