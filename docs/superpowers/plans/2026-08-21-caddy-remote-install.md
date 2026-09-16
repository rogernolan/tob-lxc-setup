# Caddy Remote Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or **superpowers:executing-plans** to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add a safe remote installer for the Caddy host manager and document install-then-invoke as the normal gateway workflow, while retaining direct remote invocation.

**Architecture:** Add scripts/install-caddy-host as a small POSIX bootstrapper. It downloads scripts/add-caddy-host to a root-only temporary file (or consumes an already-inspected local file via --payload), validates the expected payload, installs it atomically as /usr/local/sbin/add-caddy-host (destination root overridable for tests), and execs that installed command with unchanged arguments. Keep all gateway behavior in scripts/add-caddy-host; test the installer independently with command stubs and update the Caddy README section with review-first, primary, and fallback commands.

**Tech Stack:** POSIX sh, curl, mktemp, install, mv, awk/grep, Bash test harness, Markdown.

## Global Constraints

- The installer is POSIX shell and must require root.
- Default payload URL: https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/add-caddy-host.
- Downloads use curl --fail --silent --show-error --location --proto '=https' --tlsv1.2.
- Failed downloads or payload validation leave an existing installed command untouched.
- The installed command is $CADDY_HOST_DEST_DIR/add-caddy-host, defaulting to /usr/local/sbin/add-caddy-host, owned by root with mode 0755. CADDY_HOST_DEST_DIR exists so tests run against a fake root; it is not part of the documented operator workflow.
- --payload FILE installs and executes an already-downloaded, inspected copy instead of downloading; the review-first workflow uses it so the inspected file is what gets installed.
- The installer forwards all original arguments and exit status with exec.
- Do not print downloaded payloads, Cloudflare credentials, or secret-bearing environment variables.
- Existing scripts/add-caddy-host behavior is out of scope.
- Primary documentation must install and then invoke; direct streaming is explicitly secondary.

---

### Task 1: Add the remote installer script

**Files:**
- Create: scripts/install-caddy-host

**Interfaces:**
- Consumes: optional --payload FILE, optional CADDY_HOST_PAYLOAD_URL and CADDY_HOST_DEST_DIR, and command-line arguments for add-caddy-host.
- Produces: $CADDY_HOST_DEST_DIR/add-caddy-host (default /usr/local/sbin/add-caddy-host), then executes it with the same arguments.

- [ ] Write a POSIX script with set -eu, root checking, command checks for curl/mktemp/install, EXIT/HUP/INT/TERM cleanup, and a configurable payload URL defaulting to the raw GitHub URL.
- [ ] Download to a temporary file with curl --fail --silent --show-error --location --proto '=https' --tlsv1.2, or use the file given with --payload. Validate the first line is #!/bin/sh and that the payload contains set -eu before changing the installed command.
- [ ] Create a temporary file beside the destination, install the payload there with root:root and 0755, then mv it into place. Do not use tee or write directly to the destination.
- [ ] Execute the destination with exec "$destination" "$@".
- [ ] Run sh -n scripts/install-caddy-host; expect exit status 0.
- [ ] Commit with git add scripts/install-caddy-host and git commit -m 'feat: add remote caddy host installer'.

### Task 2: Add isolated installer tests

**Files:**
- Create: tests/test_caddy_remote.sh
- Modify: README.md verification section

**Interfaces:**
- Consumes: scripts/install-caddy-host, CADDY_HOST_PAYLOAD_URL, CADDY_HOST_DEST_DIR, temporary fake bin/destination directories.
- Produces: repeatable assertions for successful installation, local-payload installation, exact argument forwarding, and failed-payload preservation.

- [ ] Create a Bash test harness using mktemp -d and a trap. It must not require root, alter /usr/local, or contact GitHub.
- [ ] Stub id, curl, install, mv, rm, dirname, head, and grep through a fake PATH. Point CADDY_HOST_DEST_DIR at a fake directory and place an executable add-caddy-host stub there, so the absolute installed-command path is intercepted. The curl stub writes a valid payload and records the URL.
- [ ] Add a success test that asserts the installed file in the fake destination is executable, the default raw URL was requested, and the installed payload receives exactly: --force app.hatbat.net http://192.168.68.20:8080.
- [ ] Add a --payload test that passes a local file and asserts no URL was requested and the local bytes are what get installed and executed.
- [ ] Add malformed-payload and download-failure tests. Seed an existing fake destination with OLD-CONTENT and assert the installer fails while preserving those exact bytes.
- [ ] Run bash tests/test_caddy_remote.sh. Expected final output: PASS: caddy remote installer tests.
- [ ] Extend README verification with bash -n setup.sh tests/test_setup.sh, sh -n scripts/add-caddy-host scripts/install-caddy-host, bash tests/test_setup.sh, and bash tests/test_caddy_remote.sh.
- [ ] Commit with git add tests/test_caddy_remote.sh README.md and git commit -m 'test: cover remote caddy host installation'.

### Task 3: Document remote installation and direct invocation

**Files:**
- Modify: README.md Caddy host manager section

**Interfaces:**
- Consumes: raw GitHub URLs for scripts/install-caddy-host and scripts/add-caddy-host.
- Produces: copy/pasteable gateway commands with install-then-invoke as the main path.

- [ ] Add a review-first workflow that downloads both scripts to /tmp, displays them with less, runs sudo sh /tmp/install-caddy-host.sh --payload /tmp/add-caddy-host.sh app.hatbat.net http://192.168.68.20:8080 so the exact inspected payload is installed, and removes the temporary files.
- [ ] Add the primary convenience command: curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 URL-of-install-caddy-host | sudo sh -s -- app.hatbat.net http://192.168.68.20:8080. Explain that the installer downloads, installs, and invokes the Caddy command.
- [ ] Include the existing explicit insecure-upstream-TLS example through the install-and-run path.
- [ ] Add a clearly secondary direct invocation fallback using URL-of-add-caddy-host | sudo sh -s -- app.hatbat.net http://192.168.68.20:8080. State that it bypasses installation and does not update /usr/local/sbin/add-caddy-host.
- [ ] Run bash -n setup.sh tests/test_setup.sh; sh -n scripts/add-caddy-host scripts/install-caddy-host; bash tests/test_setup.sh; bash tests/test_caddy_remote.sh; and git diff --check. Expect all tests to pass and shell checks to be silent.
- [ ] Commit with git add README.md and git commit -m 'docs: document remote caddy host workflows'.

## Final Review

- Confirm the normal README path installs /usr/local/sbin/add-caddy-host before invoking it.
- Confirm the review-first workflow installs the exact inspected payload via --payload.
- Confirm direct invocation is present but explicitly secondary.
- Confirm failed download or validation cannot replace an existing command.
- Confirm tests do not require root, network access, Caddy, systemd, or Cloudflare credentials, and run entirely under the fake destination.
- Confirm no unrelated .DS_Store files are staged.
