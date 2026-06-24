#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

write_config "git@example.com:me/profiles.git"

# With a real profile name → marker has profile= and repo=
run_script write-marker.sh rust-cli "$WORKSPACE" >/dev/null
got=$(cat "$WORKSPACE/.claude-profiles")
assert_contains "$got" "profile=rust-cli" "profile line" || exit 1
assert_contains "$got" "repo=git@example.com:me/profiles.git" "repo line" || exit 1

# With profile=none → no repo= line
run_script write-marker.sh none "$WORKSPACE" >/dev/null
got=$(cat "$WORKSPACE/.claude-profiles")
assert_contains "$got" "profile=none" "none profile line" || exit 1
case "$got" in
  *repo=*) echo "expected no repo= for profile=none, got: $got" >&2; exit 1 ;;
esac
