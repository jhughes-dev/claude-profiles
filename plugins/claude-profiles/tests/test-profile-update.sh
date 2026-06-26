#!/usr/bin/env bash
# Exercise profile-update.sh — the destructive engine behind /claude-profiles:update.
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

bare=$(make_fake_profiles_repo)        # main + template, one commit with README.md
ws="$WORKSPACE"; dir="$ws/.claude"
git clone -q --branch main "$bare" "$dir"
( cd "$dir" && git config user.email t@t && git config user.name t )

# A second working clone used to advance the remote independently.
other="$TEST_TMP/other"
git clone -q --branch main "$bare" "$other"
( cd "$other" && git config user.email t@t && git config user.name t )

# 1) In sync → clean.
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action clean "in sync -> clean" || { echo "$out"; exit 1; }

# 2) Dirty tree → needs_commit (and nothing is pushed).
echo change > "$dir/README.md"
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action needs_commit "dirty -> needs_commit" || { echo "$out"; exit 1; }
git -C "$dir" checkout -q -- README.md

# 3) Ahead → pushed, and the bare repo actually advances.
echo local > "$dir/local.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "local 1"
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action pushed "ahead -> pushed" || { echo "$out"; exit 1; }
git -C "$bare" cat-file -e main:local.txt 2>/dev/null \
  || { echo "push did not reach the bare repo" >&2; exit 1; }

# 4) Behind → pulled (fast-forward).
( cd "$other" && git pull -q && echo remote > remote.txt \
  && git add -A && git commit -q -m "remote 1" && git push -q origin main )
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action pulled "behind -> pulled" || { echo "$out"; exit 1; }
[ -f "$dir/remote.txt" ] || { echo "pull did not bring remote.txt" >&2; exit 1; }

# 5) Diverged on different files → rebased_pushed.
echo local2 > "$dir/local2.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "local 2"
( cd "$other" && git pull -q && echo remote2 > remote2.txt \
  && git add -A && git commit -q -m "remote 2" && git push -q origin main )
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action rebased_pushed "diverged (no conflict) -> rebased_pushed" || { echo "$out"; exit 1; }

# 6) Diverged on the same file → needs_resolve with a populated conflicts list.
echo localside > "$dir/conflict.txt"
git -C "$dir" add -A && git -C "$dir" commit -q -m "local conflict"
( cd "$other" && git pull -q && echo remoteside > conflict.txt \
  && git add -A && git commit -q -m "remote conflict" && git push -q origin main )
out=$(run_script profile-update.sh "$ws")
assert_kv "$out" action needs_resolve "same-file diverge -> needs_resolve" || { echo "$out"; exit 1; }
assert_contains "$out" "conflict.txt" "conflicts list names the file" || { echo "$out"; exit 1; }
git -C "$dir" rebase --abort 2>/dev/null || true
