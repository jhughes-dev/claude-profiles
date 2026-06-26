#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_helpers.sh"
test_setup; trap test_teardown EXIT

# 1) Seed from the plugin's bundled starter (default starter dir, no network).
target="$TEST_TMP/target.git"
out=$(run_script seed-local-repo.sh "$target" 2>&1)
rc=$?
assert_eq "$rc" "0" "exit 0 seeding from bundled starter" || { echo "$out"; exit 1; }
assert_contains "$out" "main, template" "reports seeded branches" || exit 1

heads=$(git ls-remote --heads "$target" | awk '{sub("refs/heads/","",$2); print $2}')
assert_contains "$heads" "main" "main seeded" || exit 1
assert_contains "$heads" "template" "template seeded" || exit 1

# The template branch carries the starter profile content (incl. dotfiles).
desc=$(git -C "$target" show template:.profile-description 2>/dev/null)
assert_contains "$desc" "template" "template has .profile-description" || exit 1
git -C "$target" cat-file -e template:CLAUDE.md 2>/dev/null \
  || { echo "template missing CLAUDE.md" >&2; exit 1; }
git -C "$target" cat-file -e template:.gitignore 2>/dev/null \
  || { echo "template missing .gitignore" >&2; exit 1; }
git -C "$target" cat-file -e main:README.md 2>/dev/null \
  || { echo "main missing README.md" >&2; exit 1; }

# 2) A custom starter dir is honored.
custom="$TEST_TMP/custom"
mkdir -p "$custom/main" "$custom/template"
echo landing > "$custom/main/README.md"
echo custom-template > "$custom/template/CLAUDE.md"
target2="$TEST_TMP/target2.git"
out2=$(run_script seed-local-repo.sh "$target2" "$custom" 2>&1)
rc2=$?
assert_eq "$rc2" "0" "exit 0 with custom starter" || { echo "$out2"; exit 1; }
got=$(git -C "$target2" show template:CLAUDE.md 2>/dev/null)
assert_eq "$got" "custom-template" "custom template content seeded" || exit 1

# 3) Missing starter content → non-zero (no branches to seed from).
if run_script seed-local-repo.sh "$TEST_TMP/target3.git" "$TEST_TMP/nope" >/dev/null 2>&1; then
  echo "expected non-zero when starter dir missing" >&2; exit 1
fi

# 4) When a push genuinely fails, the script must report failure rather than
#    silently exit 0. Force a non-fast-forward by giving the target a diverging
#    `main` first (deterministic — no reliance on commit-timestamp differences).
busy="$TEST_TMP/busy.git"
git init -q --bare -b main "$busy"
seedwc="$TEST_TMP/seedwc"
git init -q -b main "$seedwc"
( cd "$seedwc" && git config user.email t@t && git config user.name t \
  && echo diverging > x && git add x && git commit -q -m other && git push -q "$busy" main )
if run_script seed-local-repo.sh "$busy" >/dev/null 2>&1; then
  echo "seeding over a diverging branch should fail, not report success" >&2; exit 1
fi
