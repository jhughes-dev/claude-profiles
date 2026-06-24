#!/usr/bin/env bash
# list-user-components + promote-component (issue #6).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Build a fake user space (~/.claude = throwaway HOME).
uc="$HOME/.claude"
mkdir -p "$uc/skills/myskill" "$uc/agents/myagent" "$uc/commands" "$uc/hooks"
echo "skill" > "$uc/skills/myskill/SKILL.md"
echo "agent" > "$uc/agents/myagent/AGENT.md"
echo "README" > "$uc/skills/README.md"          # should be ignored
echo "cmd" > "$uc/commands/mycmd.md"
echo "README" > "$uc/commands/README.md"         # should be ignored
echo "hook" > "$uc/hooks/myhook.sh"
echo "x" > "$uc/CLAUDE.md"
cat > "$uc/settings.json" <<'JSON'
{ "model": "opus", "enabledPlugins": { "foo@bar": true, "baz@qux": false } }
JSON

# Enumeration.
out=$(run_script list-user-components.sh)
assert_contains "$out" "$(printf 'skill\tmyskill')" "skill listed" || exit 1
assert_contains "$out" "$(printf 'agent\tmyagent')" "agent listed" || exit 1
assert_contains "$out" "$(printf 'command\tmycmd')" "command listed" || exit 1
assert_contains "$out" "$(printf 'hook\tmyhook.sh')" "hook listed" || exit 1
assert_contains "$out" "$(printf 'plugin\tfoo@bar\ttrue')" "enabled plugin listed" || exit 1
assert_contains "$out" "$(printf 'plugin\tbaz@qux\tfalse')" "disabled plugin listed" || exit 1
assert_contains "$out" "$(printf 'setting\tmodel')" "model setting listed" || exit 1
assert_contains "$out" "$(printf 'claudemd\tpresent')" "claude.md noted" || exit 1
case "$out" in *README*) echo "README should be excluded" >&2; exit 1 ;; esac

# Promote: copy a skill (source remains), move a command (source removed).
mkdir -p "$WORKSPACE/.claude"
run_script promote-component.sh skill myskill copy "$WORKSPACE" >/dev/null
[ -f "$WORKSPACE/.claude/skills/myskill/SKILL.md" ] || { echo "skill not copied" >&2; exit 1; }
[ -d "$uc/skills/myskill" ] || { echo "copy must keep source" >&2; exit 1; }

run_script promote-component.sh command mycmd move "$WORKSPACE" >/dev/null
[ -f "$WORKSPACE/.claude/commands/mycmd.md" ] || { echo "command not moved" >&2; exit 1; }
[ -e "$uc/commands/mycmd.md" ] && { echo "move must remove source" >&2; exit 1; }

echo ok
