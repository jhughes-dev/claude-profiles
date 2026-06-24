#!/usr/bin/env bash
# Shared helpers for tests. `source` this; do not run.

# PLUGIN_ROOT is set by run.sh.
: "${PLUGIN_ROOT:?PLUGIN_ROOT not set — run via tests/run.sh}"

# shellcheck source=../scripts/_lib.sh
. "$PLUGIN_ROOT/scripts/_lib.sh"

# Set up a clean throwaway HOME and workspace for each test, so that ~/.claude*
# files written by scripts/hooks don't leak into the real home dir.
test_setup() {
  TEST_TMP=$(mktemp -d)
  export HOME="$TEST_TMP/home"
  # Isolate the XDG config dir to the throwaway HOME so the JSON config lands
  # under it (and never touches the real ~/.config).
  unset XDG_CONFIG_HOME
  mkdir -p "$HOME"
  # Give the throwaway HOME a global git identity, so repos created by the
  # scripts under test (e.g. the .claude clones) can commit. Mirrors a real
  # user who has `git config --global user.{name,email}` set.
  git config --global user.email t@t
  git config --global user.name t
  WORKSPACE="$TEST_TMP/workspace"
  mkdir -p "$WORKSPACE"
  export WORKSPACE
  export CLAUDE_PROJECT_DIR="$WORKSPACE"
}

test_teardown() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# Run a script under the plugin and capture stdout.
run_script() {
  local script="$1"
  shift
  bash "$PLUGIN_ROOT/scripts/$script" "$@"
}

# Assert exact equality. Usage: assert_eq <actual> <expected> <description>
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  printf 'assertion failed (%s):\n  expected: %s\n  actual:   %s\n' "$3" "$2" "$1" >&2
  return 1
}

# Assert a key=value line is present in the input.
# Usage: assert_kv <kv-output> <key> <expected-value> <description>
assert_kv() {
  local actual
  actual=$(printf '%s\n' "$1" | sed -n "s/^${2}=//p" | head -n1)
  assert_eq "$actual" "$3" "$4"
}

# Assert a substring is present.
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf 'assertion failed (%s):\n  expected substring: %s\n  in:                 %s\n' "$3" "$2" "$1" >&2
  return 1
}

# Normalize a filesystem path to a form git will return (resolves MSYS→Windows).
normalize_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

# Initialize a bare repo with a `template` and `main` branch — usable as a
# fake profiles repo. Echoes the path to the bare repo.
make_fake_profiles_repo() {
  local bare="$TEST_TMP/profiles.git"
  git init --bare -q -b main "$bare"
  local seed="$TEST_TMP/seed"
  git init -q -b main "$seed"
  (
    cd "$seed"
    git config user.email t@t
    git config user.name t
    echo seed > README.md
    git add README.md
    git commit -q -m init
    git branch template
    git push -q "$bare" main template
  )
  rm -rf "$seed"
  normalize_path "$bare"
}

# Write a minimal profiles config pointing at the given repo (current format).
write_config() {
  pcfg_set_repo "$1"
}

# Write a legacy (pre-1.x) key=value global config, for migration tests.
write_legacy_config() {
  local repo="$1" branches="${2:-}"
  {
    printf 'repo=%s\n' "$repo"
    [ -n "$branches" ] && printf 'branches=%s\n' "$branches"
  } > "$HOME/.claude-profiles-config"
}
