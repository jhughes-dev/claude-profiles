#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Build a fake profiles repo with two branches that don't conflict, plus one
# that does, by seeding distinct files on each branch.
repo=$(make_fake_profiles_repo)
write_config "$repo"

# Add divergent commits on three branches: 'a' (no conflict with 'b'),
# 'b', and 'c' (conflicts with 'a' on shared.txt).
seed="$TEST_TMP/seed"
git clone -q -b main "$repo" "$seed"
(
  cd "$seed"
  git config user.email t@t
  git config user.name t

  git checkout -q -b a
  echo only-a > a-only.txt
  git add a-only.txt
  git commit -q -m "branch a"
  echo from-a > shared.txt
  git add shared.txt
  git commit -q -m "shared from a"
  git push -q origin a

  git checkout -q -b b main
  echo only-b > b-only.txt
  git add b-only.txt
  git commit -q -m "branch b"
  git push -q origin b

  git checkout -q -b c main
  echo from-c > shared.txt
  git add shared.txt
  git commit -q -m "shared from c"
  git push -q origin c
)
rm -rf "$seed"

# Clean merge: a + b → 'combo'. Should push and exit 0.
run_script merge-profile.sh combo a b "$WORKSPACE" >/dev/null
[ -d "$WORKSPACE/.claude/.git" ] || { echo ".claude/.git missing" >&2; exit 1; }
branch=$(git -C "$WORKSPACE/.claude" branch --show-current)
assert_eq "$branch" "combo" "checked out new merged branch" || exit 1
[ -f "$WORKSPACE/.claude/a-only.txt" ] || { echo "missing a-only.txt" >&2; exit 1; }
[ -f "$WORKSPACE/.claude/b-only.txt" ] || { echo "missing b-only.txt" >&2; exit 1; }
heads=$(git ls-remote --heads "$repo" | awk '{sub("refs/heads/","",$2); print $2}')
assert_contains "$heads" "combo" "merged branch pushed to remote" || exit 1

# Conflict path: a + c on a fresh workspace. Expect exit 2, no push, conflict
# markers in shared.txt.
ws2="$TEST_TMP/ws2"
mkdir -p "$ws2"
out=$(bash "$PLUGIN_ROOT/scripts/merge-profile.sh" bad a c "$ws2" 2>&1)
rc=$?
assert_eq "$rc" "2" "conflict exits 2" || { printf '%s\n' "$out" >&2; exit 1; }
assert_contains "$out" "shared.txt" "conflict report mentions file" || exit 1
heads=$(git ls-remote --heads "$repo" | awk '{sub("refs/heads/","",$2); print $2}')
case "$heads" in
  *bad*) echo "conflict branch 'bad' should not be pushed" >&2; exit 1 ;;
esac
grep -q '<<<<<<<' "$ws2/.claude/shared.txt" || {
  echo "expected conflict markers in shared.txt" >&2; exit 1;
}
