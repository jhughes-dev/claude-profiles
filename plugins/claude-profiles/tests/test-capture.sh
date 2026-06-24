#!/usr/bin/env bash
# capture-user-branch honors a configurable user-profile branch (issue #10).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

repo=$(make_fake_profiles_repo)
write_config "$repo"

# Fake user space with some content.
mkdir -p "$HOME/.claude"
echo "user config" > "$HOME/.claude/CLAUDE.md"

# Capture as a custom branch name (not the default 'user').
run_script capture-user-branch.sh mine >/dev/null 2>&1

# The branch choice is persisted to the global config.
assert_eq "$(pcfg_get_pref userBranch)" "mine" "userBranch preference persisted" || exit 1

# ~/.claude is on that branch and it was pushed; default 'user' was not created.
assert_eq "$(git -C "$HOME/.claude" branch --show-current)" "mine" "~/.claude on branch 'mine'" || exit 1
git ls-remote --heads "$repo" | grep -q 'refs/heads/mine$' || { echo "branch 'mine' not pushed" >&2; exit 1; }
if git ls-remote --heads "$repo" | grep -q 'refs/heads/user$'; then
  echo "should not have created a 'user' branch" >&2; exit 1
fi

# A later capture with no arg reuses the stored branch (no error, still 'mine').
run_script capture-user-branch.sh >/dev/null 2>&1
assert_eq "$(pcfg_get_pref userBranch)" "mine" "stored branch reused on argless capture" || exit 1
