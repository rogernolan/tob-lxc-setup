# Guest firewalls: initial policy and extensions

Run on Proxmox, never inside the guest. Read the repo's `scripts/configure-lxc-firewall`, `scripts/install-lxc-firewall`, `README.md` and `docs/lxc-firewall-rollout.md`. The current apply adapter requires exactly `pve-firewall 6.0.4` with the verified legacy backend. Inspect installed versions/backend; do not bypass the version guard or switch firewall backends to make an apply work.

## Inspect and install

Match VMID to the live hostname/config/status, inspect `/etc/pve/firewall/VMID.fw`, full NIC properties, relevant host/Datacenter settings and actual guest TCP/UDP listeners. Confirm console/`pct exec` recovery access and retain exact NIC/file before-state. Only a local, unlocked LXC with one supported bridged NIC is supported. `tob-gateway` / 101 is a router and needs a separate policy; do not apply these application profiles to it.

If the bundle is missing or stale, review the full `scripts/` payload and install it on Proxmox:

```sh
sudo bash /path/to/reviewed/scripts/install-lxc-firewall \
  --payload-dir /path/to/reviewed/scripts
```

The paths above refer to the same staged checkout on Proxmox. Alternatively use `--ref` with a reviewed full lowercase 40-character commit, with the installer itself reviewed from that revision. Install the complete bundle, including both Perl modules and validation/apply helpers. Installation alone does not change policy. Do not run `setup.sh` on Proxmox.

## Select policy

| Profile | Service allowance |
| --- | --- |
| `ssh-only` | No extra service ports |
| `application` | Complete list of TCP `--port` and/or UDP `--udp-port` arguments |
| `lan-smb` | TCP 445; SMB2/3 configuration remains the guest's responsibility |
| `development` | All TCP from the gateway; no arbitrary UDP addition option |
| `unrestricted` | Guest enforcement disabled; no inbound isolation |

Restrictive profiles retain LAN SSH TCP 22 and mosh UDP 60000–61000 over both configured LAN families, LAN IPv4 mDNS UDP 5353, DHCP support and outbound ACCEPT. `application`/`lan-smb` default to both trusted LAN subnets for service ports. `--service-source gateway` allows those services only from IPv4 `192.168.68.71`, while retaining LAN SSH/mosh. `development` always uses gateway service access.

Choose exposure from the request. Caddy-only application access usually needs the selected application ports with gateway scope. LAN clients otherwise bypass Caddy's controls. Tailscale subnet clients are recorded as SNATed through the gateway; a source-IP rule cannot distinguish them from Caddy or other gateway connections. Confirm the live route/source when testing. Do not invent independent per-port scopes or protocol inspection this tool cannot express.

## Extending an existing policy

The tool replaces its **entire managed file**; `--port` and `--udp-port` are not incremental operations. Recover the current profile, source scope and complete TCP/UDP allowance list from the live managed file and intended requirements. Merge the requested additions into that full list. Convert stored inclusive `START:END` ranges to CLI `START-END`; preserve existing ranges and UDP allowances. Exact duplicates are normalized; overlaps remain separate rules.

Example: if live policy is `application`, gateway scope, TCP 8080 and 9090 plus UDP 2021, adding TCP 8765 needs every allowance:

```sh
sudo configure-lxc-firewall 106 application \
  --service-source gateway \
  --port 8080 --port 9090 --port 8765 --udp-port 2021 --dry-run
```

106 and these existing ports are illustrative, not an inventory claim. Substitute the verified target and complete live policy. Compare old/new rendered rules: only the requested ports/exposure should change. A new call with just `--port 8765` would remove the other service allowances.

Unmarked files, unknown format versions or custom rules that cannot be represented by the profiles require reconciliation; do not force adoption or overwrite them. Adding UDP to `development`, or preserving mixed source scopes, requires a design choice/tool change rather than silently switching profiles and losing access.

## Apply, verify and recover

Run the exact full command with `--dry-run` first. Preview writes nothing and is **not native validation**. Apply without that flag only within the authorized target/exposure. Apply validates the current/candidate context outside `/etc/pve`, captures recovery state, publishes the managed policy/NIC change and checks running-guest IPv4/IPv6 chain signatures. A stopped guest remains stopped and has runtime verification pending; starting it is a separate action.

Verify fresh SSH, DNS/HTTPS egress, existing allowed services and the new service from intended sources. Exercise UDP with actual request/response, not a TCP check or ambiguous UDP scan. To prove filtering, confirm an unlisted listener and network path were reachable before restriction and the listener still runs afterward. Record unavailable IPv6/Tailscale paths as untested. Broader profile/range changes should first use the verified disposable guest 105; restore its baseline and remove only fixtures created for that test.

Recovery state is `/var/backups/tob-lxc-firewall/VMID/`: `previous.json` records prior successful-operation state; `pending.json` blocks apply when recovery is unresolved. Inspect and reconcile state instead of deleting `pending.json` or retrying blindly. Preserve concurrent external edits. For emergency NIC isolation disablement, derive `pct set VMID --netN` from the captured **full** NIC property, changing only `firewall=0`; keep bridge, MAC, address and all other properties. Never reuse 105's NIC string for another guest, alter host/Datacenter rules, edit generated kernel chains or stop the host-wide firewall for guest recovery.
