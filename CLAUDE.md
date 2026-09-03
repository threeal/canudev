# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Repository

canudev is a single, dependency-light bash script (`canudev.sh`) that interactively manages udev rules for CAN interfaces. It's meant to be run either after cloning or directly via `curl -fsSL <url> | bash`, and it works by reading, adding to, and rewriting marked blocks in `/etc/udev/rules.d/99-canbus.rules` — one block per physical CAN interface — covering static naming (via `KERNELS`), auto-bring-up, and bitrate configuration.

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
