#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Fresh config — repo set, valid JSON written at the XDG path.
run_script write-config.sh "git@example.com:me/profiles.git" >/dev/null
assert_eq "$(pcfg_default_repo)" "git@example.com:me/profiles.git" "repo set" || exit 1
assert_eq "$(pcfg_default_source_name)" "default" "default source name" || exit 1
[ -f "$(pcfg_file)" ] || { echo "config.json not created at $(pcfg_file)" >&2; exit 1; }

# Updating the URL replaces it in place — no duplicate repo entries.
run_script write-config.sh "/new/path.git" >/dev/null
assert_eq "$(pcfg_default_repo)" "/new/path.git" "url updated" || exit 1
count=$(grep -c '"repo"' "$(pcfg_file)")
assert_eq "$count" "1" "exactly one repo entry" || exit 1

# Cached branches + descriptions (issue #3) survive a repo update.
pcfg_set_branches_csv "rust-cli,web-development"
pcfg_set_description "rust-cli" "Rust CLI work"
run_script write-config.sh "/another.git" >/dev/null
assert_eq "$(pcfg_default_repo)" "/another.git" "url replaced" || exit 1
assert_eq "$(pcfg_branches_csv)" "rust-cli,web-development" "branches preserved" || exit 1
assert_eq "$(pcfg_description rust-cli)" "Rust CLI work" "description preserved" || exit 1
