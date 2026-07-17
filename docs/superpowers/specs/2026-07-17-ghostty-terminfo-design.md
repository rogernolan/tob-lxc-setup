# Ghostty Terminfo Installation Design

## Goal

Install the `xterm-ghostty` terminfo entry system-wide so terminal programs work correctly when Rog connects to a configured LXC from Ghostty, including when commands run through `sudo`.

## Source and packaging

The repository will carry Ghostty's canonical terminfo source as a payload under `files/`. A normal repository checkout will use that local payload. When only `setup.sh` is downloaded, the script will fetch the payload from the matching path on this repository's `main` branch, following the existing user-guidance payload fallback pattern.

The apt package list will include `ncurses-bin` so the `tic` compiler is explicitly available on supported Debian and Ubuntu hosts.

## Installation flow

After package installation, the setup script will locate or fetch the terminfo source, validate that it defines `xterm-ghostty`, and compile it with extended capabilities enabled. The compiled entry will be written beneath the configured root's `/usr/share/terminfo`, which corresponds to the system-wide database on a real host and remains isolated in fake-root tests.

Repeated runs will compile the same source to the same destination and converge without duplicate state. Dry-run mode will report the intended installation without fetching the fallback payload, creating files, or invoking `tic`.

Temporary downloaded payloads will use the script's existing cleanup mechanism. A failed download, invalid source, missing compiler, or failed compilation will stop setup with a clear error rather than claiming the host is configured.

## Testing

The fake-root integration suite will add a `tic` test double and verify that:

- `ncurses-bin` is included in the main apt installation.
- The local payload is compiled with extended capabilities into the fake system database.
- Two setup runs remain successful and target the same system-wide entry.
- A missing local payload is fetched from the repository fallback URL before compilation.
- Dry-run mode neither fetches nor compiles the terminfo payload.

The existing shell syntax checks and full fake-root suite remain the acceptance tests.

## Documentation

The README will list `ncurses-bin`, describe the installed `xterm-ghostty` entry, mention the terminfo payload among possible repository downloads, and retain the existing security boundary that downloaded data is validated and never executed as shell code.
