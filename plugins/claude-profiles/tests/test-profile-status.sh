#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# missing .claude → state=missing, action=init
out=$(run_script profile-status.sh "$WORKSPACE")
assert_kv "$out" state missing "missing state" || exit 1
assert_kv "$out" action init "missing action" || exit 1

# .claude exists but not git → state=not_git
mkdir "$WORKSPACE/.claude"
out=$(run_script profile-status.sh "$WORKSPACE")
assert_kv "$out" state not_git "not_git state" || exit 1
assert_kv "$out" action opt_out_cleanup "opt_out action" || exit 1

# Real profile clone, in sync → state=ok, action=clean
rm -rf "$WORKSPACE/.claude"
repo=$(make_fake_profiles_repo)
git clone -q --branch main --single-branch "$repo" "$WORKSPACE/.claude"
out=$(run_script profile-status.sh "$WORKSPACE")
assert_kv "$out" state ok "ok state" || exit 1
assert_kv "$out" action clean "clean action" || exit 1
assert_kv "$out" branch main "branch name" || exit 1

# Add an uncommitted change → action=commit
echo dirty > "$WORKSPACE/.claude/scratch.txt"
out=$(run_script profile-status.sh "$WORKSPACE")
assert_kv "$out" dirty 1 "dirty flag" || exit 1
assert_kv "$out" action commit "commit action" || exit 1

# Commit it locally → action=push (ahead)
(cd "$WORKSPACE/.claude" && git config user.email t@t && git config user.name t \
  && git add -A && git commit -q -m wip)
out=$(run_script profile-status.sh "$WORKSPACE")
assert_kv "$out" action push "push action" || exit 1
assert_kv "$out" ahead 1 "ahead count" || exit 1
