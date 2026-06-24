#!/usr/bin/env bash
# Multi-source support (issue #1).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

repoA=$(make_repo_with_branches A rust-cli web-dev)
repoB=$(make_repo_with_branches B rust-cli internal)

# Add first source (default), then a second.
run_script source.sh add personal "$repoA" --default >/dev/null
run_script source.sh add work "$repoB" >/dev/null
assert_eq "$(pcfg_sources | paste -sd, -)" "personal,work" "two sources" || exit 1
assert_eq "$(pcfg_default_source_name)" "personal" "personal is default" || exit 1
assert_eq "$(pcfg_source_repo work)" "$repoB" "work repo recorded" || exit 1

# list-branches --by-source labels each branch with its source (template excluded).
out=$(run_script list-branches.sh --by-source)
assert_contains "$out" "$(printf 'personal\trust-cli')" "personal:rust-cli listed" || exit 1
assert_contains "$out" "$(printf 'work\tinternal')" "work:internal listed" || exit 1
case "$out" in *template*) echo "template should be excluded" >&2; exit 1 ;; esac

# Branch caches populated on add → disambiguation works off the cache.
assert_eq "$(pcfg_find_sources_for_branch rust-cli | sort | paste -sd, -)" "personal,work" "rust-cli in both" || exit 1
assert_eq "$(pcfg_find_sources_for_branch internal)" "work" "internal only in work" || exit 1

# Default source drives the back-compat active repo; override flips it.
assert_eq "$(pcfg_active_repo)" "$repoA" "active = default (personal) repo" || exit 1
assert_eq "$( (export CLAUDE_PROFILES_SOURCE=work; pcfg_active_repo) )" "$repoB" "override → work repo" || exit 1

# Switch default.
run_script source.sh default work >/dev/null
assert_eq "$(pcfg_default_source_name)" "work" "default switched to work" || exit 1
assert_eq "$(pcfg_active_repo)" "$repoB" "active follows new default" || exit 1

# write-marker records the active source.
( export CLAUDE_PROFILES_SOURCE=personal
  run_script write-marker.sh rust-cli "$WORKSPACE" >/dev/null )
got=$(cat "$WORKSPACE/.claude-profiles")
assert_contains "$got" '"source": "personal"' "marker records resolved source" || exit 1
assert_contains "$got" "$repoA" "marker records that source's repo" || exit 1

# clone-profile honors the active source (clones from work's repo).
rm -rf "$WORKSPACE/.claude"
( export CLAUDE_PROFILES_SOURCE=work
  run_script clone-profile.sh internal "" "$WORKSPACE" >/dev/null 2>&1 )
assert_eq "$(git -C "$WORKSPACE/.claude" remote get-url origin)" "$repoB" "cloned from work's repo" || exit 1

# Removing the default source reassigns a new default.
run_script source.sh remove work >/dev/null
assert_eq "$(pcfg_sources)" "personal" "work removed" || exit 1
assert_eq "$(pcfg_default_source_name)" "personal" "default reassigned to remaining source" || exit 1
