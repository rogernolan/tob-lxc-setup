---
name: homelab-admin
description: Use when administering Rog's Proxmox homelab with tob-lxc-setup, preparing or configuring Debian/Ubuntu LXCs, creating or extending guest firewall policy, managing gateway Cloudflare DDNS, or publishing services through Caddy.
---

# Homelab Admin

Use the maintained tools in `/Users/rog/Development/tob-lxc-setup`. Read the relevant source and README before operating; if the checkout is unavailable, locate it or obtain the requested files at a reviewed immutable revision. Do not silently substitute fresh `main` code for reviewed payloads.

## Choose the execution context

| Task | Execute on | Guide |
| --- | --- | --- |
| Prepare a new LXC | Proxmox; Rog creates it by default | [LXC creation and configuration](references/lxc.md) |
| Configure guest OS/account/tools | Inside the selected Debian/Ubuntu LXC, as root | [LXC creation and configuration](references/lxc.md) |
| Set or extend guest firewall | Proxmox host, as root | [Guest firewalls](references/firewall.md) |
| Add DDNS alone | Gateway LXC, as root | [Gateway DDNS](references/ddns.md) |
| Publish a service, optionally including DNS | Gateway LXC, as root | [Caddy services](references/services.md) |

Read only the guides needed for the request. Creating this skill or discussing a plan does not authorize changes to live infrastructure. A request to configure a specific target authorizes that work; do not ask for the same permission again. Resolve unknown target identity, exposure, or required privileges before dependent changes.

## Establish access and identity

Repository records identify `tob-proxmox` at `192.168.68.81`, `tob-gateway` / VMID 101 at `192.168.68.71`, LAN `192.168.68.0/22`, and LAN IPv6 `fdbc:54c7:7b7e:4bdd::/64`. These are discovery hints, not confirmed current state. Connect as `rog` using existing SSH keys/configuration and verify hostname, addresses and role. Preserve SSH host-key checking; investigate a mismatch.

Use `pct list`, the selected guest's `pct config`/status and host-side `pct exec` to match VMID, hostname and addresses. Read `docs/lxc-firewall-rollout.md` for historical inventory, then check live listeners/configuration. Inventory, old approvals and test results do not authorize a fresh rollout. Guest 105 is the recorded disposable test LXC; do not borrow a production guest for tests.

Check `sudo -n -l` when elevation is needed. The repo grants passwordless status/log and selected service commands, plus Proxmox list/get commands; this is not blanket root access. Do not assume `pct config`, `pct exec`, installation or firewall apply can run unattended. If credentials or console interaction are required, prepare the exact command for Rog; never collect a password in chat or disable privilege checks.

Prefix local shell commands with `rtk`; use `rtk proxy` for SSH, SCP and script invocations when raw output matters. Remote hosts need not have RTK installed. Read the target's applicable `AGENTS.md`. Keep secret-bearing files and environments out of tool output.

## Finish with evidence

Retain the relevant before-state and recovery path, make the requested change, and verify fresh connections and actual service behavior. Report target, changed configuration, backup location, checks that passed and checks still pending. Distinguish previews, native validation, active policy and end-to-end verification. Use the official Codex attention mechanism when exposed by the session for a real user-action block or substantial long-running completion; follow Rog's global guidance and never use the legacy phone-alert helper.
