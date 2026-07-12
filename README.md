# TOB LXC Setup

Small, repeatable setup for Debian and Ubuntu LXC guests on Proxmox.

The script installs common administration tools, creates the `rog` administrator account, configures sudo, installs Rog's public GitHub SSH keys, adds `/home/rog/AGENTS.md`, and enables SSH/Avahi when systemd is active.

## Supported hosts

- Debian or Ubuntu LXC guests.
- Root access is required.
- The guest needs network access to its apt repositories and GitHub.
- The repository should be public for the credential-free bootstrap command.

Unsupported distributions fail before package or configuration changes are made.

## What is installed

The apt packages are:

`ca-certificates`, `curl`, `git`, `jq`, `locales`, `nodejs`, `npm`, `openssh-client`, `openssh-server`, `ripgrep`, `sudo`, `tmux`, and `avahi-daemon`.

The script also installs the OpenAI Codex CLI globally with npm:

```sh
npm install --global @openai/codex
```

After setup, run `codex` as `rog` and complete the interactive sign-in flow. See the [Codex CLI documentation](https://developers.openai.com/codex/cli/) for current authentication and usage details.

## Quick start

Review-first workflow:

```sh
wget -qO /tmp/tob-lxc-setup.sh https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/setup.sh
less /tmp/tob-lxc-setup.sh
bash /tmp/tob-lxc-setup.sh --github-user rogernolan
rm -f /tmp/tob-lxc-setup.sh
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

The first run prompts twice for the `rog` user's password. Repeat runs preserve the existing password, and `--dry-run` does not prompt.

Use a local public-key file instead of GitHub:

```sh
./setup.sh --ssh-public-key-file /path/to/rog.pub
```

Create the account without configuring SSH keys:

```sh
./setup.sh --no-ssh-key
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

- Only public SSH key text is downloaded from GitHub; downloaded shell code is never executed by the setup script.
- SSH key lines are restricted to Ed25519, ECDSA, and RSA OpenSSH public keys and are deduplicated by key type and material.
- The `rog` sudo rule is written to `/etc/sudoers.d/rog`, validated with `visudo`, and installed with mode `0440`.
- Existing `/home/rog/AGENTS.md` is preserved. Existing user data and unrelated system configuration are not overwritten.
- The script does not configure firewall rules, disable SSH password authentication, change hostnames, change timezones, or customize shells.
- Package upgrades can restart services or change system behavior. Run the script during a suitable maintenance window.
- `en_GB.UTF-8` is generated so SSH sessions that request that locale do not produce Bash warnings; existing `LANG` and locale policy are otherwise preserved.
- Repeat runs are expected and should converge without duplicate users, group membership, SSH keys, or guidance files.

## Verification

Run the local fake-root test suite:

```sh
bash -n setup.sh tests/test_setup.sh
bash tests/test_setup.sh
```

The tests do not modify the development machine or require a live LXC.
