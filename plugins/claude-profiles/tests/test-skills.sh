#!/usr/bin/env bash
# Structural checks for the command->skill port (issue #8).
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"

root="$PLUGIN_ROOT"
fail=0

# Commands were ported to skills; the commands/ dir should be gone.
[ ! -d "$root/commands" ] || { echo "commands/ should not exist (ported to skills)" >&2; fail=1; }

# Every skill has frontmatter + a description. Driven from the directory so new
# skills are covered automatically (a missing description fails marketplace
# acceptance).
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || { echo "no skills found under $root/skills" >&2; fail=1; break; }
  s=$(basename "$(dirname "$f")")
  head -1 "$f" | grep -q '^---' || { echo "$s: missing frontmatter" >&2; fail=1; }
  grep -q '^description:' "$f" || { echo "$s: missing description" >&2; fail=1; }
done

# Side-effecting actions are explicit-only; status/configure stay model-invocable.
for s in init set update source describe; do
  grep -q '^disable-model-invocation: true' "$root/skills/$s/SKILL.md" \
    || { echo "$s: expected disable-model-invocation: true" >&2; fail=1; }
done
if grep -q '^disable-model-invocation:' "$root/skills/status/SKILL.md"; then
  echo "status should remain model-invocable (no disable-model-invocation)" >&2; fail=1
fi

exit $fail
