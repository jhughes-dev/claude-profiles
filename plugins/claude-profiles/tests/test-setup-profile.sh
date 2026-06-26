#!/usr/bin/env bash
# One-shot profile setup (issue #4).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

repo=$(make_repo_with_branches A rust-cli)
write_config "$repo"
git -C "$WORKSPACE" init -q   # workspace must be a git repo for .gitignore handling

# Existing branch: clone + gitignore + marker in one call.
out=$(run_script setup-profile.sh rust-cli "$WORKSPACE")
assert_kv "$out" state ok "existing: state ok" || exit 1
assert_kv "$out" branch rust-cli "existing: branch echoed" || exit 1
[ -d "$WORKSPACE/.claude/.git" ] || { echo "clone missing" >&2; exit 1; }
grep -qF '.claude/' "$WORKSPACE/.gitignore" || { echo ".claude/ not gitignored" >&2; exit 1; }
assert_eq "$(read_marker_profile "$WORKSPACE")" "rust-cli" "marker written" || exit 1

# Opt out.
ws2="$TEST_TMP/ws2"; mkdir -p "$ws2"
out=$(run_script setup-profile.sh --none "$ws2")
assert_kv "$out" state none "none: state" || exit 1
assert_eq "$(read_marker_profile "$ws2")" "none" "none: marker" || exit 1

# New from template: creates + pushes the branch, sets it up.
ws3="$TEST_TMP/ws3"; mkdir -p "$ws3"; git -C "$ws3" init -q
out=$(run_script setup-profile.sh --new fresh-profile "$ws3")
assert_kv "$out" state ok "new: state ok" || exit 1
assert_eq "$(git -C "$ws3/.claude" branch --show-current)" "fresh-profile" "new: on new branch" || exit 1
git ls-remote --heads "$repo" | grep -q 'refs/heads/fresh-profile$' || { echo "new branch not pushed" >&2; exit 1; }
assert_eq "$(read_marker_profile "$ws3")" "fresh-profile" "new: marker" || exit 1
