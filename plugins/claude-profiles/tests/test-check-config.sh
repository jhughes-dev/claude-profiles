#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# No config → state=missing
out=$(run_script check-config.sh)
assert_kv "$out" state missing "missing state" || exit 1

# Empty config → state=no_repo
: > "$HOME/.claude-profiles-config"
out=$(run_script check-config.sh)
assert_kv "$out" state no_repo "no_repo state" || exit 1

# Valid local repo → state=ok
repo=$(make_fake_profiles_repo)
write_config "$repo"
out=$(run_script check-config.sh)
assert_kv "$out" state ok "ok state" || exit 1
assert_kv "$out" repo "$repo" "repo echoed" || exit 1

# Bogus URL → state=unreachable
write_config "/no/such/path.git"
out=$(run_script check-config.sh)
assert_kv "$out" state unreachable "unreachable state" || exit 1
