#!/usr/bin/env bash
# Profile self-descriptions: author, cache, opportunistic capture, surface (#3).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

write_config "git@example.com:me/p.git"   # creates the default source

# write-profile-description writes the file and caches the description.
mkdir -p "$WORKSPACE/.claude"
git -C "$WORKSPACE/.claude" init -q -b rust-cli
run_script write-profile-description.sh "Rust CLI projects" "$WORKSPACE" >/dev/null
assert_eq "$(cat "$WORKSPACE/.claude/.profile-description")" "Rust CLI projects" "desc file written" || exit 1
assert_eq "$(pcfg_description rust-cli)" "Rust CLI projects" "desc cached" || exit 1

# cache-description reads an existing file (first non-empty, trimmed line).
rm -rf "$WORKSPACE/.claude"; mkdir -p "$WORKSPACE/.claude"
printf '   Web dev profile   \nignored second line\n' > "$WORKSPACE/.claude/.profile-description"
run_script cache-description.sh web-dev "$WORKSPACE" >/dev/null
assert_eq "$(pcfg_description web-dev)" "Web dev profile" "cache reads trimmed first line" || exit 1

# clone-profile opportunistically caches a branch's self-description.
bare="$TEST_TMP/descrepo.git"; git init --bare -q -b main "$bare"
seed="$TEST_TMP/descseed"; git init -q -b main "$seed"
(
  cd "$seed"; git config user.email t@t; git config user.name t
  echo readme > README.md; git add README.md; git commit -qm init
  git checkout -q -b cli-profile
  echo "CLI tooling profile" > .profile-description
  git add .profile-description; git commit -qm desc
  git push -q "$bare" main cli-profile
)
repo=$(normalize_path "$bare"); write_config "$repo"
rm -rf "$WORKSPACE/.claude"
run_script clone-profile.sh cli-profile "" "$WORKSPACE" >/dev/null 2>&1
assert_eq "$(pcfg_description cli-profile)" "CLI tooling profile" "clone cached description" || exit 1

# list-branches --by-source surfaces the cached description.
out=$(run_script list-branches.sh --by-source)
assert_contains "$out" "$(printf 'default\tcli-profile\tCLI tooling profile')" "by-source shows description" || exit 1
