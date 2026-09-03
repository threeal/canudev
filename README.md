# canudev

Interactively manage udev rules for CAN interfaces — static naming, auto-up, and bitrate — no dependencies beyond bash and `ip`.

## Usage

Run it directly:

```sh
curl -fsSL https://raw.githubusercontent.com/threeal/canudev/main/canudev.sh | bash
```

Or download it and run it locally:

```sh
curl -fsSLo canudev.sh https://raw.githubusercontent.com/threeal/canudev/main/canudev.sh
bash canudev.sh
```

## Development

Install [Lefthook](https://lefthook.dev/) and [dprint](https://dprint.dev/), then register the pre-commit hook:

```sh
lefthook install
```

Before committing, run the pre-commit hook to fix formatting:

```sh
lefthook run pre-commit
```

If any file changes during the run, re-stage the changed files and retry. The hook also runs automatically on each `git commit` — if it fails, re-stage the changed files and commit again.

After committing, push to `main` or open a pull request from another branch — CI will run the pre-commit hook across all files.

## License

This project is licensed under the [MIT License](LICENSE).
