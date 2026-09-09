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

## Proxmox LXC firewall (initial test release)

`setup.sh` configures the OS inside a guest. The separate
`scripts/configure-lxc-firewall` command runs **as root on Proxmox** and manages
native guest firewall policy. Caddy publication remains independent.

The adapter requires the verified `pve-firewall` package version **6.0.4**
and a local, unlocked LXC with exactly one supported bridged NIC. Live testing
has only changed **105 / tob-test-lxc**. Review the
[rollout inventory](docs/lxc-firewall-rollout.md) before selecting other guests.
The native validator and local failure tests pass. Live tests on 105 verified
SSH, DNS/HTTPS, application-port allow/block transitions, idempotence and
restriction persistence after reboot. See [test evidence](docs/lxc-firewall-investigation.md)
for unrun tests and limitations.

Install on the Proxmox host using a pinned commit. The one-shot command below
installs the complete bundle; it does **not** change any guest firewall:

```sh
curl -fsSL https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/963028907cc2df2874e5285446b39ca974a6f329/scripts/install-lxc-firewall | sudo bash -s -- --ref 963028907cc2df2874e5285446b39ca974a6f329
```

For installation followed by a preview, append `-- 105 ssh-only --dry-run`.
To apply, run the installed command explicitly:

```sh
sudo configure-lxc-firewall 105 ssh-only --dry-run
sudo configure-lxc-firewall 105 ssh-only
sudo configure-lxc-firewall 105 application --port 8080 --port 9090 --dry-run
```

For a review-first installation, download a checkout at the same commit, inspect
its `scripts/` directory, then run
`sudo bash scripts/install-lxc-firewall --payload-dir scripts`.
The installer copies the exact local payload or downloads every helper from the
specified immutable commit, checks syntax using Proxmox's libraries, and
atomically replaces `/usr/local/sbin/configure-lxc-firewall`. Complete releases
remain under `/usr/local/lib/tob-lxc-firewall/releases/`; an already running
command keeps using its original helpers. Rerun the installer with a newer
reviewed commit to upgrade. A failed download or validation leaves the previous
installed command usable. The installer does not alter Proxmox firewall services.

| Profile | Allowed service ports from either trusted LAN subnet |
| --- | --- |
| `ssh-only` | TCP 22 |
| `application` | TCP 22 plus required `--port` values |
| `lan-smb` | TCP 22 and direct SMB TCP 445 |
| `development` | All TCP from gateway 192.168.68.71; TCP 22 from both LAN subnets |
| `unrestricted` | Guest enforcement disabled; no inbound isolation |

LAN clients and Tailscale connections SNATed through `192.168.68.71` share
this access tier. Applications may also be published through Caddy on that
gateway, without changing guest firewall rules. Direct clients bypass controls
provided solely by Caddy, so application authentication must account for them.
By default, each selected service port allows both `192.168.68.0/22` and the local IPv6
subnet `fdbc:54c7:7b7e:4bdd::/64`. Other source subnets remain blocked.

For `application` and `lan-smb`, `--service-source gateway` restricts service
ports to `192.168.68.71`, retaining SSH from both LAN subnets. `development`
always uses gateway-only service access and allows arbitrary TCP ports; this
does not inspect whether traffic is HTTPS. Gateway access includes Caddy and
other gateway-originated connections as well as SNATed Tailscale clients.
This is the approved treatment for tob-files and tob-dev respectively.

Restrictive profiles use inbound DROP, outbound ACCEPT, native DHCP support
and a LAN UDP 5353 allowance for local name resolution. Testing on 105 showed
that `.local` SSH selects a ULA IPv6 address. With the matching IPv6 service allowances, a fresh `.local` SSH connection
used IPv6 directly in 0.53 seconds, with no IPv4 fallback; it does not trust `fe80::/10` or all IPv6 sources.
This subnet is specific to the current LAN and must be reviewed if addressing
changes. Discovery over Tailscale is not promised. The command does not change Avahi, Samba or Caddy configuration.
`lan-smb` is for direct SMB2/SMB3 access by name/address, not NetBIOS browsing.
It opens no TCP/UDP 137–139 or UDP 445 ports. Samba itself must disable SMB1;
a port rule cannot enforce its negotiated protocol version.

Dry-run renders the proposal without writes or native validation. Apply takes
a private snapshot, compiles the existing and proposed configurations outside
`/etc/pve`, and treats native parser warnings as errors. Only a validated
candidate is published. For a running guest, it waits for Proxmox's IPv4 and
IPv6 guest-chain signatures to match. A stopped guest remains stopped and is
reported as configured with runtime verification pending.

Only single-NIC bridged guests are supported. The full NIC configuration is
preserved, changing only its firewall flag when needed. Unmarked guest firewall
files and unknown managed versions are refused. The tool owns the complete
marked file; manual edits to it will be replaced on a later apply. No generic
force/adoption option is provided.

Application failures attempt to restore the prior policy and NIC configuration.
Private recovery state is retained under `/var/backups/tob-lxc-firewall/VMID/`.
All guest applies share `/var/backups/tob-lxc-firewall/lock`; if another operation
is running, retry after it finishes. The lock covers capture, validation,
activation and recovery.
`previous.json` holds the last successful operation's prior state;
`pending.json` means recovery is unresolved and blocks another apply. Concurrent
GUI/API edits are unsupported; detected external changes are not overwritten.
No changes are made to host/Datacenter policies or generated kernel chains.

### Inspection and recovery for the initial test guest

Inspect from Proxmox:

```sh
sudo pct config 105
sudo cat /etc/pve/firewall/105.fw
sudo pve-firewall status
```

Before applying, retain a copy of 105's current configuration and review the
recovery snapshot. For the **specific NIC configuration captured during this
work**, emergency network recovery is:

```sh
sudo pct set 105 --net0 'name=eth0,bridge=vmbr0,firewall=0,hwaddr=BC:24:11:68:9F:3B,ip=dhcp,type=veth'
```

This deliberately disables guest NIC isolation. Recheck the NIC first if it
has changed; do not reuse that command for another guest. The original state
had `firewall=1` and no guest policy file. Restore the exact original state or
the recorded prior policy after diagnosing the failure. Do not simply delete
`pending.json` and rerun: inspect its `before`/`desired` data and reconcile the
actual configuration first. Never stop the host-wide firewall for guest
recovery. Host-side `pct exec 105 -- ...` remains available if guest networking
is lost.

## Verification

Run the local fake-root test suite:

```sh
bash -n setup.sh tests/test_setup.sh
sh -n scripts/add-caddy-host scripts/install-caddy-host
bash tests/test_setup.sh
bash tests/test_caddy_remote.sh
bash tests/test_lxc_firewall.sh
bash tests/test_lxc_firewall_install.sh
perl tests/test_lxc_firewall_target.pl
perl tests/test_lxc_firewall_transaction.pl
```

The tests do not modify the development machine or require a live LXC.

On Proxmox, the native compiler fixture test runs without sudo and only writes
temporary files:

```sh
perl tests/test_lxc_firewall_native.pl scripts/lxc-firewall-validate
```

`sudo perl scripts/check-lxc-firewall 105` additionally validates candidate
service policies against copies of the actual local configuration. It does
not apply policy or start the guest.
