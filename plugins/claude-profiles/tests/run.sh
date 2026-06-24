#!/usr/bin/env bash
# Run every test-*.sh in this directory. Each test script should exit 0 on
# success and non-zero on failure. Stdout from individual tests is shown only
# when they fail.
#
# Usage: bash tests/run.sh [pattern]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"
export PLUGIN_ROOT="$plugin_root"
pattern="${1:-test-*.sh}"

# shellcheck disable=SC2012
tests=$(ls "$here"/$pattern 2>/dev/null | sort)
if [ -z "$tests" ]; then
  echo "no tests matched pattern: $pattern"
  exit 1
fi

pass=0
fail=0
failed_names=()

for t in $tests; do
  name=$(basename "$t" .sh)
  out=$(bash "$t" 2>&1)
  rc=$?
  if [ "$rc" = "0" ]; then
    printf '  ok    %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s (exit %d)\n' "$name" "$rc"
    printf '%s\n' "$out" | sed 's/^/        /'
    fail=$((fail + 1))
    failed_names+=("$name")
  fi
done

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = "0" ]
