#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# version_gt: strictly-greater dotted-numeric comparison.
version_gt 1.0.1 1.0.0   || { echo "1.0.1 > 1.0.0 failed" >&2; exit 1; }
version_gt 1.2.0 1.1.9   || { echo "1.2.0 > 1.1.9 failed" >&2; exit 1; }
version_gt 2.0.0 1.9.9   || { echo "2.0.0 > 1.9.9 failed" >&2; exit 1; }
version_gt 1.10.0 1.2.0  || { echo "1.10.0 > 1.2.0 (numeric) failed" >&2; exit 1; }
! version_gt 1.0.0 1.0.0 || { echo "equal must not be greater" >&2; exit 1; }
! version_gt 1.0.0 1.0.1 || { echo "older must not be greater" >&2; exit 1; }
! version_gt 1.0.0 2.0.0 || { echo "older major must not be greater" >&2; exit 1; }

# latest_release_version: highest claude-profiles--vX.Y.Z tag on a repo.
bare="$TEST_TMP/plugin.git"
git init --bare -q -b main "$bare"
seed="$TEST_TMP/pseed"; git init -q -b main "$seed"
(
  cd "$seed"
  git config user.email t@t; git config user.name t
  echo x > f; git add f; git commit -q -m init
  git tag claude-profiles--v1.0.0
  git tag claude-profiles--v1.2.0
  git tag claude-profiles--v1.10.0   # 1.10.0 must beat 1.2.0 (numeric, not lexical)
  git tag other-plugin--v9.9.9       # unrelated tags ignored
  git push -q "$bare" main --tags
)
got=$(latest_release_version "$(normalize_path "$bare")")
assert_eq "$got" "1.10.0" "latest release tag (numeric sort, filtered)" || exit 1

# No release tags → empty.
empty="$TEST_TMP/empty.git"; git init --bare -q -b main "$empty"
got=$(latest_release_version "$(normalize_path "$empty")")
assert_eq "$got" "" "no tags → empty" || exit 1
