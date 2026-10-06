# LXC creation and configuration

Repository: `/Users/rog/Development/tob-lxc-setup`.

## New container

Rog creates LXCs manually by default. Prepare the Proxmox creation settings and a concise handoff rather than running `pct create`, cloning a guest or downloading/executing a community creation script. The repo has no LXC creation tool. If Rog explicitly delegates creation, establish the concrete parameters and use the installed Proxmox tools/documentation; the manual default is not a permanent prohibition.

Discover available VMIDs, templates, storage capacity and bridges. Establish hostname, Debian/Ubuntu template, CPU, RAM, disk, storage, bridge, DHCP/static addressing and intended service. Prefer an unprivileged guest unless its requirements justify something else; nesting, device passthrough and mounts depend on the service. Do not copy another guest's MAC, IP, secrets or storage bindings. Give Rog the selected settings, then verify the resulting VMID/configuration before bootstrap. Inspect storage and guest requirements before proposing features or mounts.

## Existing or newly created guest

Read `setup.sh`, `README.md` and `files/rog/AGENTS.md`. Inspect guest `/etc/os-release`, identity, networking, disk space, existing `rog` account/keys, SSH and systemd state. Keep Proxmox console/`pct exec` access available: setup changes SSH authentication after installing keys.

Stage the reviewed checkout inside the guest, including `setup.sh` and `files/`. Transfer the same reviewed revision, preserving paths, instead of installing a second download. The script can fetch missing guidance/terminfo from `main`; include `files/rog/AGENTS.md` and `files/terminfo/ghostty.terminfo` to keep those payloads local. Public SSH keys still come from GitHub unless a local public-key file is selected.

Inside the guest, from the staged repository directory, preview and then apply the authorized bootstrap:

```sh
bash setup.sh --dry-run --github-user rogernolan
bash setup.sh --github-user rogernolan
```

These commands require root, including preview. When invoking from the Mac, wrap the remote invocation with `rtk proxy ssh`; run the root command through authorized `sudo` or the Proxmox console. A local public key can instead be supplied with `--ssh-public-key-file PATH`. Current `setup.sh --help` and parser are authoritative; do not rely on historical README options unsupported by the parser.

Setup upgrades packages, installs admin tools and Codex/OpenCode CLIs, configures the `rog` account/sudo rules, installs public keys, hardens SSH, installs Ghostty terminfo and starts SSH/Avahi when systemd is active. It preserves an existing `/home/rog/AGENTS.md`. It does not set hostname, timezone, network configuration or firewall policy. Treat those as separate work when requested; never run guest bootstrap on Proxmox itself.

Have Rog set `passwd rog` through a private console/terminal if a sudo password is needed. CLI provider sign-in is a separate manual step when requested, not evidence of failed bootstrap.

Verify a fresh SSH connection as `rog` before closing recovery access; inspect installed packages, sudo rules with `visudo`, SSH configuration with `sshd -t`, SSH/Avahi service state, and `infocmp xterm-ghostty` as `rog`. Report anything requiring manual sign-in. Configure the guest firewall separately using [firewall.md](firewall.md), and use [services.md](services.md) only when gateway publication is part of the request.
