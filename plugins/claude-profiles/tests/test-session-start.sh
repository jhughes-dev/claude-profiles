#!/usr/bin/env bash
# Exercise the SessionStart hook's main branches without hitting the network.
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

HOOK="$PLUGIN_ROOT/hooks/session-start.sh"
run_hook() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" </dev/null 2>/dev/null; }

# Mark the daily new-branch and version checks as already done so the hook never
# reaches out to a remote during the test.
touch "$HOME/.claude-profiles-version-stamp" "$HOME/.claude-profiles-branches-stamp"

# (a) Silent inside the global ~/.claude.
mkdir -p "$HOME/.claude"
out=$(run_hook "$HOME/.claude")
assert_eq "$out" "" "silent inside ~/.claude" || { echo "[$out]"; exit 1; }

# (b) No profiles repo configured → emits the init nudge.
ws1="$TEST_TMP/ws1"; mkdir -p "$ws1"
out=$(run_hook "$ws1")
assert_contains "$out" "No Claude profiles repo configured" "init nudge when unconfigured" \
  || { echo "$out"; exit 1; }

# (c) Configured + a profile clone with a dirty tree → commit nudge.
bare=$(make_fake_profiles_repo)
write_config "$bare"
ws2="$TEST_TMP/ws2"; mkdir -p "$ws2"
git clone -q --branch main "$bare" "$ws2/.claude"
( cd "$ws2/.claude" && git config user.email t@t && git config user.name t )
write_marker_json "$ws2" main "$bare"
echo dirty > "$ws2/.claude/README.md"
out=$(run_hook "$ws2")
assert_contains "$out" "uncommitted changes" "commit nudge for a dirty profile" \
  || { echo "$out"; exit 1; }

# (d) Opted-out workspace → silent (no marker nag).
ws3="$TEST_TMP/ws3"; mkdir -p "$ws3"
write_marker_json "$ws3" none
out=$(run_hook "$ws3")
assert_eq "$out" "" "silent when opted out" || { echo "[$out]"; exit 1; }
