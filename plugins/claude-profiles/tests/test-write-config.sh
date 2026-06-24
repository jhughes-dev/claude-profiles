#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Fresh config — repo= line written.
run_script write-config.sh "git@example.com:me/profiles.git" >/dev/null
got=$(cat "$HOME/.claude-profiles-config")
assert_contains "$got" "repo=git@example.com:me/profiles.git" "wrote repo line" || exit 1

# Updating the URL replaces in place; doesn't leak duplicates.
run_script write-config.sh "/new/path.git" >/dev/null
got=$(cat "$HOME/.claude-profiles-config")
assert_contains "$got" "repo=/new/path.git" "updated url" || exit 1
count=$(grep -c '^repo=' "$HOME/.claude-profiles-config")
assert_eq "$count" "1" "exactly one repo= line" || exit 1

# Existing config with extra keys is preserved.
echo "branches=main,template" >> "$HOME/.claude-profiles-config"
run_script write-config.sh "/another.git" >/dev/null
got=$(cat "$HOME/.claude-profiles-config")
assert_contains "$got" "repo=/another.git" "url replaced" || exit 1
assert_contains "$got" "branches=main,template" "branches preserved" || exit 1
