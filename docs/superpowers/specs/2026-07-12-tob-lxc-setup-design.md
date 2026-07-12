# TOB LXC Setup Design

## Goal

Create a small, auditable, idempotent setup script for Debian and Ubuntu LXC guests running under Proxmox. It should install common administration and development tools, create the `rog` administrator account, configure SSH access from the user's public GitHub keys, and enable useful services with safe defaults.

## Scope and assumptions

- Supported operating systems: Debian and Ubuntu only, using `apt` and `systemd` where available.
- Repository name: `tob-lxc-setup`.
- Expected GitHub owner: `rogernolan`.
- The repository is intended to be public so the script can be fetched without credentials.
- The script is run as root on a host that has network access to Debian/Ubuntu package mirrors and GitHub.
- The initial implementation is shell-only; Ansible is deliberately deferred.

## User-facing behavior

The primary entry point is `setup.sh`. It will:

1. Require Bash and root privileges.
2. Detect and validate Debian or Ubuntu using `/etc/os-release`; fail before making changes on unsupported systems.
3. Refresh package metadata and upgrade installed packages.
4. Install Git, OpenSSH client/server, curl, jq, ripgrep, tmux, sudo, Avahi, Node.js/npm, and the Codex CLI. Package names and the current supported Codex installation method will be verified against current vendor documentation during implementation.
5. Create `rog` if absent; preserve an existing account and home directory; add the user to the distro's administrative group (`sudo` on Debian/Ubuntu).
6. Install a dedicated `/etc/sudoers.d/rog` entry with correct ownership and mode, validated with `visudo`. The entry grants administrative capability without modifying unrelated sudo policy.
7. Obtain SSH public keys from `https://github.com/rogernolan.keys` by default, or from an explicitly supplied local public-key file. Validate supported OpenSSH public-key lines, install them idempotently in `/home/rog/.ssh/authorized_keys`, and apply restrictive ownership and permissions.
8. Install the user guidance payload from `files/rog/AGENTS.md` as `/home/rog/AGENTS.md`, preserving an identical existing file unless an explicit overwrite option is introduced.
9. Enable and start `ssh`/`sshd` and `avahi-daemon` when the services are present and systemd is available; otherwise report the skipped service action without treating it as a package-install failure.
10. Leave firewall policy, SSH password policy, hostname, locale, timezone, and shell customization unchanged.

Supported options:

- `--github-user USER`: override the default GitHub username.
- `--ssh-public-key-file FILE`: use a local public-key file instead of GitHub.
- `--no-ssh-key`: create/configure the user without installing a key.
- `--dry-run`: print planned actions without changing the system.
- `--help`: print usage.

The script will not silently create an SSH account with no usable key unless `--no-ssh-key` is explicitly selected. A GitHub or local-key failure is fatal so a partially provisioned remote-login path is not mistaken for a successful setup.

## Security and idempotency

- Use `set -Eeuo pipefail`, a predictable `PATH`, and quoted variables.
- Never execute downloaded shell content. Remote data is limited to public-key text and is validated line-by-line.
- Use `curl --fail --silent --show-error --location --proto '=https' --tlsv1.2` for GitHub key retrieval.
- Use `DEBIAN_FRONTEND=noninteractive` only for apt operations and preserve apt's normal error behavior.
- Make repeated runs converge: package installs, user/group membership, sudoers, authorized keys, and service state should not duplicate or overwrite unrelated configuration.
- Refuse unsafe key-file permissions only where doing so prevents accidental use of a private key; accept normal public-key file modes.
- Do not log passwords, tokens, private keys, or complete environment contents.

## Repository layout

- `setup.sh`: single executable entry point and all setup logic.
- `files/rog/AGENTS.md`: user-home guidance installed for the `rog` account.
- `README.md`: prerequisites, one-line fetch command, local invocation examples, supported distributions, options, and security notes.
- `tests/setup.bats`: shell-level tests using a fake root and stubbed commands for argument parsing, OS rejection, idempotency-sensitive file generation, and key validation.
- `docs/superpowers/specs/...`: approved design documentation.
- `docs/superpowers/plans/...`: implementation plan.

When `setup.sh` is streamed from the documented raw GitHub URL, it will fetch the user guidance payload from the matching raw URL, validate its expected `AGENTS.md` heading, and install it without executing it. Local runs use the tracked payload directly.

## One-line installation

After the public repository is available on GitHub, the documented command will be:

```sh
curl -fsSL https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/setup.sh | sudo bash -s -- --github-user rogernolan
```

The README will recommend downloading and reviewing the script first for hosts where supply-chain review is important. The command is a convenience for trusted homelab use, not a replacement for reviewing changes to the repository.

## Testing and verification

- Test script behavior without modifying the development machine by stubbing apt, systemctl, curl, getent, user/group tools, and `visudo` behind a temporary fake root.
- Verify the script parses with `bash -n` and passes ShellCheck when available.
- Run tests twice where applicable to demonstrate idempotent output and absence of duplicate keys or sudoers entries.
- Run a final repository diff/status check and document any checks unavailable in the local environment.
