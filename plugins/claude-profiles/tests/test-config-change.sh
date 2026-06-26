#!/usr/bin/env bash
# ConfigChange hook detects global additions and asks about placement (#9).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

uc="$HOME/.claude"
mkdir -p "$uc/skills/existing"
echo s > "$uc/skills/existing/SKILL.md"
printf '{ "enabledPlugins": { "foo@bar": true } }\n' > "$uc/settings.json"

# Seed the baseline, as SessionStart does.
bash "$PLUGIN_ROOT/scripts/list-user-components.sh" | sort -u > "$HOME/.claude-profiles-global-cache"

# Add a new global skill and enable a new global plugin.
mkdir -p "$uc/skills/newskill"; echo s > "$uc/skills/newskill/SKILL.md"
printf '{ "enabledPlugins": { "foo@bar": true, "baz@qux": true } }\n' > "$uc/settings.json"

run_cc() { CLAUDE_PROJECT_DIR="$1" bash "$PLUGIN_ROOT/hooks/config-change.sh" </dev/null; }

# Non-profile workspace: still fires, with the no-profile guidance.
out=$(run_cc "$WORKSPACE")
assert_contains "$out" "newskill" "notifies about a new global skill" || exit 1
assert_contains "$out" "baz@qux" "notifies about a newly-enabled global plugin" || exit 1
assert_contains "$out" "no claude-profiles profile" "uses no-profile guidance" || exit 1

# Nothing new since the last run → silent.
out=$(run_cc "$WORKSPACE")
assert_eq "$out" "" "silent when nothing new was added" || exit 1

# Profile workspace: profile-aware guidance, names the active profile.
mkdir -p "$uc/skills/another"; echo s > "$uc/skills/another/SKILL.md"
ws2="$TEST_TMP/ws2"; mkdir -p "$ws2/.claude"
git -C "$ws2/.claude" init -q -b rust-cli
write_marker_json "$ws2" rust-cli "git@example.com:me/p.git" default
out=$(run_cc "$ws2")
assert_contains "$out" "another" "profile workspace notifies about new global skill" || exit 1
assert_contains "$out" "rust-cli" "names the active profile" || exit 1
