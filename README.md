# canudev

Interactively manage udev rules for CAN interfaces — static naming, auto-up, and bitrate — using nothing beyond bash, `ip`, `udevadm`, and `sha256sum`.

Currently supports USB-attached CAN adapters only — interfaces on other buses, such as SPI-based controllers like the MCP2515, can't be resolved to a stable physical location and won't be offered a static name.

## Requirements

- `bash`, `ip` (iproute2), `udevadm`, and `sha256sum` — present by default on most Linux distributions.
- Root privileges, to write `/etc/udev/rules.d/99-canbus.rules` and reload udev.
- A USB-attached CAN adapter (see the limitation above).

## Usage

Run it directly (root is required to write udev rules and reload them):

```sh
curl -fsSL https://raw.githubusercontent.com/threeal/canudev/main/canudev.sh | sudo bash
```

Or download it and run it locally:

```sh
curl -fsSLo canudev.sh https://raw.githubusercontent.com/threeal/canudev/main/canudev.sh
sudo bash canudev.sh
```

## How it works

canudev reads and regenerates a single file, `/etc/udev/rules.d/99-canbus.rules`. Each interface is keyed by its physical USB location (the `KERNELS` value udev matches on) rather than its current kernel-assigned name, so the same port keeps the same static name across reboots and however the kernel happens to enumerate interfaces this time.

The generated file starts with a comment recording a sha256 hash of everything below it, plus a config version marker, so canudev can tell on the next run whether the file is still one it wrote. Selecting an interface and entering a name rewrites the whole file from the current in-memory set of names, then reapplies the rename, bring-up, and bitrate immediately — you don't need to replug or reboot to see it take effect.

If canudev prints a warning on startup, it's because that check failed and it's about to start over with an empty mapping:

- `was modified outside canudev` — the file's hash no longer matches its contents, meaning it was hand-edited (or corrupted) since canudev last wrote it.
- `has no recognizable config version marker` / `has config version N, which this version of canudev doesn't know how to read` — the file's contents are intact, but canudev doesn't recognize their format, typically because the file was written by a different (older or newer) version of canudev.

In every case above, canudev doesn't try to salvage individual entries — the next name you assign rewrites the file from scratch, so any interfaces you'd previously configured will need to be renamed again through the interactive prompts.

## Development

Install [Lefthook](https://lefthook.dev/), [dprint](https://dprint.dev/), and [ShellCheck](https://www.shellcheck.net/), then register the pre-commit hook:

```sh
lefthook install
```

Before committing, run the pre-commit hook to fix formatting:

```sh
lefthook run pre-commit
```

If any file changes during the run, re-stage the changed files and retry. The hook also runs automatically on each `git commit` — if it fails, re-stage the changed files and commit again.

Install [bats-core](https://bats-core.readthedocs.io/) to run the test suite:

```sh
bats tests/
```

After committing, push to `main` or open a pull request from another branch — CI will run the pre-commit hook and the test suite across all files.

## License

This project is licensed under the [MIT License](LICENSE).
