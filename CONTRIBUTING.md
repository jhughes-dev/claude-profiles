# Contributing

This repo is the **claude-profiles plugin**. Issues and pull requests for the
plugin itself (commands, hooks, scripts, docs) are welcome.

- **Bugs / ideas:** open an issue describing the behavior you saw vs. expected.
- **Changes:** open a pull request. Please run the test suite first:

  ```bash
  bash plugins/claude-profiles/tests/run.sh
  ```

  CI runs the same suite on every push and pull request.

## Your profiles aren't here

This repo only contains the plugin. Your actual profiles live in a separate
repo that you own — run `/claude-profiles:init` to set one up. It can be any
git repo you control: an existing remote, a new one, or a fresh local bare
repo. Add, edit, and rearrange branches however you like — they're yours, and
nothing about them needs to come back here.
