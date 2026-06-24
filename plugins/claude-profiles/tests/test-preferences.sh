#!/usr/bin/env bash
# Config preferences (issue #6: promoteMode).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

pcfg_set_repo "git@example.com:me/p.git"
pcfg_set_branches_csv "rust-cli,web-dev"

assert_eq "$(pcfg_get_pref promoteMode)" "" "unset preference is empty" || exit 1

pcfg_set_pref promoteMode copy
assert_eq "$(pcfg_get_pref promoteMode)" "copy" "preference set" || exit 1

# Preference survives source mutations and doesn't disturb repo/branches.
pcfg_add_source work "git@example.com:me/w.git"
assert_eq "$(pcfg_get_pref promoteMode)" "copy" "preference survives add-source" || exit 1
assert_eq "$(pcfg_default_repo)" "git@example.com:me/p.git" "repo intact" || exit 1
assert_eq "$(pcfg_branches_csv)" "rust-cli,web-dev" "branches intact" || exit 1

# Replacing the value keeps a single entry.
pcfg_set_pref promoteMode move
assert_eq "$(pcfg_get_pref promoteMode)" "move" "preference replaced" || exit 1
count=$(grep -c '"promoteMode"' "$(pcfg_file)")
assert_eq "$count" "1" "exactly one promoteMode entry" || exit 1
