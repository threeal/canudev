# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Repository

canudev is a single, dependency-light bash script (`canudev.sh`) that interactively manages udev rules for CAN interfaces, and must be run as root (e.g. `curl -fsSL <url> | sudo bash`). See `canudev.sh` for implementation details.

## Tooling

### Dependabot

Keeps GitHub Actions dependencies up to date automatically via `.github/dependabot.yaml`.

### dprint

Formatter for JSON, Markdown, and YAML files via `dprint.json`.

### GitHub Actions

Automates CI. Workflow files:

- **`.github/workflows/ci.yaml`** — Triggers on push to `main`, pull requests, and manual dispatch. Runs `lefthook run pre-commit --all-files` to validate formatting.

### Lefthook

Git hook manager configured in `lefthook.yaml`. The pre-commit hook:

- Fixes formatting with `dprint fmt`.

## Checking and Fixing

Run the pre-commit hook:

```sh
lefthook run pre-commit              # staged files only (default)
lefthook run pre-commit --all-files  # all files — matches what CI runs
```

If any file changes during the run, re-stage the changed files and retry.
