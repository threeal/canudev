# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Repository

canudev is a single, dependency-light bash script (`canudev.sh`) that interactively manages udev rules for CAN interfaces, and must be run as root (e.g. `curl -fsSL <url> | sudo bash`). See `canudev.sh` for implementation details.

## Tooling

### bats

Test framework for `canudev.sh` via `tests/canudev.bats`. Tests source the script directly — the trailing `main "$@"` call is guarded by a `BASH_SOURCE`/`$0` check so sourcing doesn't run the interactive loop — and stub external commands like `ip` and `udevadm` as plain bash functions rather than mocking via `PATH`.

### Dependabot

Keeps GitHub Actions dependencies up to date automatically via `.github/dependabot.yaml`.

### dprint

Formatter for JSON, Markdown, and YAML files via `dprint.json`.

### GitHub Actions

Automates CI. Workflow files:

- **`.github/workflows/ci.yaml`** — Triggers on push to `main`, pull requests, and manual dispatch. Runs `lefthook run pre-commit --all-files` to validate formatting and lint, and `bats tests/` to run the test suite.

### Lefthook

Git hook manager configured in `lefthook.yaml`. The pre-commit hook:

- Fixes formatting with `dprint fmt`.
- Lints `canudev.sh` with `shellcheck`.

## Checking and Fixing

Run the pre-commit hook:

```sh
lefthook run pre-commit              # staged files only (default)
lefthook run pre-commit --all-files  # all files — matches what CI runs
```

If any file changes during the run, re-stage the changed files and retry.

## Testing

Run the test suite (requires [bats-core](https://github.com/bats-core/bats-core)):

```sh
bats tests/
```
