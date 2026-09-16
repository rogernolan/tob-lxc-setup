# Caddy Host Manager Remote Install Design

## Goal

Make `scripts/add-caddy-host` usable on the gateway without a local checkout,
following the main LXC setup's review-first and convenience-command patterns.
The normal documented path must install the command and then invoke the
installed copy. A separate direct-invocation path must remain available for
testing or emergency use when the remote command needs to change.

## Scope

- Add a repository-hosted remote installer wrapper for
  `scripts/add-caddy-host`.
- The installer downloads the Caddy command from the public raw GitHub URL —
  or consumes an already-inspected local file via `--payload` — validates the
  payload as the expected shell script, installs it atomically at
  `/usr/local/sbin/add-caddy-host` (destination root overridable via
  `CADDY_HOST_DEST_DIR` for tests), and invokes it with the caller's
  arguments.
- Update the Caddy section of `README.md` with review-first installation,
  install-and-run, and direct remote invocation examples.
- Extend the fake-root tests to cover installer syntax, argument forwarding,
  payload validation, and installation behavior without modifying the real
  host.

The existing gateway behavior, command-line arguments, Caddy configuration,
Cloudflare update, rollback, and local verification remain unchanged.

## Design

The new wrapper will be a POSIX shell script intended to be downloaded and
executed as root. It will use a configurable raw payload URL, defaulting to the
`main` branch's `scripts/add-caddy-host` file. It will:

1. Require root and fail clearly if `curl`, `mktemp`, or `install` is missing.
2. Download over HTTPS with `curl --fail --silent --show-error --location`,
   requiring TLS 1.2 or newer, or read the file given with `--payload` instead.
3. Validate that the temporary or supplied payload begins with the expected
   shell-script interpreter and contains the known command marker before
   installing it.
4. Install through a temporary file beside the destination (defaulting to
   `/usr/local/sbin`, overridable via `CADDY_HOST_DEST_DIR` so tests run
   against a fake root), then atomically move it into place with root
   ownership and mode `0755`.
5. Execute `/usr/local/sbin/add-caddy-host` with `exec`, preserving all
   arguments and the command's exit status.
6. Remove temporary files on every exit path and never print downloaded
   contents or environment variables containing Cloudflare credentials.

The wrapper will not modify Caddy or Cloudflare configuration itself; all
gateway changes remain in the installed command. It will not silently replace
the installed command on a failed download or failed payload validation.

## Documentation interface

The README will show:

- A review-first workflow that downloads the installer and command payloads to
  `/tmp`, displays them for inspection, then runs the installer with
  `--payload` so the exact inspected file is what gets installed.
- The primary convenience command that downloads and runs the installer,
  installing the command before forwarding `HOSTNAME`, `UPSTREAM`, and flags.
- A direct invocation command that streams the current `add-caddy-host` script
  into `sh -s --`, explicitly described as bypassing installation and intended
  for temporary changes or recovery.

Examples will preserve the existing HTTP and explicit insecure-upstream-TLS
forms, and will make the trust and root requirements visible.

## Failure handling and security

Downloads, validation, installation, and execution will use strict shell error
handling. A failed download or validation leaves the existing installed command
untouched. The installer will use a root-only temporary file and root-owned
destination. The raw URL will be HTTPS and pinned to the repository's public
`main` path, matching the existing LXC documentation convention; the README
will retain the warning that users should review remote code when supply-chain
review matters.

## Verification

- `bash -n`/`sh -n` for all shell scripts and the test script.
- Existing fake-root test suite, extended for the installer; tests intercept
  the absolute installed-command path by pointing `CADDY_HOST_DEST_DIR` at a
  fake directory, so nothing touches `/usr/local`.
- Tests proving a failed or malformed download does not replace an existing
  installed command.
- Documentation review ensuring the install-then-invoke path is primary and
  direct invocation is clearly secondary.

