#!/usr/bin/env bash
# Initialize a bare repo at <path> (if missing) and seed it with `main` and
# `template` from the upstream repo.
#
# Usage: seed-local-repo.sh <bare-path> <upstream-url>
set -uo pipefail

path="${1:?usage: seed-local-repo.sh <bare-path> <upstream-url>}"
upstream="${2:?usage: seed-local-repo.sh <bare-path> <upstream-url>}"

if [ ! -d "$path" ]; then
  git init --bare "$path" >/dev/null
fi

# Probe upstream for the branches we care about before cloning.
remote_heads=$(git ls-remote --heads "$upstream" 2>/dev/null | awk '{sub("refs/heads/","",$2); print $2}')
if [ -z "$remote_heads" ]; then
  echo "could not list branches on $upstream — is it reachable?" >&2
  exit 1
fi
have_main=0
have_template=0
printf '%s\n' "$remote_heads" | grep -qx main     && have_main=1
printf '%s\n' "$remote_heads" | grep -qx template && have_template=1

if [ "$have_main" = "0" ]; then
  echo "WARNING: upstream $upstream has no 'main' branch — skipping." >&2
fi
if [ "$have_template" = "0" ]; then
  echo "WARNING: upstream $upstream has no 'template' branch. /claude-profiles:set --new will not work until you create one (e.g. push the desired starter content as 'template' to your profiles repo)." >&2
fi
if [ "$have_main" = "0" ] && [ "$have_template" = "0" ]; then
  echo "nothing to seed from $upstream" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$upstream" "$tmp/src" >/dev/null

refs=""
[ "$have_main" = "1" ]     && refs="$refs main:main"
[ "$have_template" = "1" ] && {
  git -C "$tmp/src" fetch -q origin template:template 2>/dev/null || true
  refs="$refs template:template"
}

# shellcheck disable=SC2086
git -C "$tmp/src" push "$path" $refs

seeded=$(printf '%s' "$refs" | sed -e 's/^ *//' -e 's/ /, /g' -e 's/:[^,]*//g')
echo "seeded $path with: $seeded (from $upstream)"
