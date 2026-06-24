#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Not a git repo → state=not_git
out=$(run_script ensure-gitignore.sh "$WORKSPACE")
assert_kv "$out" state not_git "not_git state" || exit 1

# Init a git repo, no existing .gitignore → state=added, file created
git -C "$WORKSPACE" init -q
out=$(run_script ensure-gitignore.sh "$WORKSPACE")
assert_kv "$out" state added "added state" || exit 1
assert_contains "$(cat "$WORKSPACE/.gitignore")" ".claude/" "gitignore content" || exit 1

# Re-run → state=already_ignored (idempotent)
out=$(run_script ensure-gitignore.sh "$WORKSPACE")
assert_kv "$out" state already_ignored "idempotent" || exit 1

# Pre-existing .gitignore without trailing newline → entry is appended
rm "$WORKSPACE/.gitignore"
printf 'node_modules' > "$WORKSPACE/.gitignore"  # no trailing newline
out=$(run_script ensure-gitignore.sh "$WORKSPACE")
assert_kv "$out" state added "added with prior content" || exit 1
content=$(cat "$WORKSPACE/.gitignore")
assert_contains "$content" "node_modules" "preserved prior" || exit 1
assert_contains "$content" ".claude/" "added new" || exit 1
