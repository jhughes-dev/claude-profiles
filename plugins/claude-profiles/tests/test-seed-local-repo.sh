#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# Build an "upstream" with only main (no template) to exercise the warning.
upstream="$TEST_TMP/upstream.git"
git init -q --bare -b main "$upstream"
seed="$TEST_TMP/seed"
git init -q -b main "$seed"
(cd "$seed" && git config user.email t@t && git config user.name t \
  && echo hi > f && git add f && git commit -q -m init && git push -q "$upstream" main)

target="$TEST_TMP/target.git"
out=$(run_script seed-local-repo.sh "$target" "$upstream" 2>&1)
rc=$?
assert_eq "$rc" "0" "exit 0 when at least main present" || { echo "$out"; exit 1; }
assert_contains "$out" "WARNING" "warning emitted for missing template" || exit 1
assert_contains "$out" "template" "warning mentions template" || exit 1

# Confirm main was actually pushed into target.
heads=$(git ls-remote --heads "$target" | awk '{sub("refs/heads/","",$2); print $2}')
assert_contains "$heads" "main" "main seeded" || exit 1
case "$heads" in *template*) echo "template should not exist" >&2; exit 1 ;; esac

# Now build an upstream with neither branch → seed-local-repo refuses.
upstream2="$TEST_TMP/upstream2.git"
git init -q --bare -b main "$upstream2"
target2="$TEST_TMP/target2.git"
if run_script seed-local-repo.sh "$target2" "$upstream2" >/dev/null 2>&1; then
  echo "expected non-zero when upstream has no branches" >&2; exit 1
fi
