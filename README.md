# TOB LXC Setup

Small, repeatable setup for Debian and Ubuntu LXC guests on Proxmox.

The script installs common administration tools, installs the `xterm-ghostty` terminfo entry system-wide, creates the `rog` administrator account, configures sudo, installs Rog's public GitHub SSH keys, adds `/home/rog/AGENTS.md`, and enables SSH/Avahi when systemd is active. It also grants `rog` passwordless sudo for a small set of low-risk sysadmin commands; everything else still requires the password.

## Supported hosts

- Debian or Ubuntu LXC guests.
- Root access is required.
- The guest needs network access to its apt repositories and GitHub.
- The repository should be public for the credential-free bootstrap command.

Unsupported distributions fail before package or configuration changes are made.

## What is installed

The apt packages are:

`ca-certificates`, `curl`, `git`, `jq`, `locales`, `npm`, `openssh-client`, `openssh-server`, `ripgrep`, `sudo`, `tmux`, `ncurses-bin`, and `avahi-daemon`.

If `npm` is not already available, the package manager installs it separately; its package dependencies provide a compatible Node.js runtime.

The script also installs the OpenAI Codex CLI and the OpenCode CLI globally with npm:

```sh
npm install --global @openai/codex
npm install --global opencode-ai
```

After setup, run `codex` as `rog` and complete the interactive sign-in flow. See the [Codex CLI documentation](https://developers.openai.com/codex/cli/) for current authentication and usage details.

Run `opencode` as `rog` and use the `/connect` command to configure an LLM provider. See the [OpenCode documentation](https://opencode.ai/docs/) for authentication and usage details.

## Passwordless sudo

The `rog` account can run a small set of sysadmin commands with `sudo` without a password:

- `systemctl start`, `systemctl stop`, `systemctl restart`, and `systemctl status` for any unit.
- `journalctl` for system logs.
- `pvesh get`, `pct list`, and `qm list` when the Proxmox host tools are available.

The rules live in `/etc/sudoers.d/rog-nopasswd`, validated with `visudo` and installed with mode `0440`, so every other command still requires `rog`'s password through the base `ALL` rule. `systemctl` is whitelisted per subcommand, never as bare `systemctl`. The Proxmox tools (`pvesh`, `pct`, `qm`) are host commands; on guests where they are absent the corresponding rules simply never match.

Ghostty's `xterm-ghostty` definition is compiled with `tic -x` into `/usr/share/terminfo`, making it available to all users and commands run through `sudo`.

## Quick start

Review-first workflow:

```sh
wget -qO /tmp/tob-lxc-setup.sh https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/setup.sh
bash /tmp/tob-lxc-setup.sh --github-user rogernolan
```

Convenience one-liner for a trusted homelab host:

```sh
wget -qO- https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/setup.sh | bash -s -- --github-user rogernolan
```

The one-liner executes the current `main` branch as root. Review changes to the repository before using it on a host where supply-chain review matters.

## Local usage

```sh
./setup.sh --github-user rogernolan
```

The setup finishes non-interactively. Set the `rog` user's password afterward with `passwd rog`.

Use a local public-key file instead of GitHub:

```sh
./setup.sh --ssh-public-key-file /path/to/rog.pub
```

Show planned actions without changing the host:

```sh
./setup.sh --dry-run --github-user rogernolan
```

Options:

- `--github-user USER` fetches keys from `https://github.com/USER.keys`; default: `rogernolan`.
- `--ssh-public-key-file FILE` reads public keys from a local file.
- `--no-ssh-key` skips SSH key installation explicitly.
- `--dry-run` prints planned changes and skips mutations/network fetches.
- `--help` prints usage.

## Security and operational notes

- Only public SSH key text and validated repository payloads are downloaded from GitHub; downloaded shell code is never executed by the setup script.
- SSH key lines are restricted to Ed25519, ECDSA, and RSA OpenSSH public keys and are deduplicated by key type and material.
- The `rog` sudo rule is written to `/etc/sudoers.d/rog`, validated with `visudo`, and installed with mode `0440`.
- Existing `/home/rog/AGENTS.md` is preserved. Existing user data and unrelated system configuration are not overwritten.
- SSH public-key installation is mandatory. After at least one accepted key is installed for `rog`, the script warns and configures SSH to require public keys, disabling password, keyboard-interactive/challenge-response, GSSAPI/Kerberos, and empty-password authentication.
- If no accepted SSH key is available, setup fails before SSH authentication hardening is applied. Use console access to recover from an unexpected key problem.
- The script does not configure firewall rules, change hostnames, change timezones, or customize shells.
- Package upgrades can restart services or change system behavior. Run the script during a suitable maintenance window.
- `en_GB.UTF-8` is generated so SSH sessions that request that locale do not produce Bash warnings; existing `LANG` and locale policy are otherwise preserved.
- Repeat runs are expected and should converge without duplicate users, group membership, SSH keys, or guidance files.
- Passwordless sudo is limited to `systemctl start/stop/restart/status`, `journalctl`, `pvesh get`, `pct list`, and `qm list`, in a separate `visudo`-validated `/etc/sudoers.d/rog-nopasswd` file with mode `0440`. All other commands require `rog`'s password via the base `ALL` rule.

## Caddy host manager

[`scripts/add-caddy-host`](scripts/add-caddy-host) adds a `hatbat.net`
reverse-proxy hostname to a gateway that already has Caddy and the Cloudflare
DDNS service installed. It is intentionally not run by `setup.sh`, because it
is specific to the gateway LXC.

The gateway must provide:

- `/etc/caddy/Caddyfile`, containing
  `import /etc/caddy/sites-enabled/*.caddy`;
- `/etc/cloudflare-ddns/cloudflare-ddns.env`, with `CF_ALIASES` and the
  root-only Cloudflare credentials;
- `/usr/local/sbin/cloudflare-ddns`;
- working Caddy and systemd services.

The normal remote workflow installs the command and then invokes the installed
copy. For a review-first workflow, download both scripts, inspect them, and
run the installer as root:

```sh
wget -qO /tmp/install-caddy-host.sh \
  https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/install-caddy-host
wget -qO /tmp/add-caddy-host.sh \
  https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/add-caddy-host
sudo sh /tmp/install-caddy-host.sh \
  --payload-file /tmp/add-caddy-host.sh -- \
  app.hatbat.net http://192.168.68.20:8080
```

The `--payload-file` option makes the installer use the inspected local copy
instead of downloading the payload again. The `--` separates installer options
from arguments passed to `add-caddy-host`.

For the usual install-and-run path, stream only the installer. It downloads
and installs `/usr/local/sbin/add-caddy-host` before invoking it:

```sh
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/install-caddy-host \
  | sudo sh -s -- app.hatbat.net http://192.168.68.20:8080
```

For an HTTPS upstream with a self-signed or otherwise untrusted certificate,
the verification bypass must be requested explicitly:

```sh
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/install-caddy-host \
  | sudo sh -s -- --insecure-upstream-tls \
    admin.hatbat.net https://192.168.68.30:8443
```

If the remote command needs to change, or for a temporary one-off operation,
the command can instead be invoked directly without installing it. This is a
fallback path and does not update `/usr/local/sbin/add-caddy-host`:

```sh
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/add-caddy-host \
  | sudo sh -s -- app.hatbat.net http://192.168.68.20:8080
```

The command accepts only lowercase `hatbat.net` subdomains and RFC1918 IPv4
upstreams with explicit ports. It probes the upstream, serializes operations
with `flock`, creates root-only backups in `/var/backups/caddy-hosts`, writes a
dedicated file under `/etc/caddy/sites-enabled`, adds the hostname to
`CF_ALIASES`, updates Cloudflare DNS, validates and reloads Caddy, and performs
a local HTTPS check. Configuration changes are rolled back if validation, DNS
update, or reload fails. Use `--force` only to replace an existing host file
after inspecting it.

## Verification

Run the local fake-root test suite:

```sh
bash -n setup.sh tests/test_setup.sh
sh -n scripts/add-caddy-host scripts/install-caddy-host
bash tests/test_setup.sh
bash tests/test_caddy_remote.sh
```

The tests do not modify the development machine or require a live LXC.
