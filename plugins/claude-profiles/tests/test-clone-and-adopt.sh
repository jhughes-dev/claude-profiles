#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

repo=$(make_fake_profiles_repo)
write_config "$repo"

# clone-profile.sh main → .claude exists, on main, with origin set
run_script clone-profile.sh main "" "$WORKSPACE" >/dev/null
[ -d "$WORKSPACE/.claude/.git" ] || { echo ".claude/.git missing" >&2; exit 1; }
branch=$(git -C "$WORKSPACE/.claude" branch --show-current)
assert_eq "$branch" "main" "checked out main" || exit 1

# Refuses to overwrite existing .claude
if run_script clone-profile.sh main "" "$WORKSPACE" >/dev/null 2>&1; then
  echo "expected non-zero when .claude already exists" >&2; exit 1
fi

# new-from-template flow
rm -rf "$WORKSPACE/.claude"
run_script clone-profile.sh template my-thing "$WORKSPACE" >/dev/null
branch=$(git -C "$WORKSPACE/.claude" branch --show-current)
assert_eq "$branch" "my-thing" "branched from template" || exit 1
heads=$(git ls-remote --heads "$repo" | awk '{sub("refs/heads/","",$2); print $2}')
assert_contains "$heads" "my-thing" "new branch pushed to remote" || exit 1

# adopt-profile.sh against a fresh .claude in a separate workspace.
ws2="$TEST_TMP/ws2"
mkdir -p "$ws2/.claude"
echo "hello" > "$ws2/.claude/CLAUDE.md"
run_script adopt-profile.sh adopted-thing "$ws2" >/dev/null
# Confirm origin remote points at our repo and branch was pushed.
got_remote=$(normalize_path "$(git -C "$ws2/.claude" remote get-url origin)")
assert_eq "$got_remote" "$repo" "origin set" || exit 1
heads=$(git ls-remote --heads "$repo" | awk '{sub("refs/heads/","",$2); print $2}')
assert_contains "$heads" "adopted-thing" "branch pushed" || exit 1
