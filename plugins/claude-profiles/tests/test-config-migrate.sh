#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# A legacy (pre-1.x) key=value config is migrated to JSON on first access.
write_legacy_config "git@example.com:me/profiles.git" "rust-cli,web-development"

assert_eq "$(pcfg_default_repo)" "git@example.com:me/profiles.git" "migrated repo" || exit 1
assert_eq "$(pcfg_branches_csv)" "rust-cli,web-development" "migrated branches" || exit 1

# JSON file created at the XDG path; legacy file retired (not left to drift).
[ -f "$(pcfg_file)" ] || { echo "config.json not created at $(pcfg_file)" >&2; exit 1; }
[ ! -f "$HOME/.claude-profiles-config" ] || { echo "legacy config not retired" >&2; exit 1; }
assert_contains "$(cat "$(pcfg_file)")" '"version": 1' "schema version present" || exit 1

# check-config reports ok against the migrated config (reachable local repo).
repo=$(make_fake_profiles_repo)
write_legacy_config "$repo"
rm -rf "$(pcfg_dir)"   # force a fresh migration from the new legacy file
out=$(run_script check-config.sh)
assert_kv "$out" state ok "ok after migrating a reachable repo" || exit 1
