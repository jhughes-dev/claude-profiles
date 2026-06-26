#!/usr/bin/env bash
# Regression tests for the security hardening: component-name traversal guard
# (promote-component.sh) and repo-URL transport-helper guard (_lib.sh / callers).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# --- MED-1: promote-component.sh rejects path-traversal names ----------------
mkdir -p "$WORKSPACE/.claude/skills"
mkdir -p "$HOME/.claude/skills/realskill"
echo x > "$HOME/.claude/skills/realskill/SKILL.md"

for bad in ".." "../../etc" "a/b" "."; do
  if run_script promote-component.sh skill "$bad" move "$WORKSPACE" >/dev/null 2>&1; then
    echo "promote-component accepted traversal name: $bad" >&2; exit 1
  fi
done
# The user's real config must be untouched by the rejected 'move' attempts.
[ -d "$HOME/.claude/skills/realskill" ] || { echo "rejected move still deleted source!" >&2; exit 1; }

# A legitimate single-segment name still works.
out=$(run_script promote-component.sh skill realskill copy "$WORKSPACE" 2>&1)
assert_eq "$?" "0" "valid component name copies" || { echo "$out"; exit 1; }
[ -f "$WORKSPACE/.claude/skills/realskill/SKILL.md" ] || { echo "copy did not land" >&2; exit 1; }

# --- MED-2: repo-URL validation rejects transport-helper / option syntax -----
for safe in \
  "https://github.com/o/r.git" \
  "ssh://git@host/o/r.git" \
  "git@github.com:o/r.git" \
  "file:///tmp/p.git" \
  "/tmp/local.git" ; do
  pcfg_validate_repo "$safe" 2>/dev/null || { echo "rejected a safe repo URL: $safe" >&2; exit 1; }
done

for bad in \
  "ext::sh -c touch /tmp/pwned" \
  "fd::17/foo" \
  "-oProxyCommand=evil" \
  "" ; do
  if pcfg_validate_repo "$bad" 2>/dev/null; then
    echo "accepted an unsafe repo URL: $bad" >&2; exit 1
  fi
done

# write-config.sh refuses to store an ext:: URL.
if run_script write-config.sh "ext::sh -c id" >/dev/null 2>&1; then
  echo "write-config stored a transport-helper URL" >&2; exit 1
fi

# source.sh add validates BEFORE running ls-remote on the URL.
if run_script source.sh add evil "ext::sh -c id" >/dev/null 2>&1; then
  echo "source add accepted a transport-helper URL" >&2; exit 1
fi

# --- LOW: write-config redacts embedded credentials in its echo --------------
out=$(run_script write-config.sh "https://alice:s3cret@host/o/r.git" 2>&1)
assert_eq "$?" "0" "credentialed https URL is accepted" || { echo "$out"; exit 1; }
assert_contains "$out" "***" "password is redacted in output" || { echo "$out"; exit 1; }
case "$out" in *s3cret*) echo "password leaked in output: $out" >&2; exit 1 ;; esac
