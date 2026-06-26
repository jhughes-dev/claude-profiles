#!/usr/bin/env bash
# Detect a workspace's project traits to help suggest a fitting profile (issue #4).
# Prints one trait per line (e.g. rust, node, python). The set/init skills match
# these against available profile branch names and descriptions to recommend one.
# Usage: detect-project.sh [workspace]
set -uo pipefail

ws="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
emit() { printf '%s\n' "$1"; }
has() { [ -e "$ws/$1" ]; }
pkg_has() { [ -f "$ws/package.json" ] && grep -q "\"$1\"" "$ws/package.json" 2>/dev/null; }

# Languages / ecosystems
has Cargo.toml && emit rust
has go.mod && emit go
{ has pyproject.toml || has setup.py || has requirements.txt || has Pipfile; } && emit python
{ has pom.xml || ls "$ws"/*.gradle "$ws"/*.gradle.kts >/dev/null 2>&1; } && emit java
has Gemfile && emit ruby
has composer.json && emit php
has package.json && emit node

# Frameworks (Node ecosystem)
{ pkg_has next; } && emit nextjs
{ pkg_has nuxt || pkg_has vue; } && emit vue
{ pkg_has react && ! pkg_has next; } && emit react
{ pkg_has svelte; } && emit svelte

# App shells / domains
{ has src-tauri || has src-tauri/tauri.conf.json; } && emit tauri
{ has fabric.mod.json || has build.gradle && grep -rqi 'minecraft\|fabric\|forge' "$ws"/*.gradle* 2>/dev/null; } && emit minecraft
{ has .claude-plugin || has .claude-plugin/plugin.json || has plugin.json; } && emit claude-plugin
has Dockerfile && emit docker

exit 0
