#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# No config at all → exits non-zero
if run_script list-branches.sh >/dev/null 2>&1; then
  echo "expected non-zero exit with no config" >&2; exit 1
fi

repo=$(make_fake_profiles_repo)
write_config "$repo"

# Add a few extra branches to the bare repo (with template excluded from output).
seed=$(mktemp -d)
git clone -q "$repo" "$seed"
git -C "$seed" config user.email t@t
git -C "$seed" config user.name t
git -C "$seed" branch rust-cli main
git -C "$seed" branch web-dev main
git -C "$seed" push -q "$repo" rust-cli web-dev

out=$(run_script list-branches.sh)
# Should include main, rust-cli, web-dev; never template.
assert_contains "$out" "main" "main listed" || { rm -rf "$seed"; exit 1; }
assert_contains "$out" "rust-cli" "rust-cli listed" || { rm -rf "$seed"; exit 1; }
assert_contains "$out" "web-dev" "web-dev listed" || { rm -rf "$seed"; exit 1; }
case "$out" in *template*) echo "template should be excluded" >&2; rm -rf "$seed"; exit 1 ;; esac
rm -rf "$seed"
