#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

write_config "git@example.com:me/profiles.git"

# Real profile → JSON marker with profile, repo, and source fields.
run_script write-marker.sh rust-cli "$WORKSPACE" >/dev/null
got=$(cat "$WORKSPACE/.claude-profiles")
assert_contains "$got" '"profile": "rust-cli"' "profile field" || exit 1
assert_contains "$got" '"repo": "git@example.com:me/profiles.git"' "repo field" || exit 1
assert_contains "$got" '"source": "default"' "source field" || exit 1
assert_eq "$(read_marker_profile "$WORKSPACE")" "rust-cli" "marker reads back" || exit 1

# profile=none → opt-out marker, no repo/source.
run_script write-marker.sh none "$WORKSPACE" >/dev/null
got=$(cat "$WORKSPACE/.claude-profiles")
assert_contains "$got" '"profile": "none"' "none profile" || exit 1
case "$got" in
  *'"repo"'*) echo "expected no repo for profile=none, got: $got" >&2; exit 1 ;;
esac
assert_eq "$(read_marker_profile "$WORKSPACE")" "none" "none reads back" || exit 1

# Back-compat: a legacy key=value marker still reads.
printf 'profile=legacy-branch\nrepo=x\n' > "$WORKSPACE/.claude-profiles"
assert_eq "$(read_marker_profile "$WORKSPACE")" "legacy-branch" "legacy marker reads" || exit 1
